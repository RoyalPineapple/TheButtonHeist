import Network
import XCTest
@testable import ButtonHeist
import TheScore

// MARK: - Test Helpers

extension DeviceConnection {
    /// Sets the connection into `.connected` state for testing.
    /// The NWConnection is never started — only the state enum matters.
    func simulateConnected() {
        let dummyConnection = NWConnection(host: "127.0.0.1", port: 1, using: .tcp)
        connectionState = .connected(ActiveConnection(connection: dummyConnection))
    }
}

@ButtonHeistActor
func assertDeviceConnectionConnected(
    _ connection: DeviceConnection,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .connected = connection.connectionState { return }
    XCTFail("Expected device connection to be connected, got \(connection.connectionState)", file: file, line: line)
}

@ButtonHeistActor
func assertDeviceConnectionDisconnected(
    _ connection: DeviceConnection,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .disconnected = connection.connectionState { return }
    XCTFail("Expected device connection to be disconnected, got \(connection.connectionState)", file: file, line: line)
}

/// Pattern-match helpers for `HandoffConnectionPhase`. Replaces the
/// dropped `Equatable` conformance — production code never compared phases
/// for equality.
@ButtonHeistActor
func assertDisconnected(
    _ phase: HandoffConnectionPhase,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .disconnected = phase { return }
    XCTFail("Expected .disconnected, got \(phase)", file: file, line: line)
}

@ButtonHeistActor
func assertConnected(
    _ phase: HandoffConnectionPhase,
    device expected: DiscoveredDevice? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .connected(let session) = phase else {
        XCTFail("Expected .connected, got \(phase)", file: file, line: line)
        return
    }
    if let expected {
        XCTAssertEqual(session.device, expected, file: file, line: line)
    }
}

@ButtonHeistActor
func assertConnecting(
    _ phase: HandoffConnectionPhase,
    device expected: DiscoveredDevice,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .connecting(let attempt) = phase else {
        XCTFail("Expected .connecting, got \(phase)", file: file, line: line)
        return
    }
    XCTAssertEqual(attempt.device, expected, file: file, line: line)
}

@ButtonHeistActor
func assertReconnecting(
    _ phase: HandoffConnectionPhase,
    device expected: DiscoveredDevice,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .reconnecting(let attempt) = phase else {
        XCTFail("Expected .reconnecting, got \(phase)", file: file, line: line)
        return
    }
    XCTAssertEqual(attempt.target.device, expected, file: file, line: line)
}

@ButtonHeistActor
func assertFailed(
    _ phase: HandoffConnectionPhase,
    failure expected: HandoffConnectionError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .failed(let failure) = phase else {
        XCTFail("Expected .failed(\(expected)), got \(phase)", file: file, line: line)
        return
    }
    XCTAssertEqual(failure, expected, file: file, line: line)
}

/// Drive `TheHandoff` through a mock connection to land in `.connected`.
/// Returns the mock so the caller can inspect sent messages or trigger
/// further events. The mock does not auto-emit `.info` so the caller can
/// drive `handleServerMessage(.info(...))` explicitly when needed.
@ButtonHeistActor
@discardableResult
func connectMockHandoff(
    _ handoff: TheHandoff,
    device: DiscoveredDevice = DiscoveredDevice(host: "127.0.0.1", port: 1234)
) -> MockConnection {
    let mock = MockConnection()
    handoff.makeConnection = { _, _, _ in mock }
    handoff.connect(to: device)
    return mock
}

// MARK: - Mock Implementations for DeviceConnecting / DeviceDiscovering

@ButtonHeistActor
final class MockConnection: TransportReachabilityConnecting {
    var isConnected = false
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var onTransportReady: (@ButtonHeistActor () -> Void)?
    var sent: [(ClientMessage, String?)] = []
    var connectCount = 0
    var disconnectCount = 0
    var emitTransportReadyOnConnect = false
    var connectEventsOverride: [ConnectionEvent]?
    var sendOutcome: DeviceSendOutcome = .enqueued
    var asyncSendFailure: DeviceSendFailure?
    var batchStepDurationMs: Int = 0

    var serverInfo: ServerInfo?

    func connect() {
        connectCount += 1
        isConnected = true
        if let connectEventsOverride {
            for event in connectEventsOverride {
                onEvent?(event)
            }
            return
        }
        if emitTransportReadyOnConnect {
            onTransportReady?()
        }
        onEvent?(.connected)
        if let info = serverInfo {
            onEvent?(.message(.info(info), requestId: nil))
        }
    }

    func disconnect() {
        disconnectCount += 1
        isConnected = false
    }

    @discardableResult
    func send(_ message: ClientMessage, requestId: String?) -> DeviceSendOutcome {
        guard sendOutcome == .enqueued else { return sendOutcome }
        sent.append((message, requestId))
        if let asyncSendFailure {
            Task { @ButtonHeistActor [self] in
                self.onEvent?(.sendFailed(asyncSendFailure, requestId: requestId))
            }
        }
        if let handler = autoResponse {
            let response = batchExecutionResponse(for: message, handler: handler) ?? handler(message)
            Task { @ButtonHeistActor [self] in
                self.onEvent?(.message(response, requestId: requestId))
            }
        }
        return .enqueued
    }

    var autoResponse: ((ClientMessage) -> ServerMessage)?

    private func batchExecutionResponse(
        for message: ClientMessage,
        handler: (ClientMessage) -> ServerMessage
    ) -> ServerMessage? {
        guard case .batchExecutionPlan(let plan) = message else { return nil }

        var stepResults: [BatchExecutionStepResult] = []
        var failedIndex: Int?
        for (index, step) in plan.steps.enumerated() {
            if let failedIndex {
                let skipped = BatchExecutionSkippedStepResult(
                    index: index,
                    reason: "skipped: stop_on_error stopped batch after step \(failedIndex)",
                    afterFailedIndex: failedIndex
                )
                stepResults.append(BatchExecutionStepResult(
                    index: index,
                    durationMs: batchStepDurationMs,
                    skipped: skipped
                ))
                continue
            }

            let actionResult = actionResult(for: step.command, handler: handler)
            let expectation = actionResult.success ? step.expectation.validate(against: actionResult) : nil
            let shouldStop = plan.policy == .stopOnError
                && (actionResult.success == false || expectation?.met == false)
            stepResults.append(BatchExecutionStepResult(
                index: index,
                actionResult: actionResult,
                expectation: expectation,
                durationMs: batchStepDurationMs,
                stopsBatch: shouldStop
            ))
            if shouldStop {
                failedIndex = index
            }
        }

        let result = BatchExecutionResult(
            policy: plan.policy,
            steps: stepResults,
            totalTimingMs: 0,
            failedIndex: failedIndex
        )
        return .actionResult(ActionResult(
            success: failedIndex == nil,
            method: .batchExecutionPlan,
            errorKind: failedIndex == nil ? nil : .actionFailed,
            payload: .batchExecution(result)
        ))
    }

    private func actionResult(
        for command: ClientMessage,
        handler: (ClientMessage) -> ServerMessage
    ) -> ActionResult {
        switch handler(command) {
        case .actionResult(let result):
            return result
        case .error(let error):
            return ActionResult(
                success: false,
                method: actionMethod(for: command),
                message: error.message,
                errorKind: .general
            )
        default:
            return ActionResult(success: true, method: .activate)
        }
    }

    private func actionMethod(for command: ClientMessage) -> ActionMethod {
        switch command {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
        case .rotor: return .rotor
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .getPasteboard: return .getPasteboard
        case .resignFirstResponder: return .resignFirstResponder
        case .oneFingerTap: return .syntheticTap
        case .longPress: return .syntheticLongPress
        case .swipe: return .syntheticSwipe
        case .drag: return .syntheticDrag
        case .pinch: return .syntheticPinch
        case .rotate: return .syntheticRotate
        case .twoFingerTap: return .syntheticTwoFingerTap
        case .drawPath, .drawBezier: return .syntheticDrawPath
        case .typeText: return .typeText
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .elementSearch: return .elementSearch
        case .scrollToEdge: return .scrollToEdge
        case .waitForIdle: return .waitForIdle
        case .waitFor: return .waitFor
        case .waitForChange: return .waitForChange
        case .batchExecutionPlan: return .batchExecutionPlan
        case .clientHello, .authenticate, .requestInterface,
             .ping, .status, .requestScreen:
            return .batchExecutionPlan
        }
    }
}

@ButtonHeistActor
final class MockDiscovery: DeviceDiscovering {
    var discoveredDevices: [DiscoveredDevice] = []
    var onEvent: (@ButtonHeistActor (DiscoveryEvent) -> Void)?
    var startCount = 0
    var stopCount = 0

    func start() {
        startCount += 1
        onEvent?(.stateChanged(isReady: true))
        for device in discoveredDevices {
            onEvent?(.found(device))
        }
    }

    func stop() {
        stopCount += 1
    }
}

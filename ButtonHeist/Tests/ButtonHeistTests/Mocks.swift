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

/// Pattern-match helpers for `TheHandoff.ConnectionPhase`. Replaces the
/// dropped `Equatable` conformance — production code never compared phases
/// for equality.
@ButtonHeistActor
func assertDisconnected(
    _ phase: TheHandoff.ConnectionPhase,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .disconnected = phase { return }
    XCTFail("Expected .disconnected, got \(phase)", file: file, line: line)
}

@ButtonHeistActor
func assertConnected(
    _ phase: TheHandoff.ConnectionPhase,
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
    _ phase: TheHandoff.ConnectionPhase,
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
func assertFailed(
    _ phase: TheHandoff.ConnectionPhase,
    failure expected: TheHandoff.ConnectionError,
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
final class MockConnection: DeviceConnecting {
    var isConnected = false
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var sent: [(ClientMessage, String?)] = []
    var connectCount = 0
    var disconnectCount = 0
    var emitTransportReadyOnConnect = false
    var connectEventsOverride: [ConnectionEvent]?
    var sendOutcome: DeviceSendOutcome = .enqueued
    var asyncSendFailure: DeviceSendFailure?

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
            onEvent?(.transportReady)
        }
        onEvent?(.connected)
        if let info = serverInfo {
            onEvent?(.message(.info(info), requestId: nil, accessibilityTrace: nil))
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
                self.onEvent?(.message(response, requestId: requestId, accessibilityTrace: nil))
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
                    actionName: step.action.testCommandName,
                    expectationName: step.expectation.summaryDescription,
                    reason: "skipped: stop_on_error stopped batch after step \(failedIndex)",
                    afterFailedIndex: failedIndex
                )
                stepResults.append(BatchExecutionStepResult(
                    index: index,
                    actionName: step.action.testCommandName,
                    expectationName: step.expectation.summaryDescription,
                    durationMs: 0,
                    skipped: skipped
                ))
                continue
            }

            let actionResult = actionResult(for: step.action, handler: handler)
            let expectation = actionResult.success ? step.expectation.validate(against: actionResult) : nil
            let shouldStop = plan.policy == .stopOnError
                && (actionResult.success == false || expectation?.met == false)
            stepResults.append(BatchExecutionStepResult(
                index: index,
                actionName: step.action.testCommandName,
                expectationName: step.expectation.summaryDescription,
                actionResult: actionResult,
                expectation: expectation,
                durationMs: 0,
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
        for action: TheScore.Action,
        handler: (ClientMessage) -> ServerMessage
    ) -> ActionResult {
        guard let message = action.testClientMessage else {
            return ActionResult(
                success: true,
                method: .waitForChange,
                message: action.testCommandName
            )
        }
        switch handler(message) {
        case .actionResult(let result):
            return result
        case .error(let error):
            return ActionResult(
                success: false,
                method: .unsupportedCommand,
                message: error.message,
                errorKind: .general
            )
        default:
            return ActionResult(success: true, method: .activate)
        }
    }
}

private extension TheScore.Action {
    var testCommandName: String {
        switch self {
        case .activate: return "activate"
        case .increment: return "increment"
        case .decrement: return "decrement"
        case .performCustomAction: return "perform_custom_action"
        case .rotor: return "rotor"
        case .touchTap: return "tap"
        case .touchLongPress: return "long_press"
        case .touchSwipe: return "swipe"
        case .touchDrag: return "drag"
        case .touchPinch: return "pinch"
        case .touchRotate: return "rotate"
        case .touchTwoFingerTap: return "two_finger_tap"
        case .touchDrawPath: return "draw_path"
        case .touchDrawBezier: return "draw_bezier"
        case .typeText: return "type_text"
        case .editAction: return "edit_action"
        case .setPasteboard: return "set_pasteboard"
        case .scroll: return "scroll"
        case .scrollToVisible: return "scroll_to_visible"
        case .elementSearch: return "element_search"
        case .scrollToEdge: return "scroll_to_edge"
        case .waitForIdle: return "wait_for_idle"
        case .waitForElement: return "wait_for"
        case .waitForChange: return "wait_for_change"
        case .explore: return "explore"
        case .resignFirstResponder: return "dismiss_keyboard"
        }
    }

    var testClientMessage: ClientMessage? {
        switch self {
        case .activate(let target):
            return .activate(target.executableTarget)
        case .increment(let target):
            return .increment(target.executableTarget)
        case .decrement(let target):
            return .decrement(target.executableTarget)
        case .performCustomAction(let target):
            if let elementTarget = target.target {
                return .performCustomAction(CustomActionTarget(
                    elementTarget: elementTarget.executableTarget,
                    actionName: target.actionName
                ))
            }
            guard let containerTarget = target.containerTarget else { return nil }
            return .performCustomAction(CustomActionTarget(
                containerTarget: containerTarget,
                ordinal: target.containerOrdinal,
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.target.executableTarget,
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: target.direction,
                currentHeistId: target.currentSourceHeistId,
                currentTextRange: target.currentTextRange
            ))
        case .touchTap(let target):
            return .touchTap(TouchTapTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY
            ))
        case .touchLongPress(let target):
            return .touchLongPress(LongPressTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY,
                duration: target.duration
            ))
        case .touchSwipe(let target):
            return .touchSwipe(SwipeTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                direction: target.direction,
                duration: target.duration,
                start: target.start,
                end: target.end
            ))
        case .touchDrag(let target):
            return .touchDrag(DragTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                duration: target.duration
            ))
        case .touchPinch(let target):
            return .touchPinch(PinchTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                scale: target.scale,
                spread: target.spread,
                duration: target.duration
            ))
        case .touchRotate(let target):
            return .touchRotate(RotateTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                angle: target.angle,
                radius: target.radius,
                duration: target.duration
            ))
        case .touchTwoFingerTap(let target):
            return .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                spread: target.spread
            ))
        case .touchDrawPath(let target):
            return .touchDrawPath(target)
        case .touchDrawBezier(let target):
            return .touchDrawBezier(target)
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.target?.executableTarget
            ))
        case .editAction(let target):
            return .editAction(target)
        case .setPasteboard(let target):
            return .setPasteboard(target)
        case .scroll(let target):
            return .scroll(ScrollTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.target?.executableTarget
            ))
        case .elementSearch(let target):
            return .elementSearch(ElementSearchTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                elementTarget: target.target?.executableTarget,
                edge: target.edge
            ))
        case .waitForIdle(let target):
            return .waitForIdle(target)
        case .waitForElement(let target):
            return .waitFor(WaitForTarget(
                elementTarget: target.target.executableTarget,
                absent: target.absent,
                timeout: target.timeout
            ))
        case .waitForChange(let target):
            return .waitForChange(target)
        case .explore:
            return .explore
        case .resignFirstResponder:
            return .resignFirstResponder
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

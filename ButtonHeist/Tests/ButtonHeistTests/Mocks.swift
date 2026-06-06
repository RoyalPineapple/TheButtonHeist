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
    handoff.makeConnection = { _ in mock }
    handoff.connect(to: device)
    return mock
}

@ButtonHeistActor
@discardableResult
func connectPendingMockHandoff(
    _ handoff: TheHandoff,
    device: DiscoveredDevice = DiscoveredDevice(host: "127.0.0.1", port: 1234)
) -> MockConnection {
    let mock = MockConnection()
    mock.connectEventsOverride = []
    handoff.makeConnection = { _ in mock }
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
    var heistStepDurationMs: Int = 0

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
            let response = heistExecutionResponse(for: message, handler: handler) ?? handler(message)
            Task { @ButtonHeistActor [self] in
                self.onEvent?(.message(response, requestId: requestId))
            }
        }
        return .enqueued
    }

    var autoResponse: ((ClientMessage) -> ServerMessage)?

    private func heistExecutionResponse(
        for message: ClientMessage,
        handler: (ClientMessage) -> ServerMessage
    ) -> ServerMessage? {
        guard case .heistPlan(let run) = message else { return nil }
        let plan = run.plan

        var stepResults: [HeistExecutionStepResult] = []
        var failedIndex: Int?
        for (index, step) in plan.body.enumerated() {
            if let failedIndex {
                let skipped = HeistExecutionSkippedStepResult(
                    index: index,
                    reason: "skipped: heist stopped after step \(failedIndex)",
                    afterFailedIndex: failedIndex
                )
                stepResults.append(HeistExecutionStepResult(
                    index: index,
                    path: "$.body[\(index)]",
                    kind: .skipped,
                    durationMs: heistStepDurationMs,
                    skipped: skipped
                ))
                continue
            }

            let stepResult = heistStepResult(
                for: step,
                index: index,
                path: "$.body[\(index)]",
                handler: handler
            )
            let shouldStop = stepResult.isFailure
            stepResults.append(stepResult.markingStop(shouldStop))
            if shouldStop {
                failedIndex = index
            }
        }

        let result = HeistExecutionResult(
            steps: stepResults,
            totalTimingMs: 0,
            failedIndex: failedIndex
        )
        return .actionResult(ActionResult(
            success: failedIndex == nil,
            method: .heistPlan,
            errorKind: failedIndex == nil ? nil : .actionFailed,
            payload: .heistExecution(result)
        ))
    }

    private func heistStepResult(
        for step: HeistStep,
        index: Int,
        path: String,
        handler: (ClientMessage) -> ServerMessage
    ) -> HeistExecutionStepResult {
        switch step {
        case .action(let action):
            return heistActionStepResult(for: action, index: index, path: path, handler: handler)
        case .wait(let wait):
            return heistWaitStepResult(for: wait, index: index, path: path, handler: handler)
        case .conditional(let conditional):
            return heistConditionalStepResult(for: conditional, index: index, path: path)
        case .waitForCases(let waitForCases):
            return heistWaitForCasesStepResult(for: waitForCases, index: index, path: path)
        case .forEachElement(let forEach):
            return heistForEachElementStepResult(for: forEach, index: index, path: path)
        case .forEachString(let forEach):
            return heistForEachStringStepResult(for: forEach, index: index, path: path)
        case .heist(let plan):
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .heist,
                message: plan.name.map { "heist \($0)" },
                durationMs: heistStepDurationMs,
                children: plan.body.enumerated().map { childIndex, childStep in
                    heistStepResult(
                        for: childStep,
                        index: childIndex,
                        path: "\(path).heist.body[\(childIndex)]",
                        handler: handler
                    )
                }
            )
        case .invoke(let invoke):
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .invoke,
                message: "invoke \(invoke.path.joined(separator: "."))",
                durationMs: heistStepDurationMs
            )
        case .warn(let warn):
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .warn,
                message: warn.message,
                durationMs: heistStepDurationMs
            )
        case .fail(let fail):
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .fail,
                message: fail.message,
                durationMs: heistStepDurationMs,
                stopsHeist: true
            )
        }
    }

    private func heistActionStepResult(
        for action: ActionStep,
        index: Int,
        path: String,
        handler: (ClientMessage) -> ServerMessage
    ) -> HeistExecutionStepResult {
        guard let command = try? action.command.resolve(in: .empty) else {
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .action,
                actionResult: ActionResult(
                    success: false,
                    method: .heistPlan,
                    message: "mock could not resolve heist action command",
                    errorKind: .validationError
                ),
                durationMs: heistStepDurationMs
            )
        }
        let actionResult = actionResult(for: command, handler: handler)
        let expectation = actionResult.success
            ? heistExpectation(for: action.expectation, handler: handler)
            : nil
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .action,
            actionCommand: action.command,
            actionResult: actionResult,
            expectationActionResult: expectation?.actionResult,
            expectation: expectation?.result,
            durationMs: heistStepDurationMs
        )
    }

    private func heistWaitStepResult(
        for wait: WaitStep,
        index: Int,
        path: String,
        handler: (ClientMessage) -> ServerMessage
    ) -> HeistExecutionStepResult {
        guard let resolved = try? wait.resolve(in: .empty) else {
            return HeistExecutionStepResult(
                index: index,
                path: path,
                kind: .wait,
                actionResult: ActionResult(
                    success: false,
                    method: .wait,
                    message: "mock could not resolve heist wait predicate",
                    errorKind: .validationError
                ),
                durationMs: heistStepDurationMs
            )
        }
        let result = actionResult(
            for: .wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout)),
            handler: handler
        )
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .wait,
            actionResult: result,
            expectation: resolved.predicate.validate(against: result),
            durationMs: heistStepDurationMs
        )
    }

    private func heistConditionalStepResult(
        for conditional: ConditionalStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .conditional,
            message: "mock conditionals do not execute nested steps",
            durationMs: heistStepDurationMs,
            caseSelection: HeistCaseSelectionResult(
                cases: mockCaseResults(for: conditional.cases),
                selectedCaseIndex: nil,
                elapsedMs: heistStepDurationMs
            )
        )
    }

    private func heistWaitForCasesStepResult(
        for waitForCases: WaitForCasesStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .waitForCases,
            message: "mock wait_for_cases timed out",
            durationMs: heistStepDurationMs,
            caseSelection: HeistCaseSelectionResult(
                cases: mockCaseResults(for: waitForCases.cases),
                selectedCaseIndex: nil,
                elapsedMs: heistStepDurationMs,
                timeout: waitForCases.timeout,
                timedOut: true
            )
        )
    }

    private func heistForEachElementStepResult(
        for forEach: ForEachElementStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachElement,
            message: "mock for_each did not match elements",
            durationMs: heistStepDurationMs,
            forEachResult: HeistForEachResult(
                matchedCount: 0,
                limit: forEach.limit,
                iterationCount: 0,
                failureReason: nil
            )
        )
    }

    private func heistForEachStringStepResult(
        for forEach: ForEachStringStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: index,
            path: path,
            kind: .forEachString,
            message: "mock for_each_string completed \(forEach.values.count) iteration(s)",
            durationMs: heistStepDurationMs,
            forEachResult: HeistForEachResult(
                matchedCount: forEach.values.count,
                limit: forEach.values.count,
                iterationCount: forEach.values.count,
                failureReason: nil
            )
        )
    }

    private func mockCaseResults(for cases: [PredicateCase]) -> [HeistCaseMatchResult] {
        cases.map {
            let predicate = (try? $0.predicate.resolve(in: .empty))
                ?? .state(.present(ElementPredicate(label: "unresolved")))
            return HeistCaseMatchResult(
                predicate: predicate,
                result: ExpectationResult(met: false, predicate: predicate)
            )
        }
    }

    private func heistExpectation(
        for expectation: WaitStep?,
        handler: (ClientMessage) -> ServerMessage
    ) -> (actionResult: ActionResult, result: ExpectationResult)? {
        guard let expectation else { return nil }
        guard let resolved = try? expectation.resolve(in: .empty) else {
            let result = ActionResult(
                success: false,
                method: .wait,
                message: "mock could not resolve heist expectation predicate",
                errorKind: .validationError
            )
            return (
                result,
                ExpectationResult(
                    met: false,
                    predicate: .state(.present(ElementPredicate(label: "unresolved"))),
                    actual: result.message
                )
            )
        }
        let waitResult = actionResult(
            for: .wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout)),
            handler: handler
        )
        return (waitResult, resolved.predicate.validate(against: waitResult))
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
        case .typeText: return .typeText
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .scrollToEdge: return .scrollToEdge
        case .wait: return .wait
        case .heistPlan: return .heistPlan
        case .clientHello, .authenticate, .requestInterface,
             .ping, .status, .requestScreen:
            return .heistPlan
        }
    }
}

private extension HeistExecutionStepResult {
    func markingStop(_ stop: Bool) -> HeistExecutionStepResult {
        guard stop != stopsHeist else { return self }
        return HeistExecutionStepResult(
            index: index,
            path: path,
            kind: kind,
            actionResult: actionResult,
            expectationActionResult: expectationActionResult,
            expectation: expectation,
            message: message,
            durationMs: durationMs,
            stopsHeist: stop,
            skipped: skipped,
            caseSelection: caseSelection,
            children: children
        )
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

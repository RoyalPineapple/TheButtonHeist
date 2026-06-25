import Network
import XCTest
import ThePlans
@testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

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
            let response = heistExecutionResponse(for: message) ?? handler(message)
            Task { @ButtonHeistActor [self] in
                self.onEvent?(.message(response, requestId: requestId))
            }
        }
        return .enqueued
    }

    var autoResponse: ((ClientMessage) -> ServerMessage)?
    var runtimeActionResponse: ((RuntimeActionMessage) -> ServerMessage)?

    private func heistExecutionResponse(for message: ClientMessage) -> ServerMessage? {
        guard case .heistPlan(let run) = message else { return nil }
        let plan = run.plan

        var stepResults: [HeistExecutionStepResult] = []
        for (index, step) in plan.body.enumerated() {
            let stepResult = heistStepResult(
                for: step,
                index: index,
                path: "$.body[\(index)]",
                handler: runtimeActionResponse
            )
            stepResults.append(stepResult)
            if stepResult.isFailure { break }
        }
        let abortedAtPath = stepResults.firstFailedStep?.path

        let result = HeistExecutionResult(
            steps: stepResults,
            durationMs: 0,
            abortedAtPath: abortedAtPath
        )
        return .actionResult(ActionResult(
            success: abortedAtPath == nil,
            method: .heistPlan,
            errorKind: abortedAtPath == nil ? nil : .actionFailed,
            payload: .heistExecution(result)
        ))
    }

    private func heistStepResult(
        for step: HeistStep,
        index: Int,
        path: String,
        handler: ((RuntimeActionMessage) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        switch step {
        case .action(let action):
            return heistActionStepResult(for: action, index: index, path: path, handler: handler)
        case .wait(let wait):
            return heistWaitStepResult(for: wait, index: index, path: path, handler: handler)
        case .conditional(let conditional):
            return heistConditionalStepResult(for: conditional, index: index, path: path)
        case .forEachElement(let forEach):
            return heistForEachElementStepResult(for: forEach, index: index, path: path)
        case .forEachString(let forEach):
            return heistForEachStringStepResult(for: forEach, index: index, path: path)
        case .heist(let plan):
            let children = plan.body.enumerated().map { childIndex, childStep in
                heistStepResult(
                    for: childStep,
                    index: childIndex,
                    path: "\(path).heist.body[\(childIndex)]",
                    handler: handler
                )
            }
            let abortedAtChildPath = children.firstFailedStep?.path
            return HeistExecutionStepResult(
                path: path,
                kind: .heist,
                status: abortedAtChildPath == nil ? .passed : .failed,
                durationMs: heistStepDurationMs,
                intent: .heist(name: plan.name),
                evidence: .invocation(HeistInvocationEvidence(
                    name: plan.name.map { "heist \($0)" },
                    childFailedPath: abortedAtChildPath
                )),
                failure: abortedAtChildPath.map { mockChildFailure($0, category: .invocation) },
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        case .invoke(let invoke):
            return HeistExecutionStepResult(
                path: path,
                kind: .invoke,
                status: .passed,
                durationMs: heistStepDurationMs,
                intent: .invoke(path: invoke.path.joined(separator: "."), argument: nil),
                evidence: .invocation(HeistInvocationEvidence(invocation: invoke, name: invoke.path.joined(separator: ".")))
            )
        case .warn(let warn):
            return HeistExecutionStepResult(
                path: path,
                kind: .warn,
                status: .passed,
                durationMs: heistStepDurationMs,
                intent: .warn(message: warn.message),
                evidence: .warning(HeistExecutionWarning(path: path, message: warn.message))
            )
        case .fail(let fail):
            return HeistExecutionStepResult(
                path: path,
                kind: .fail,
                status: .failed,
                durationMs: heistStepDurationMs,
                intent: .fail(message: fail.message),
                failure: HeistFailureDetail(
                    category: .explicitFailure,
                    contract: "explicit heist failure",
                    observed: fail.message
                )
            )
        }
    }

    private func heistActionStepResult(
        for action: ActionStep,
        index: Int,
        path: String,
        handler: ((RuntimeActionMessage) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        guard let command = try? action.command.resolveForRuntimeDispatch(in: .empty) else {
            return HeistExecutionStepResult(
                path: path,
                kind: .action,
                status: .failed,
                durationMs: heistStepDurationMs,
                intent: mockActionIntent(action.command),
                evidence: .action(HeistActionEvidence(command: action.command, actionResult: nil)),
                failure: HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action command resolves before dispatch",
                    observed: "mock could not resolve heist action command"
                )
            )
        }
        let actionResult = actionResult(for: command, handler: handler)
        let expectation = actionResult.success
            ? heistExpectation(for: action.expectation, handler: handler)
            : nil
        let failure = mockActionFailure(command: action.command, actionResult: actionResult, expectation: expectation?.result)
        return HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: failure == nil ? .passed : .failed,
            durationMs: heistStepDurationMs,
            intent: mockActionIntent(action.command),
            evidence: .action(HeistActionEvidence(
                command: action.command,
                actionResult: actionResult,
                expectationActionResult: expectation?.actionResult,
                expectation: expectation?.result
            )),
            failure: failure
        )
    }

    private func heistWaitStepResult(
        for wait: WaitStep,
        index: Int,
        path: String,
        handler: ((RuntimeActionMessage) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        guard let resolved = try? wait.resolve(in: .empty) else {
            return HeistExecutionStepResult(
                path: path,
                kind: .wait,
                status: .failed,
                durationMs: heistStepDurationMs,
                intent: .wait(predicate: wait.predicate.description, timeout: wait.timeout),
                failure: HeistFailureDetail(
                    category: .wait,
                    contract: "wait predicate resolves before evaluation",
                    observed: "mock could not resolve heist wait predicate",
                    expected: wait.predicate.description
                )
            )
        }
        let result = actionResult(
            for: .wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout)),
            handler: handler
        )
        let expectation = resolved.predicate.validate(against: result)
        let failure = (!result.success || !expectation.met)
            ? HeistFailureDetail(
                category: .wait,
                contract: "wait predicate is met before timeout",
                observed: expectation.actual ?? result.message ?? "wait failed",
                expected: wait.predicate.description
            )
            : nil
        return HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: failure == nil ? .passed : .failed,
            durationMs: heistStepDurationMs,
            intent: .wait(predicate: wait.predicate.description, timeout: wait.timeout),
            evidence: .wait(HeistWaitEvidence(actionResult: result, expectation: expectation)),
            failure: failure
        )
    }

    private func heistConditionalStepResult(
        for conditional: ConditionalStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .conditional,
            status: .passed,
            durationMs: heistStepDurationMs,
            intent: .conditional,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: HeistCaseSelectionResult(
                cases: mockCaseResults(for: conditional.cases),
                selectedCaseIndex: nil,
                elapsedMs: heistStepDurationMs
            )))
        )
    }

    private func heistForEachElementStepResult(
        for forEach: ForEachElementStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .forEachElement,
            status: .passed,
            durationMs: heistStepDurationMs,
            intent: .forEachElement(
                parameter: forEach.parameter,
                matching: forEach.matching.description,
                limit: forEach.limit
            ),
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: forEach.parameter,
                matching: forEach.matching,
                limit: forEach.limit,
                matchedCount: 0,
                iterationCount: 0
            ))
        )
    }

    private func heistForEachStringStepResult(
        for forEach: ForEachStringStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .forEachString,
            status: .passed,
            durationMs: heistStepDurationMs,
            intent: .forEachString(parameter: forEach.parameter, count: forEach.values.count),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: forEach.parameter,
                count: forEach.values.count,
                iterationCount: forEach.values.count
            ))
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
        handler: ((RuntimeActionMessage) -> ServerMessage)?
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

    private func mockActionIntent(_ command: HeistActionCommand) -> HeistStepIntent {
        .action(
            command: command.wireType.rawValue,
            target: command.reportTarget.map(String.init(describing:))
        )
    }

    private func mockActionFailure(
        command: HeistActionCommand,
        actionResult: ActionResult,
        expectation: ExpectationResult?
    ) -> HeistFailureDetail? {
        if !actionResult.success {
            return HeistFailureDetail(
                category: actionResult.errorKind == .elementNotFound ? .targetResolution : .action,
                contract: "action dispatch succeeds",
                observed: actionResult.message ?? actionResult.errorKind?.rawValue ?? "action failed",
                expected: command.reportTarget.map(String.init(describing:))
            )
        }
        if let expectation, !expectation.met {
            return HeistFailureDetail(
                category: .expectation,
                contract: "post-action expectation is met",
                observed: expectation.actual ?? "expectation not met",
                expected: expectation.predicate?.description
            )
        }
        return nil
    }

    private func mockChildFailure(_ childPath: String, category: HeistFailureCategory) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    private func actionResult(
        for command: RuntimeActionMessage,
        handler: ((RuntimeActionMessage) -> ServerMessage)?
    ) -> ActionResult {
        switch handler?(command) {
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
            return ActionResult(success: true, method: actionMethod(for: command))
        }
    }

    private func actionMethod(for command: RuntimeActionMessage) -> ActionMethod {
        switch command {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
        case .rotor: return .rotor
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
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

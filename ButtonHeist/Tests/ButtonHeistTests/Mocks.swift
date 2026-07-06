import Network
import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
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
final class MockConnection: DeviceConnecting, TransportReachabilityConnecting {
    var isConnected = false
    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var onTransportReady: (@ButtonHeistActor () -> Void)?
    var sent: [(ClientMessage, String?)] = []
    var sentRequestScreenPayloads: [ScreenRequestPayload?] = []
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
        if case .requestScreen(let payload) = message {
            sentRequestScreenPayloads.append(payload)
        }
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
        if abortedAtPath == nil {
            return .actionResult(ActionResult.success(payload: .heistExecution(result)))
        }
        return .actionResult(ActionResult.failure(
            payload: .heistExecution(result),
            errorKind: .actionFailed
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
        case .repeatUntil(let repeatUntil):
            return heistRepeatUntilStepResult(for: repeatUntil, index: index, path: path)
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
            let evidence = HeistStepEvidence.invocation(.heist(
                name: plan.name.map { "heist \($0)" },
                childFailedPath: abortedAtChildPath
            ))
            if let abortedAtChildPath {
                return .childAborted(
                    path: path,
                    kind: .heist,
                    durationMs: heistStepDurationMs,
                    intent: .heist(name: plan.name),
                    evidence: evidence,
                    failure: mockChildFailure(abortedAtChildPath, category: .invocation),
                    abortedAtChildPath: abortedAtChildPath,
                    children: children
                )
            }
            return .passed(
                path: path,
                kind: .heist,
                durationMs: heistStepDurationMs,
                intent: .heist(name: plan.name),
                evidence: evidence,
                children: children
            )
        case .invoke(let invoke):
            return .passed(
                path: path,
                kind: .invoke,
                durationMs: heistStepDurationMs,
                intent: .invoke(
                    path: HeistInvocationPath.preconditionValidated(components: invoke.path),
                    argument: invoke.argument
                ),
                evidence: .invocation(.invocation(invoke, name: invoke.path.joined(separator: ".")))
            )
        case .warn(let warn):
            return .passed(
                path: path,
                kind: .warn,
                durationMs: heistStepDurationMs,
                intent: .warn(message: warn.message),
                evidence: .warning(HeistExecutionWarning(path: path, message: warn.message))
            )
        case .fail(let fail):
            return .failed(
                path: path,
                kind: .fail,
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
            return .failed(
                path: path,
                kind: .action,
                durationMs: heistStepDurationMs,
                intent: mockActionIntent(action.command),
                evidence: .action(.commandResolutionFailure(command: action.command)),
                failure: HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action command resolves before dispatch",
                    observed: "mock could not resolve heist action command"
                )
            )
        }
        let actionResult = actionResult(for: command, handler: handler)
        let expectation = actionResult.success
            ? heistExpectation(for: action.expectationPolicy.expectedStep, handler: handler)
            : nil
        let failure = mockActionFailure(command: action.command, actionResult: actionResult, expectation: expectation?.result)
        let actionEvidence = expectation.map {
            HeistActionEvidence.expectation(
                command: action.command,
                dispatchResult: actionResult,
                expectationResult: $0.actionResult,
                expectation: $0.result
            )
        } ?? .dispatch(command: action.command, dispatchResult: actionResult)
        if let failure {
            return .failed(
                path: path,
                kind: .action,
                durationMs: heistStepDurationMs,
                intent: mockActionIntent(action.command),
                evidence: .action(actionEvidence),
                failure: failure
            )
        }
        return .passed(
            path: path,
            kind: .action,
            durationMs: heistStepDurationMs,
            intent: mockActionIntent(action.command),
            evidence: .action(actionEvidence)
        )
    }

    private func heistWaitStepResult(
        for wait: WaitStep,
        index: Int,
        path: String,
        handler: ((RuntimeActionMessage) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        guard let resolved = try? wait.resolve(in: .empty) else {
            return .failed(
                path: path,
                kind: .wait,
                durationMs: heistStepDurationMs,
                intent: .wait(predicate: wait.predicate, timeout: wait.timeout),
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
        let waitEvidence: HeistWaitEvidence
        if failure == nil {
            guard let metExpectation = MetExpectationResult(expectation) else {
                preconditionFailure("Passed wait mock fixture requires a met expectation")
            }
            guard let matchedCheck = HeistWaitEvidence.MatchedCheck(
                actionResult: result,
                expectation: metExpectation
            ) else {
                preconditionFailure("Passed wait mock fixture requires a successful action result")
            }
            waitEvidence = .matched(matchedCheck)
        } else {
            guard let unmatchedCheck = HeistWaitEvidence.UnmatchedCheck(
                actionResult: result,
                expectation: expectation
            ) else {
                preconditionFailure("Failed wait mock fixture requires unmatched wait evidence")
            }
            waitEvidence = .failed(unmatchedCheck)
        }
        let evidence = HeistStepEvidence.wait(waitEvidence)
        if let failure {
            return .failed(
                path: path,
                kind: .wait,
                durationMs: heistStepDurationMs,
                intent: .wait(predicate: wait.predicate, timeout: wait.timeout),
                evidence: evidence,
                failure: failure
            )
        }
        return .passed(
            path: path,
            kind: .wait,
            durationMs: heistStepDurationMs,
            intent: .wait(predicate: wait.predicate, timeout: wait.timeout),
            evidence: evidence
        )
    }

    private func heistConditionalStepResult(
        for conditional: ConditionalStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        .passed(
            path: path,
            kind: .conditional,
            durationMs: heistStepDurationMs,
            intent: .conditional,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: HeistCaseSelectionResult(
                cases: mockCaseResults(for: conditional.cases),
                outcome: .noMatch,
                elapsedMs: heistStepDurationMs
            )))
        )
    }

    private func heistForEachElementStepResult(
        for forEach: ForEachElementStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        .passed(
            path: path,
            kind: .forEachElement,
            durationMs: heistStepDurationMs,
            intent: .forEachElement(
                parameter: forEach.parameter,
                matching: forEach.matching,
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
        .passed(
            path: path,
            kind: .forEachString,
            durationMs: heistStepDurationMs,
            intent: .forEachString(parameter: forEach.parameter, count: forEach.values.count),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: forEach.parameter,
                count: forEach.values.count,
                iterationCount: forEach.values.count
            ))
        )
    }

    private func heistRepeatUntilStepResult(
        for repeatUntil: RepeatUntilStep,
        index _: Int,
        path: String
    ) -> HeistExecutionStepResult {
        let predicate = (try? repeatUntil.predicate.resolve(in: .empty))
            ?? .state(.exists(ElementPredicate(label: "unresolved")))
        return .passed(
            path: path,
            kind: .repeatUntil,
            durationMs: heistStepDurationMs,
            intent: .repeatUntil(predicate: .predicate(predicate), timeout: repeatUntil.timeout),
            evidence: .repeatUntil(HeistRepeatUntilEvidence.predicateMet(
                predicate: predicate,
                timeout: repeatUntil.timeout,
                iterationCount: 0,
                expectation: MetExpectationResult(predicate: predicate)
            ))
        )
    }

    private func mockCaseResults(for cases: [PredicateCase]) -> [HeistCaseMatchResult] {
        cases.map {
            let predicate = (try? $0.predicate.resolve(in: .empty)).map(AccessibilityPredicate.state)
                ?? .state(.exists(ElementPredicate(label: "unresolved")))
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
            let result = ActionResult.failure(
                method: .wait,
                errorKind: .validationError,
                message: "mock could not resolve heist expectation predicate")
            return (
                result,
                ExpectationResult(
                    met: false,
                    predicate: .state(.exists(ElementPredicate(label: "unresolved"))),
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
        .action(command: command)
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
            return ActionResult.failure(
                method: actionMethod(for: command),
                errorKind: .general,
                message: error.message)
        default:
            return ActionResult.success(method: actionMethod(for: command))
        }
    }

    private func actionMethod(for command: RuntimeActionMessage) -> ActionMethod {
        switch command {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .customAction
        case .rotor: return .rotor
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
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

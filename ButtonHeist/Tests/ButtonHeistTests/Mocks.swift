import Network
import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

private func receiptPath(_ value: String) -> HeistExecutionPath {
    do {
        return try HeistExecutionPath(validating: value)
    } catch {
        preconditionFailure("invalid mock receipt path \(value): \(error)")
    }
}

// MARK: - Test Helpers

extension DeviceConnection {
    /// Sets the connection into `.connected` state for testing.
    /// The NWConnection is never started — only the state enum matters.
    func simulateConnected() {
        let dummyConnection = NWConnection(host: "127.0.0.1", port: 1, using: .tcp)
        runtimePhase = .connected(RuntimeSession(connection: dummyConnection))
    }
}

@ButtonHeistActor
func assertDeviceConnectionConnected(
    _ connection: DeviceConnection,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .connected = connection.runtimePhase { return }
    XCTFail("Expected device connection to be connected", file: file, line: line)
}

@ButtonHeistActor
func assertDeviceConnectionDisconnected(
    _ connection: DeviceConnection,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .disconnected = connection.runtimePhase { return }
    XCTFail("Expected device connection to be disconnected", file: file, line: line)
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
    var sent: [(ClientMessage, RequestID?)] = []
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
    func send(_ message: ClientMessage, requestId: RequestID?) -> DeviceSendOutcome {
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
    var runtimeActionResponse: ((ResolvedHeistActionCommand) -> ServerMessage)?
    var resolvedWaitResponse: ((ResolvedWaitStep) -> ServerMessage)?

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
            durationMs: 0
        )
        if abortedAtPath == nil {
            return .actionResult(ActionResult.success(payload: .heistExecution(result)))
        }
        return .actionResult(ActionResult.failure(
            payload: .heistExecution(result),
            errorKind: .actionFailed,
        ))
    }

    private func heistStepResult(
        for step: HeistStep,
        index: Int,
        path: String,
        handler: ((ResolvedHeistActionCommand) -> ServerMessage)?
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
            switch HeistExecutedChildren(children) {
            case .passed(let children):
                return .heist(
                    path: receiptPath(path),
                    durationMs: heistStepDurationMs,
                    name: plan.name,
                    completion: .passed(children: children)
                )
            case .aborted(let children):
                return .heist(
                    path: receiptPath(path),
                    durationMs: heistStepDurationMs,
                    name: plan.name,
                    completion: .childAborted(
                        failure: mockChildFailure(children.abortedAtPath, category: .invocation),
                        children: children
                    )
                )
            }
        case .invoke(let invoke):
            let rawEvidence = HeistInvocationEvidence.completed(expectation: nil)
            guard let evidence = HeistPassedInvocationEvidence(rawEvidence) else {
                preconditionFailure("completed mock invocation must carry passing evidence")
            }
            return .invocation(
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                invocationPath: invoke.path,
                argument: invoke.argument,
                completion: .passed(evidence: evidence)
            )
        case .warn(let warn):
            return .warning(
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                message: warn.message,
                completion: .passed()
            )
        case .fail(let fail):
            return .failure(
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                message: fail.message,
                completion: .failed(failure: HeistFailureDetail(
                    category: .explicitFailure,
                    contract: "explicit heist failure",
                    observed: fail.message.description
                ))
            )
        }
    }

    private func heistActionStepResult(
        for action: ActionStep,
        index: Int,
        path: String,
        handler: ((ResolvedHeistActionCommand) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        guard let command = try? action.command.resolve(in: .empty) else {
            let rawEvidence = HeistActionEvidence.commandResolutionFailure
            guard let evidence = HeistFailedActionEvidence(rawEvidence) else {
                preconditionFailure("command-resolution failure must carry failed action evidence")
            }
            return admittedReceipt(
                "mock action receipt construction failed",
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                node: .action(
                    command: action.command,
                    completion: .failed(evidence: evidence, failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action command resolves before dispatch",
                        observed: "mock could not resolve heist action command"
                    ))
                )
            )
        }
        let actionResult = actionResult(for: command, handler: handler)
        let expectation = actionResult.outcome.isSuccess
            ? heistExpectation(for: action.expectationPolicy.expectedStep, handler: handler)
            : nil
        let failure = mockActionFailure(command: action.command, actionResult: actionResult, expectation: expectation?.result)
        let actionEvidence = expectation.map {
            HeistActionEvidence.expectation(
                dispatchResult: actionResult,
                expectationResult: $0.actionResult,
                expectation: $0.result
            )
        } ?? .dispatch(dispatchResult: actionResult)
        if let failure {
            guard let evidence = HeistFailedActionEvidence(actionEvidence) else {
                preconditionFailure("failed mock action must carry failed evidence")
            }
            return admittedReceipt(
                "failed mock action receipt construction failed",
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                node: .action(
                    command: action.command,
                    completion: .failed(evidence: evidence, failure: failure)
                )
            )
        }
        guard let evidence = HeistPassedActionEvidence(actionEvidence) else {
            preconditionFailure("passed mock action must carry passing evidence")
        }
        return admittedReceipt(
            "passed mock action receipt construction failed",
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            node: .action(command: action.command, completion: .passed(evidence: evidence))
        )
    }

    private func heistWaitStepResult(
        for wait: WaitStep,
        index: Int,
        path: String,
        handler: ((ResolvedHeistActionCommand) -> ServerMessage)?
    ) -> HeistExecutionStepResult {
        guard let resolved = try? wait.resolve(in: .empty) else {
            return admittedReceipt(
                "mock wait resolution failure receipt construction failed",
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                node: .wait(
                    predicate: wait.predicate,
                    timeout: wait.timeout,
                    completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                        category: .wait,
                        contract: "wait predicate resolves before evaluation",
                        observed: "mock could not resolve heist wait predicate",
                        expected: wait.predicate.description
                    ))
                )
            )
        }
        let result = waitResult(for: resolved)
        let expectation = resolved.predicate.validate(against: result).expectation(for: wait.predicate)
        let failure = (!result.outcome.isSuccess || !expectation.met)
            ? HeistFailureDetail(
                category: .wait,
                contract: "wait predicate is met before timeout",
                observed: expectation.actual ?? result.message ?? "wait failed",
                expected: wait.predicate.description
            )
            : nil
        let waitEvidence: HeistWaitEvidence
        if failure == nil {
            guard let metExpectation = ExpectationResult.Met(expectation) else {
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
        if let failure {
            guard let evidence = HeistFailedWaitEvidence(waitEvidence) else {
                preconditionFailure("failed mock wait must carry failed evidence")
            }
            return admittedReceipt(
                "failed mock wait receipt construction failed",
                path: receiptPath(path),
                durationMs: heistStepDurationMs,
                node: .wait(
                    predicate: wait.predicate,
                    timeout: wait.timeout,
                    completion: .failed(evidence: .observed(evidence), failure: failure)
                )
            )
        }
        guard let evidence = HeistPassedWaitEvidence(waitEvidence) else {
            preconditionFailure("passed mock wait must carry passing evidence")
        }
        return admittedReceipt(
            "passed mock wait receipt construction failed",
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            node: .wait(
                predicate: wait.predicate,
                timeout: wait.timeout,
                completion: .passed(evidence: evidence)
            )
        )
    }

    private func heistConditionalStepResult(
        for conditional: ConditionalStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        .conditional(
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            completion: .passed(evidence: HeistCaseSelectionEvidence(selection: .selectingFirstMatch(
                cases: mockCaseResults(for: conditional.cases),
                ifNone: .noMatch,
                elapsedMs: heistStepDurationMs
            )))
        )
    }

    private func heistForEachElementStepResult(
        for forEach: ForEachElementStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        guard let rawEvidence = HeistForEachElementEvidence(
            matchedCount: 0,
            iterationCount: 0
        ) else {
            preconditionFailure("empty mock element loop progress must be valid")
        }
        guard let evidence = HeistPassedForEachElementEvidence(rawEvidence) else {
            preconditionFailure("empty mock element loop must carry passing evidence")
        }
        return admittedReceipt(
            "empty mock element loop admission failed",
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            node: .forEachElement(
                declaration: HeistForEachElementDeclaration(forEach),
                completion: .passed(evidence: evidence)
            )
        )
    }

    private func heistForEachStringStepResult(
        for forEach: ForEachStringStep,
        index: Int,
        path: String
    ) -> HeistExecutionStepResult {
        guard let rawEvidence = HeistForEachStringEvidence(
            iterationCount: forEach.values.count
        ) else {
            preconditionFailure("completed mock string loop progress must be valid")
        }
        guard let evidence = HeistPassedForEachStringEvidence(rawEvidence) else {
            preconditionFailure("completed mock string loop must carry passing evidence")
        }
        return admittedReceipt(
            "completed mock string loop admission failed",
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            node: .forEachString(
                declaration: HeistForEachStringDeclaration(forEach),
                completion: .passed(evidence: evidence)
            )
        )
    }

    private func heistRepeatUntilStepResult(
        for repeatUntil: RepeatUntilStep,
        index _: Int,
        path: String
    ) -> HeistExecutionStepResult {
        let predicate = repeatUntil.predicate
        guard let rawEvidence = HeistRepeatUntilEvidence.matched(
            iterationCount: 0,
            expectation: ExpectationResult.Met(predicate: predicate)
        ) else {
            preconditionFailure("matched mock repeat progress must be valid")
        }
        guard let evidence = HeistPassedRepeatUntilEvidence(rawEvidence) else {
            preconditionFailure("matched mock repeat must carry passing evidence")
        }
        return admittedReceipt(
            "matched mock repeat admission failed",
            path: receiptPath(path),
            durationMs: heistStepDurationMs,
            node: .repeatUntil(
                declaration: HeistRepeatUntilDeclaration(repeatUntil),
                completion: .passed(evidence: evidence)
            )
        )
    }

    private func admittedReceipt(
        _ failureMessage: String,
        path: HeistExecutionPath,
        durationMs: Int,
        node: HeistExecutionStepNode
    ) -> HeistExecutionStepResult {
        do {
            return try HeistExecutionStepResult.construct(
                path: path,
                durationMs: durationMs,
                node: node
            )
        } catch {
            preconditionFailure("\(failureMessage): \(error)")
        }
    }

    private func mockCaseResults(for cases: [PredicateCase]) -> [HeistCaseMatchResult] {
        cases.map {
            let predicate = $0.predicate.rootPredicate
            return HeistCaseMatchResult(
                predicate: predicate,
                met: false,
                actual: nil
            )
        }
    }

    private func heistExpectation(
        for expectation: WaitStep?,
        handler: ((ResolvedHeistActionCommand) -> ServerMessage)?
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
                    predicate: .exists(.label("unresolved")),
                    actual: result.message
                )
            )
        }
        let waitResult = waitResult(for: resolved)
        return (
            waitResult,
            resolved.predicate.validate(against: waitResult).expectation(for: expectation.predicate)
        )
    }

    private func mockActionFailure(
        command: HeistActionCommand,
        actionResult: ActionResult,
        expectation: ExpectationResult?
    ) -> HeistFailureDetail? {
        if !actionResult.outcome.isSuccess {
            return HeistFailureDetail(
                category: actionResult.outcome.errorKind == .elementNotFound ? .targetResolution : .action,
                contract: "action dispatch succeeds",
                observed: actionResult.message ?? actionResult.outcome.errorKind?.rawValue ?? "action failed",
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

    private func mockChildFailure(
        _ childPath: HeistExecutionPath,
        category: HeistFailureCategory
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }

    private func actionResult(
        for command: ResolvedHeistActionCommand,
        handler: ((ResolvedHeistActionCommand) -> ServerMessage)?
    ) -> ActionResult {
        switch handler?(command) {
        case .actionResult(let result):
            return result
        case .error(let error):
            return ActionResult.failure(
                method: actionMethod(for: command),
                errorKind: .general,
                message: error.message.description)
        default:
            return ActionResult.success(method: actionMethod(for: command))
        }
    }

    private func waitResult(for step: ResolvedWaitStep) -> ActionResult {
        switch resolvedWaitResponse?(step) {
        case .actionResult(let result):
            return result
        case .error(let error):
            return ActionResult.failure(
                method: .wait,
                errorKind: .general,
                message: error.message.description,
            )
        default:
            return ActionResult.success(method: .wait)
        }
    }

    private func actionMethod(for command: ResolvedHeistActionCommand) -> ActionMethod {
        switch command {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .customAction: return .customAction
        case .rotor: return .rotor
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
        case .dismissKeyboard: return .resignFirstResponder
        case .mechanicalTap: return .syntheticTap
        case .mechanicalLongPress: return .syntheticLongPress
        case .mechanicalSwipe: return .syntheticSwipe
        case .mechanicalDrag: return .syntheticDrag
        case .typeText: return .typeText
        case .viewportScroll: return .scroll
        case .viewportScrollToVisible: return .scrollToVisible
        case .viewportScrollToEdge: return .scrollToEdge
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

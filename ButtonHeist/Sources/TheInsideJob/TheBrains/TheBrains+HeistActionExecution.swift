#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    func executeActionStep(
        _ step: ActionStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope? = nil
    ) async -> HeistExecutionStepResult {
        await executeStep(
            command: step.command,
            wait: step.expectation,
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment,
            scope: scope
        )
    }

    /// The one execution path behind both an action step and a wait step.
    ///
    /// A step is an optional command followed by an optional predicate wait. An
    /// action step has a command and an optional expectation; a wait step has no
    /// command and the wait is the whole step.
    func executeStep(
        command: HeistActionCommand?,
        wait: WaitStep?,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope? = nil
    ) async -> HeistExecutionStepResult {
        let kind: HeistExecutionStepKind = command == nil ? .wait : .action

        var actionResult: ActionResult?
        if let command {
            let resolvedCommand: RuntimeActionMessage
            do {
                resolvedCommand = try command.resolveForRuntimeDispatch(in: environment)
            } catch {
                let observed = "could not resolve heist action command: \(error)"
                return HeistExecutionStepResult(
                    path: path,
                    kind: .action,
                    status: .failed,
                    durationMs: elapsedMilliseconds(since: start),
                    intent: actionIntent(command),
                    evidence: .action(HeistActionEvidence(command: command, actionResult: nil)),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action command resolves before dispatch",
                        observed: observed,
                        expected: command.reportTarget.map(String.init(describing:))
                    )
                )
            }
            actionResult = await runtime.execute(resolvedCommand)
        }

        // No predicate to wait on, or the command already failed: return the
        // action outcome as-is. A failed action is not re-checked.
        guard let wait, actionResult?.success != false else {
            let failure = actionDispatchFailure(command: command, result: actionResult)
            return HeistExecutionStepResult(
                path: path,
                kind: kind,
                status: failure == nil ? .passed : .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: command.map(actionIntent) ?? wait.map(waitIntent),
                evidence: command.map {
                    .action(HeistActionEvidence(command: $0, actionResult: actionResult))
                },
                failure: failure
            )
        }

        let resolvedWait: ResolvedWaitStep
        do {
            resolvedWait = try wait.resolve(in: environment)
        } catch {
            return waitResolutionFailure(
                command: command,
                actionResult: actionResult,
                wait: wait,
                path: path,
                start: start,
                error: error
            )
        }

        let receipt = await runtime.wait(resolvedWait, actionResult?.accessibilityTrace, nil)
        if let command {
            let failure = expectationFailure(
                wait: wait,
                receipt: receipt
            )
            return HeistExecutionStepResult(
                path: path,
                kind: .action,
                status: failure == nil ? .passed : .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: actionIntent(command),
                evidence: .action(HeistActionEvidence(
                    command: command,
                    actionResult: actionResult,
                    expectationActionResult: receipt.actionResult,
                    expectation: receipt.expectation
                )),
                failure: failure
            )
        }

        let failure = waitFailure(wait: wait, receipt: receipt)
        if failure != nil, let elseBody = wait.elseBody, let scope {
            return await waitElseResult(
                elseBody: elseBody,
                wait: wait,
                receipt: receipt,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        }
        return waitResult(
            wait: wait,
            receipt: receipt,
            failure: failure,
            path: path,
            start: start
        )
    }

    private func waitResult(
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        failure: HeistFailureDetail?,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: failure == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: waitEvidence(receipt),
            failure: failure
        )
    }

    private func waitElseResult(
        elseBody: [HeistStep],
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let children = await executeHeistSteps(
            elseBody,
            runtime: runtime,
            environment: environment,
            scope: scope,
            path: "\(path).wait.else_body"
        )
        let abortedAtChildPath = children.firstFailedStep?.path
        return HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: waitEvidence(receipt),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .wait, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func waitEvidence(_ receipt: HeistWaitReceipt) -> HeistStepEvidence {
        .wait(HeistWaitEvidence(
            actionResult: receipt.actionResult,
            expectation: receipt.expectation,
            baselineSummary: nil,
            finalSummary: receipt.expectation.actual
        ))
    }

    private func waitResolutionFailure(
        command: HeistActionCommand?,
        actionResult: ActionResult?,
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        guard let command else {
            let observed = "could not resolve heist wait predicate: \(error)"
            return HeistExecutionStepResult(
                path: path,
                kind: .wait,
                status: .failed,
                durationMs: elapsedMilliseconds(since: start),
                intent: waitIntent(wait),
                failure: HeistFailureDetail(
                    category: .wait,
                    contract: "wait predicate resolves before evaluation",
                    observed: observed,
                    expected: wait.predicate.description
                )
            )
        }

        let expectationActionResult = ActionResultBuilder(method: .wait).failure(errorKind: .actionFailed)
        let expectation = ExpectationResult(
            met: false,
            predicate: nil,
            actual: "could not resolve heist expectation: \(error)"
        )
        return HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .action(HeistActionEvidence(
                command: command,
                actionResult: actionResult,
                expectationActionResult: expectationActionResult,
                expectation: expectation
            )),
            failure: HeistFailureDetail(
                category: .expectation,
                contract: "action expectation predicate resolves before evaluation",
                observed: expectation.actual ?? "could not resolve heist expectation",
                expected: wait.predicate.description
            )
        )
    }

    private func actionIntent(_ command: HeistActionCommand) -> HeistStepIntent {
        .action(
            command: command.wireType.rawValue,
            target: command.reportTarget.map(String.init(describing:))
        )
    }

    private func waitIntent(_ wait: WaitStep) -> HeistStepIntent {
        .wait(predicate: wait.predicate.description, timeout: wait.timeout)
    }

    private func actionDispatchFailure(
        command: HeistActionCommand?,
        result: ActionResult?
    ) -> HeistFailureDetail? {
        guard let command else { return nil }
        guard let result else {
            return HeistFailureDetail(
                category: .action,
                contract: "action dispatch returns a result",
                observed: "no action result returned",
                expected: command.wireType.rawValue
            )
        }
        guard !result.success else { return nil }
        return HeistFailureDetail(
            category: result.errorKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: actionObserved(result, command: command),
            expected: command.reportTarget.map(String.init(describing:))
        )
    }

    private func expectationFailure(
        wait: WaitStep,
        receipt: HeistWaitReceipt
    ) -> HeistFailureDetail? {
        guard !receipt.actionResult.success || !receipt.expectation.met else { return nil }
        return HeistFailureDetail(
            category: .expectation,
            contract: "post-action expectation is met",
            observed: expectationObserved(receipt),
            expected: wait.predicate.description
        )
    }

    private func waitFailure(
        wait: WaitStep,
        receipt: HeistWaitReceipt
    ) -> HeistFailureDetail? {
        guard !receipt.actionResult.success || !receipt.expectation.met else { return nil }
        return HeistFailureDetail(
            category: .wait,
            contract: "wait predicate is met before timeout",
            observed: expectationObserved(receipt),
            expected: wait.predicate.description
        )
    }

    private func actionObserved(_ result: ActionResult, command: HeistActionCommand) -> String {
        [
            result.message,
            result.errorKind.map { "errorKind=\($0.rawValue)" },
            result.settled.map { "settled=\($0)" },
            failureInterfaceSuggestion(for: command, result: result),
        ].compactMap { $0 }.joined(separator: "; ")
    }

    private func failureInterfaceSuggestion(
        for command: HeistActionCommand,
        result: ActionResult
    ) -> String? {
        guard result.errorKind == .elementNotFound,
              let target = command.reportTarget,
              let elements = result.accessibilityTrace?.captures.last?.interface.projectedElements else {
            return nil
        }
        switch target {
        case .predicate(let predicate, _):
            return TheStash.Diagnostics.failureInterfaceSuggestion(for: predicate, elements: elements)
        }
    }

    private func expectationObserved(_ receipt: HeistWaitReceipt) -> String {
        [
            receipt.expectation.actual,
            receipt.actionResult.message,
            receipt.actionResult.errorKind.map { "errorKind=\($0.rawValue)" },
            receipt.actionResult.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

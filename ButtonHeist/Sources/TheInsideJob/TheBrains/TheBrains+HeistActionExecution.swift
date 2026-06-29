#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    enum HeistStepExecutionUnit {
        case action(command: HeistActionCommand, expectation: WaitStep?)
        case wait(WaitStep, scope: HeistExecutionScope)
    }

    func executeActionStep(
        _ step: ActionStep,
        index: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        await executeStep(
            .action(command: step.command, expectation: step.expectation),
            index: index,
            path: path,
            start: start,
            runtime: runtime,
            environment: environment
        )
    }

    /// The one execution path behind both an action step and a wait step.
    ///
    /// `HeistStepExecutionUnit` is the runtime transition boundary: an action
    /// always has a command, while a wait always has the scope needed to run an
    /// else body. There is no nil/nil execution state.
    func executeStep(
        _ unit: HeistStepExecutionUnit,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        switch unit {
        case .action(let command, let expectation):
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
            let actionResult = await runtime.execute(resolvedCommand)
            guard actionResult.success, let expectation else {
                return actionResultNode(
                    command: command,
                    actionResult: actionResult,
                    path: path,
                    start: start
                )
            }
            return await actionExpectationResult(
                command: command,
                actionResult: actionResult,
                wait: expectation,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment
            )

        case .wait(let wait, let scope):
            return await waitStepResult(
                wait: wait,
                path: path,
                start: start,
                runtime: runtime,
                environment: environment,
                scope: scope
            )
        }
    }

    private func actionExpectationResult(
        command: HeistActionCommand,
        actionResult: ActionResult,
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        let resolvedWait: ResolvedWaitStep
        do {
            resolvedWait = try wait.resolve(in: environment)
        } catch {
            return expectationResolutionFailure(
                command: command,
                actionResult: actionResult,
                wait: wait,
                path: path,
                start: start,
                error: error
            )
        }
        let receipt = await runtime.wait(.actionEndpoint(
            resolvedWait,
            trace: actionResult.accessibilityTrace
        ))
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

    private func actionResultNode(
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let failure = actionDispatchFailure(command: command, result: actionResult)
        return HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: failure == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .action(HeistActionEvidence(command: command, actionResult: actionResult)),
            failure: failure
        )
    }

    private func waitStepResult(
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let resolvedWait: ResolvedWaitStep
        do {
            resolvedWait = try wait.resolve(in: environment)
        } catch {
            return waitResolutionFailure(
                wait: wait,
                path: path,
                start: start,
                error: error
            )
        }

        let receipt = await runtime.wait(.standalone(resolvedWait))
        let failure = waitFailure(wait: wait, receipt: receipt)
        if failure != nil, let elseBody = wait.elseBody {
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
            outcome: failure == nil ? .matched : .failed,
            path: path,
            start: start
        )
    }

    private func waitResult(
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        failure: HeistFailureDetail?,
        outcome: HeistPredicateEvidenceOutcome,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: failure == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: waitEvidence(receipt, outcome: outcome),
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
            evidence: waitEvidence(receipt, outcome: .handledElse),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .wait, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func waitEvidence(_ receipt: HeistWaitReceipt) -> HeistStepEvidence {
        waitEvidence(
            receipt,
            outcome: receipt.actionResult.success && receipt.expectation.met ? .matched : .failed
        )
    }

    private func waitEvidence(
        _ receipt: HeistWaitReceipt,
        outcome: HeistPredicateEvidenceOutcome
    ) -> HeistStepEvidence {
        .wait(HeistWaitEvidence(
            outcome: outcome,
            actionResult: receipt.actionResult,
            expectation: receipt.expectation,
            baselineSummary: nil,
            finalSummary: receipt.expectation.actual
        ))
    }

    private func waitResolutionFailure(
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
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

    private func expectationResolutionFailure(
        command: HeistActionCommand,
        actionResult: ActionResult,
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
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
        command: HeistActionCommand,
        result: ActionResult
    ) -> HeistFailureDetail? {
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

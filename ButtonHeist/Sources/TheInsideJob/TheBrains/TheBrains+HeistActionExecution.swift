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

    private enum ActionCommandResolution {
        case resolved(RuntimeActionMessage)
        case failed(ActionCommandResolutionFailure)
    }

    private struct ActionCommandResolutionFailure {
        let detail: HeistFailureDetail

        init(command: HeistActionCommand, error: Error) {
            detail = HeistFailureDetail(
                category: .targetResolution,
                contract: "action command resolves before dispatch",
                observed: "could not resolve heist action command: \(error)",
                expected: command.reportTarget.map(String.init(describing:))
            )
        }
    }

    private enum HeistWaitResolution {
        case resolved(ResolvedWaitStep)
        case failed(HeistWaitResolutionFailure)
    }

    private struct HeistWaitResolutionFailure {
        let observed: String
        let detail: HeistFailureDetail

        init(wait: WaitStep, purpose: HeistWaitEvaluationPurpose, error: Error) {
            observed = purpose.resolutionObservedMessage(error)
            detail = HeistFailureDetail(
                category: purpose.failureCategory,
                contract: purpose.resolutionContract,
                observed: observed,
                expected: wait.predicate.description
            )
        }
    }

    private enum HeistWaitEvaluationPurpose {
        case actionExpectation
        case standaloneWait

        var failureCategory: HeistFailureCategory {
            switch self {
            case .actionExpectation:
                return .expectation
            case .standaloneWait:
                return .wait
            }
        }

        var failureContract: String {
            switch self {
            case .actionExpectation:
                return "post-action expectation is met"
            case .standaloneWait:
                return "wait predicate is met before timeout"
            }
        }

        var resolutionContract: String {
            switch self {
            case .actionExpectation:
                return "action expectation predicate resolves before evaluation"
            case .standaloneWait:
                return "wait predicate resolves before evaluation"
            }
        }

        func resolutionObservedMessage(_ error: Error) -> String {
            switch self {
            case .actionExpectation:
                return "could not resolve heist expectation: \(error)"
            case .standaloneWait:
                return "could not resolve heist wait predicate: \(error)"
            }
        }
    }

    private struct FailedHeistWaitEvaluation {
        let receipt: HeistWaitReceipt
        let detail: HeistFailureDetail
    }

    private enum HeistWaitEvaluation {
        case matched(HeistWaitReceipt)
        case failed(FailedHeistWaitEvaluation)

        var receipt: HeistWaitReceipt {
            switch self {
            case .matched(let receipt):
                return receipt
            case .failed(let failedEvaluation):
                return failedEvaluation.receipt
            }
        }

        var failure: HeistFailureDetail? {
            switch self {
            case .matched:
                return nil
            case .failed(let failedEvaluation):
                return failedEvaluation.detail
            }
        }

        var evidenceOutcome: HeistPredicateEvidenceOutcome {
            switch self {
            case .matched:
                return .matched
            case .failed:
                return .failed
            }
        }
    }

    private enum StandaloneWaitExecution {
        case receipt(HeistWaitEvaluation)
        case elseBody(elseBody: [HeistStep], failedEvaluation: FailedHeistWaitEvaluation)
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
            .action(command: step.command, expectation: step.expectationPolicy.expectedStep),
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
            return await actionStepResult(
                command: command,
                expectation: expectation,
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

    private func actionStepResult(
        command: HeistActionCommand,
        expectation: WaitStep?,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        switch actionCommandResolution(command, environment: environment) {
        case .failed(let failure):
            return actionCommandResolutionFailureReceipt(
                command: command,
                failure: failure,
                path: path,
                start: start
            )

        case .resolved(let resolvedCommand):
            let actionResult = await runtime.execute(resolvedCommand)
            guard actionResult.outcome.isSuccess, let expectation else {
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
        switch waitResolution(wait, purpose: .actionExpectation, environment: environment) {
        case .failed(let failure):
            return expectationResolutionFailure(
                command: command,
                actionResult: actionResult,
                path: path,
                start: start,
                failure: failure
            )

        case .resolved(let resolvedWait):
            let receipt = await runtime.wait(.actionEndpoint(
                resolvedWait,
                trace: actionResult.accessibilityTrace
            ))
            let evaluation = waitEvaluation(wait: wait, receipt: receipt, purpose: .actionExpectation)
            let evidence = HeistActionEvidence.expectation(
                command: command,
                dispatchResult: actionResult,
                expectationResult: evaluation.receipt.actionResult,
                expectation: evaluation.receipt.expectation,
                warning: actionWarning(command: command, actionResult: actionResult)
            )
            return heistActionReceipt(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                intent: actionIntent(command),
                evidence: .action(evidence),
                failure: evaluation.failure
            )
        }
    }

    private func actionResultNode(
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let failure = actionDispatchFailure(command: command, result: actionResult)
        let evidence = actionEvidence(command: command, actionResult: actionResult)
        return heistActionReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .action(evidence),
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
        switch waitResolution(wait, purpose: .standaloneWait, environment: environment) {
        case .failed(let failure):
            return waitResolutionFailure(
                wait: wait,
                path: path,
                start: start,
                failure: failure
            )

        case .resolved(let resolvedWait):
            let receipt = await runtime.wait(.standalone(resolvedWait))
            let evaluation = waitEvaluation(wait: wait, receipt: receipt, purpose: .standaloneWait)
            switch standaloneWaitExecution(wait: wait, evaluation: evaluation) {
            case .elseBody(let elseBody, let failedEvaluation):
                return await waitElseResult(
                    elseBody: elseBody,
                    wait: wait,
                    receipt: failedEvaluation.receipt,
                    path: path,
                    start: start,
                    runtime: runtime,
                    environment: environment,
                    scope: scope
                )

            case .receipt(let evaluation):
                return waitResult(
                    wait: wait,
                    evaluation: evaluation,
                    path: path,
                    start: start
                )
            }
        }
    }

    private func waitResult(
        wait: WaitStep,
        evaluation: HeistWaitEvaluation,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let evidence = waitEvidencePayload(evaluation.receipt, outcome: evaluation.evidenceOutcome)
        let failure = evaluation.failure
        return heistWaitReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: .wait(evidence),
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
        let evidence = waitEvidencePayload(receipt, outcome: .handledElse)
        let childExecution = HeistReceiptChildren(children)
        return heistWaitReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: .wait(evidence),
            children: childExecution,
            childFailure: { childPath in
                self.childFailureDetail(category: .wait, childPath: childPath)
            }
        )
    }

    private func waitEvidence(_ receipt: HeistWaitReceipt) -> HeistStepEvidence {
        .wait(waitEvidencePayload(
            receipt,
            outcome: receipt.actionResult.outcome.isSuccess && receipt.expectation.met ? .matched : .failed
        ))
    }

    private func waitEvidencePayload(
        _ receipt: HeistWaitReceipt,
        outcome: HeistPredicateEvidenceOutcome
    ) -> HeistWaitEvidence {
        let finalSummary = receipt.expectation.actual

        func matchedCheck() -> HeistWaitEvidence.MatchedCheck {
            guard let expectation = MetExpectationResult(receipt.expectation) else {
                preconditionFailure("Matched wait evidence requires a met expectation")
            }
            guard let check = HeistWaitEvidence.MatchedCheck(
                actionResult: receipt.actionResult,
                expectation: expectation
            ) else {
                preconditionFailure("Matched wait evidence requires a successful action result")
            }
            return check
        }

        func unmatchedCheck(_ description: String) -> HeistWaitEvidence.UnmatchedCheck {
            guard let check = HeistWaitEvidence.UnmatchedCheck(
                actionResult: receipt.actionResult,
                expectation: receipt.expectation
            ) else {
                preconditionFailure("\(description) wait evidence requires a failed action result or unmet expectation")
            }
            return check
        }

        switch outcome {
        case .matched:
            return .matched(
                matchedCheck(),
                baselineSummary: nil,
                finalSummary: finalSummary,
                warning: receipt.warning
            )
        case .handledElse:
            return .handledElse(
                unmatchedCheck("Handled-else"),
                baselineSummary: nil,
                finalSummary: finalSummary,
                warning: receipt.warning
            )
        case .failed:
            return .failed(
                unmatchedCheck("Failed"),
                baselineSummary: nil,
                finalSummary: finalSummary,
                warning: receipt.warning
            )
        case .continued:
            preconditionFailure("Continued outcome is only valid for repeat_until evidence")
        }
    }

    private func actionCommandResolution(
        _ command: HeistActionCommand,
        environment: HeistExecutionEnvironment
    ) -> ActionCommandResolution {
        do {
            return .resolved(try command.resolveForRuntimeDispatch(in: environment))
        } catch {
            return .failed(ActionCommandResolutionFailure(command: command, error: error))
        }
    }

    private func actionCommandResolutionFailureReceipt(
        command: HeistActionCommand,
        failure: ActionCommandResolutionFailure,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        heistActionReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .action(.commandResolutionFailure(command: command)),
            failure: failure.detail
        )
    }

    private func waitResolution(
        _ wait: WaitStep,
        purpose: HeistWaitEvaluationPurpose,
        environment: HeistExecutionEnvironment
    ) -> HeistWaitResolution {
        do {
            return .resolved(try wait.resolve(in: environment))
        } catch {
            return .failed(HeistWaitResolutionFailure(wait: wait, purpose: purpose, error: error))
        }
    }

    private func waitResolutionFailure(
        wait: WaitStep,
        path: String,
        start: CFAbsoluteTime,
        failure: HeistWaitResolutionFailure
    ) -> HeistExecutionStepResult {
        return heistFailedReceipt(
            path: path,
            kind: .wait,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            failure: failure.detail
        )
    }

    private func expectationResolutionFailure(
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: String,
        start: CFAbsoluteTime,
        failure: HeistWaitResolutionFailure
    ) -> HeistExecutionStepResult {
        let expectationActionResult = ActionResult.failure(method: .wait, errorKind: .actionFailed)
        let expectation = ExpectationResult(
            met: false,
            predicate: nil,
            actual: failure.observed
        )
        return heistActionReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .action(.expectation(
                command: command,
                dispatchResult: actionResult,
                expectationResult: expectationActionResult,
                expectation: expectation,
                warning: actionWarning(command: command, actionResult: actionResult)
            )),
            failure: failure.detail
        )
    }

    private func actionEvidence(
        command: HeistActionCommand,
        actionResult: ActionResult
    ) -> HeistActionEvidence {
        .dispatch(
            command: command,
            dispatchResult: actionResult,
            warning: actionWarning(command: command, actionResult: actionResult)
        )
    }

    private func actionWarning(
        command: HeistActionCommand,
        actionResult: ActionResult
    ) -> HeistActionWarning? {
        guard actionResult.outcome.isSuccess,
              let subject = actionResult.subjectEvidence
        else { return nil }

        switch command {
        case .activate where !AccessibilityPolicy.advertisesActivationAffordance(subject.element.traits):
            return .activationWeakAffordanceEvidence(
                evidence: actionAffordanceEvidenceDescription(for: subject.element)
            )
        case .typeText where !AccessibilityPolicy.supportsTextEntry(subject.element.traits):
            return .textEntryWeakAffordanceEvidence(
                evidence: actionAffordanceEvidenceDescription(for: subject.element)
            )
        default:
            return nil
        }
    }

    private func actionAffordanceEvidenceDescription(for element: HeistElement) -> String {
        ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            traits: AccessibilityPolicy.orderedMatcherTraits(element.traits),
            actions: element.actions.sorted { $0.description < $1.description }
        ).rendered(using: .activationAffordanceEvidence)
    }

    private func actionIntent(_ command: HeistActionCommand) -> HeistStepIntent {
        .action(command: command)
    }

    private func waitIntent(_ wait: WaitStep) -> HeistStepIntent {
        .wait(predicate: wait.predicate, timeout: wait.timeout)
    }

    private func actionDispatchFailure(
        command: HeistActionCommand,
        result: ActionResult
    ) -> HeistFailureDetail? {
        guard !result.outcome.isSuccess else { return nil }
        return HeistFailureDetail(
            category: result.outcome.errorKind == .elementNotFound ? .targetResolution : .action,
            contract: "action dispatch succeeds",
            observed: actionObserved(result, command: command),
            expected: command.reportTarget.map(String.init(describing:)),
            activationTrace: command.wireType == .activate ? result.activationTrace : nil
        )
    }

    private func waitEvaluation(
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        purpose: HeistWaitEvaluationPurpose
    ) -> HeistWaitEvaluation {
        guard !receipt.actionResult.outcome.isSuccess || !receipt.expectation.met else {
            return .matched(receipt)
        }
        return .failed(FailedHeistWaitEvaluation(
            receipt: receipt,
            detail: HeistFailureDetail(
                category: purpose.failureCategory,
                contract: purpose.failureContract,
                observed: expectationObserved(receipt),
                expected: wait.predicate.description
            )
        ))
    }

    private func standaloneWaitExecution(
        wait: WaitStep,
        evaluation: HeistWaitEvaluation
    ) -> StandaloneWaitExecution {
        guard case .failed(let failedEvaluation) = evaluation,
              let elseBody = wait.elseBody
        else { return .receipt(evaluation) }

        return .elseBody(elseBody: elseBody, failedEvaluation: failedEvaluation)
    }

    private func actionObserved(_ result: ActionResult, command: HeistActionCommand) -> String {
        [
            result.message,
            result.outcome.errorKind.map { "errorKind=\($0.rawValue)" },
            result.settled.map { "settled=\($0)" },
            failureInterfaceSuggestion(for: command, result: result),
        ].compactMap { $0 }.joined(separator: "; ")
    }

    private func failureInterfaceSuggestion(
        for command: HeistActionCommand,
        result: ActionResult
    ) -> String? {
        guard result.outcome.errorKind == .elementNotFound,
              let target = command.reportTarget,
              let elements = result.accessibilityTrace?.captures.last?.interface.projectedElements else {
            return nil
        }
        switch target {
        case .predicate(let predicate, _):
            return TheStash.Diagnostics.failureInterfaceSuggestion(for: predicate, elements: elements)
        case .within(_, let target):
            switch target {
            case .predicate(let predicate, _):
                return TheStash.Diagnostics.failureInterfaceSuggestion(for: predicate, elements: elements)
            case .within:
                return nil
            }
        }
    }

    private func expectationObserved(_ receipt: HeistWaitReceipt) -> String {
        [
            receipt.expectation.actual,
            receipt.actionResult.message,
            receipt.actionResult.outcome.errorKind.map { "errorKind=\($0.rawValue)" },
            receipt.actionResult.settled.map { "settled=\($0)" },
        ].compactMap { $0 }.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

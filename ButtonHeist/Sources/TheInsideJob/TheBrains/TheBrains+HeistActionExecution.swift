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
            return heistActionReceipt(
                path: path,
                durationMs: elapsedMilliseconds(since: start),
                intent: actionIntent(command),
                evidence: .expectation(
                    command: command,
                    actionResult: actionResult,
                    expectationActionResult: evaluation.receipt.actionResult,
                    expectation: evaluation.receipt.expectation,
                    warning: actionWarning(command: command, actionResult: actionResult)
                ),
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
        return heistActionReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: actionEvidence(command: command, actionResult: actionResult),
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
        heistWaitReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: waitEvidencePayload(evaluation.receipt, outcome: evaluation.evidenceOutcome),
            failure: evaluation.failure
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
        return heistWaitReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: waitIntent(wait),
            evidence: waitEvidencePayload(receipt, outcome: .handledElse),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .wait, childPath: $0)
            },
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func waitEvidence(_ receipt: HeistWaitReceipt) -> HeistStepEvidence {
        .wait(waitEvidencePayload(
            receipt,
            outcome: receipt.actionResult.success && receipt.expectation.met ? .matched : .failed
        ))
    }

    private func waitEvidencePayload(
        _ receipt: HeistWaitReceipt,
        outcome: HeistPredicateEvidenceOutcome
    ) -> HeistWaitEvidence {
        HeistWaitEvidence(
            outcome: outcome,
            actionResult: receipt.actionResult,
            expectation: receipt.expectation,
            baselineSummary: nil,
            finalSummary: receipt.expectation.actual,
            warning: receipt.warning
        )
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
            evidence: .commandResolutionFailure(command: command),
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
        return heistWaitReceipt(
            path: path,
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
        let expectationActionResult = ActionResultBuilder().failure(method: .wait, errorKind: .actionFailed)
        let expectation = ExpectationResult(
            met: false,
            predicate: nil,
            actual: failure.observed
        )
        return heistActionReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: actionIntent(command),
            evidence: .expectation(
                command: command,
                actionResult: actionResult,
                expectationActionResult: expectationActionResult,
                expectation: expectation,
                warning: actionWarning(command: command, actionResult: actionResult)
            ),
            failure: failure.detail
        )
    }

    private func actionEvidence(
        command: HeistActionCommand,
        actionResult: ActionResult
    ) -> HeistActionEvidence {
        .dispatch(
            command: command,
            actionResult: actionResult,
            warning: actionWarning(command: command, actionResult: actionResult)
        )
    }

    private func actionWarning(
        command: HeistActionCommand,
        actionResult: ActionResult
    ) -> HeistActionWarning? {
        guard case .activate = command,
              actionResult.success,
              let subject = actionResult.subjectEvidence,
              !AccessibilityPolicy.advertisesActivationAffordance(subject.element.traits)
        else { return nil }

        return .activationWeakAffordanceEvidence(
            evidence: activationAffordanceEvidenceDescription(for: subject.element)
        )
    }

    private func activationAffordanceEvidenceDescription(for element: HeistElement) -> String {
        var parts: [String] = []
        if let label = element.label, !label.isEmpty {
            parts.append("label=\(quotedEvidence(label))")
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            parts.append("identifier=\(quotedEvidence(identifier))")
        }
        let traits = AccessibilityPolicy.orderedMatcherTraits(element.traits).map(\.rawValue)
        parts.append("traits=[\(traits.joined(separator: ", "))]")
        let actions = element.actions.map(\.description).sorted()
        parts.append("actions=[\(actions.joined(separator: ", "))]")
        return parts.joined(separator: " ")
    }

    private func quotedEvidence(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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

    private func waitEvaluation(
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        purpose: HeistWaitEvaluationPurpose
    ) -> HeistWaitEvaluation {
        guard !receipt.actionResult.success || !receipt.expectation.met else {
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

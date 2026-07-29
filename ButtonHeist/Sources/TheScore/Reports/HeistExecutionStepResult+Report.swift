import ThePlans

package extension HeistExecutionStepResult {
    var actionCommand: HeistActionCommand? {
        guard case .action(let command, _) = node else { return nil }
        return command
    }

    var invocation: HeistInvocationStep? {
        guard case .invocation(let path, let argument, _) = node else { return nil }
        return HeistInvocationStep(path: path, argument: argument)
    }

    var forEachStringDeclaration: HeistForEachStringDeclaration? {
        switch node {
        case .forEachString(let declaration, _), .forEachStringIteration(let declaration, _): declaration
        default: nil
        }
    }

    var forEachElementDeclaration: HeistForEachElementDeclaration? {
        switch node {
        case .forEachElement(let declaration, _), .forEachElementIteration(let declaration, _): declaration
        default: nil
        }
    }

    var repeatUntilDeclaration: HeistRepeatUntilDeclaration? {
        switch node {
        case .repeatUntil(let declaration, _), .repeatUntilIteration(let declaration, _): declaration
        default: nil
        }
    }

}

public extension HeistExecutionStepResult {
    /// Human-facing display label for a step. Invoke steps surface the product
    /// capability that ran rather than the bare `invoke` kind.
    var reportDisplayName: String {
        invocation?.runHeistSummary ?? actionCommand?.wireType.rawValue ?? kind.rawValue
    }

    /// Durable matcher target for an action-kind step, if any.
    var reportTarget: AccessibilityTarget? {
        actionCommand?.reportTarget
    }

    /// Message to surface for this step. Failure evidence wins over compact
    /// success summaries because failed results are the detail-oriented case.
    var reportMessage: String? {
        failure?.observed ?? reportSuccessMessage
    }

    /// Action result surfaced to human/report adapters.
    var reportActionResult: ActionResult? {
        switch node {
        case .action:
            actionEvidence?.result
        case .wait:
            reportWaitActionResult
        case .conditional,
             .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .repeatUntil,
             .repeatUntilIteration,
             .warning,
             .failure,
             .heist,
             .invocation:
            nil
        }
    }

    /// Public-facing failure message for a failed step, derived from factual
    /// execution evidence.
    var reportFailureMessage: String? {
        guard let failure else { return nil }
        if children.contains(where: { $0.status == .failed }) {
            switch kind {
            case .conditional, .forEachIteration, .repeatUntilIteration, .heist, .invoke:
                return nil
            case .action, .wait, .forEachElement, .forEachString, .repeatUntil, .warn, .fail:
                break
            }
        }
        return failure.observed
    }
}

private extension HeistExecutionStepResult {
    var reportWaitActionResult: ActionResult? {
        guard let evidence = waitEvidence else { return nil }
        if status == .passed {
            let message: String
            do {
                message = try evidence.replay().actual ?? "matched"
            } catch {
                message = "matched"
            }
            return .success(
                payload: .wait,
                message: message,
                observation: .observed(evidence.observation)
            )
        }
        guard let failure else { return nil }
        return .failure(
            payload: .wait,
            failureKind: failure.actionFailureKind,
            message: failure.observed,
            observation: .observed(evidence.observation)
        )
    }

    var reportSuccessMessage: String? {
        switch node {
        case .conditional:
            guard let evidence = caseSelectionEvidence else { return nil }
            switch evidence.selection.outcome {
            case .matchedCase(let selected): return "matched case \(selected)"
            case .elseBranch(reason: .timedOut): return "timed out; else ran"
            case .elseBranch(reason: .noMatch): return "no case matched; else ran"
            case .timedOut: return "timed out"
            case .noMatch: return "no case matched"
            }
        case .forEachString(let declaration, _), .forEachStringIteration(let declaration, _):
            guard let evidence = forEachStringEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal, let value = evidence.value {
                return "iteration \(ordinal) value \"\(value)\""
            }
            return "completed \(evidence.iterationCount) of \(declaration.count) value(s)"
        case .forEachElement, .forEachElementIteration:
            guard let evidence = forEachElementEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal, let targetOrdinal = evidence.targetOrdinal {
                return "iteration \(ordinal) target ordinal \(targetOrdinal)"
            }
            return "completed \(evidence.iterationCount) of \(evidence.matchedCount) matched element(s)"
        case .repeatUntil, .repeatUntilIteration:
            guard let evidence = repeatUntilEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal {
                return "iteration \(ordinal) \(evidence.outcome.rawValue)"
            }
            return "\(evidence.outcome.rawValue) after \(evidence.iterationCount) iteration(s)"
        case .invocation(let invocationPath, _, _):
            guard let evidence = invocationEvidence else { return nil }
            if let childFailedPath = evidence.childFailedPath { return "child failed at \(childFailedPath)" }
            return invocationPath.description
        case .warning(let message, .passed):
            return message.description
        case .action, .wait, .failure, .heist, .warning:
            return nil
        }
    }
}

private extension HeistFailureDetail {
    var actionFailureKind: ActionFailure.Kind {
        switch category {
        case .timeout:
            .timeout
        case .runtimeUnavailable:
            .accessibilityTreeUnavailable
        case .targetResolution:
            .elementNotFound
        case .validation:
            .validationError
        case .internalInvariant,
             .action,
             .expectation,
             .wait,
             .invocation,
             .loop,
             .explicitFailure:
            .actionFailed
        }
    }
}

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

    var reportCapabilityPath: HeistInvocationPath? {
        guard case .invocation(let path, _, _) = node else { return nil }
        return path
    }

    var reportInvocationDisplayName: String? {
        invocation?.runHeistSummary
    }

    var reportCommand: HeistActionCommandType? {
        actionCommand?.wireType
    }

    var reportWarning: HeistExecutionWarning? {
        warningEvidence
    }

    var reportActionErrorKind: ErrorKind? {
        guard reportActionResult?.outcome.isSuccess == false else { return nil }
        return reportActionResult?.outcome.errorKind
    }
}

public extension HeistExecutionStepResult {
    /// Human-facing display label for a step. Invoke steps surface the product
    /// capability that ran rather than the bare `invoke` kind.
    var reportDisplayName: String {
        reportInvocationDisplayName ?? reportCommandName ?? kind.rawValue
    }

    /// Wire command name for an action-kind step.
    var reportCommandName: String? {
        reportCommand?.rawValue
    }

    /// Durable matcher target for an action-kind step, if any.
    var reportTarget: AccessibilityTarget? {
        actionCommand?.reportTarget
    }

    /// Message to surface for this step. Failure evidence wins over compact
    /// success summaries because failed receipts are the detail-oriented case.
    var reportMessage: String? {
        failure?.observed ?? reportSuccessMessage
    }

    /// Action result surfaced to human/report adapters. For an action with an
    /// expectation, the expectation wait result wins over the dispatch result.
    var reportActionResult: ActionResult? {
        switch node {
        case .action:
            actionEvidence?.reportedResult
        case .wait:
            waitEvidence?.actionResult
        case .repeatUntil, .repeatUntilIteration:
            repeatUntilEvidence?.actionResult
        case .invocation:
            invocationEvidence?.expectationActionResult
        case .conditional,
             .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .warning,
             .failure,
             .heist:
            nil
        }
    }

    /// Expectation to surface for this step. Action dispatch failure suppresses
    /// expectation details so the dispatch failure remains the headline.
    var reportExpectation: ExpectationResult? {
        switch node {
        case .action:
            guard actionEvidence?.dispatchResult?.outcome.isSuccess != false else { return nil }
            return actionEvidence?.checkedExpectation
        case .wait:
            return waitEvidence?.expectation
        case .repeatUntil, .repeatUntilIteration:
            return repeatUntilEvidence?.expectation
        case .invocation:
            return invocationEvidence?.expectation
        case .conditional,
             .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .warning,
             .failure,
             .heist:
            return nil
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
                return "iteration \(ordinal) predicate \(evidence.expectation.met ? "met" : "not met")"
            }
            return evidence.expectation.met
                ? "predicate met after \(evidence.iterationCount) iteration(s)"
                : "timed out after \(evidence.iterationCount) iteration(s)"
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

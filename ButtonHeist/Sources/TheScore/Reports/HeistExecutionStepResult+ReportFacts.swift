import ThePlans

package struct HeistExecutionStepReportResults: Sendable, Equatable {
    package let dispatchedActionResult: ActionResult?
    package let actionResult: ActionResult?
    package let reportedActionResult: ActionResult?
    package let expectation: ExpectationResult?

    package var traceEvidenceResult: ActionResult? { actionResult }

    package var actionErrorKind: ErrorKind? {
        actionResult?.outcome.isSuccess == false ? actionResult?.outcome.errorKind : nil
    }

    fileprivate static func action(_ evidence: HeistActionEvidence?) -> Self {
        Self(
            dispatchedActionResult: evidence?.dispatchResult,
            actionResult: evidence?.reportedResult,
            reportedActionResult: evidence?.reportedResult,
            expectation: evidence?.dispatchResult?.outcome.isSuccess == false ? nil : evidence?.checkedExpectation
        )
    }

    fileprivate static func wait(_ evidence: HeistWaitEvidence?) -> Self {
        Self(
            dispatchedActionResult: nil,
            actionResult: evidence?.actionResult,
            reportedActionResult: nil,
            expectation: evidence?.expectation
        )
    }

    fileprivate static func repeatUntil(_ evidence: HeistRepeatUntilEvidence?) -> Self {
        Self(
            dispatchedActionResult: nil,
            actionResult: evidence?.actionResult,
            reportedActionResult: nil,
            expectation: evidence?.expectation
        )
    }

    fileprivate static func invocation(_ evidence: HeistInvocationEvidence?) -> Self {
        Self(
            dispatchedActionResult: nil,
            actionResult: evidence?.expectationActionResult,
            reportedActionResult: nil,
            expectation: evidence?.expectation
        )
    }

    fileprivate static let none = Self(
        dispatchedActionResult: nil,
        actionResult: nil,
        reportedActionResult: nil,
        expectation: nil
    )
}

package struct HeistExecutionStepReportFacts: Sendable, Equatable {
    package let path: HeistExecutionPath
    package let kind: HeistExecutionStepKind
    package let capabilityPath: HeistInvocationPath?
    package let invocationDisplayName: String?
    package let command: HeistActionCommandType?
    package let target: AccessibilityTarget?
    package let status: HeistExecutionStepStatus
    package let message: String?
    package let failureMessage: String?
    package let failureCategory: HeistFailureCategory?
    package let results: HeistExecutionStepReportResults
    package let warning: HeistExecutionWarning?

    package init(step: HeistExecutionStepResult) {
        path = step.path
        kind = step.kind
        status = step.status
        failureMessage = Self.failureMessage(for: step)
        failureCategory = step.failure?.category
        if let failure = step.failure {
            message = failure.observed
        } else {
            message = Self.successMessage(for: step)
        }

        switch step.node {
        case .action(let actionCommand, _):
            let evidence = step.actionEvidence
            capabilityPath = nil
            invocationDisplayName = nil
            command = actionCommand.wireType
            target = actionCommand.reportTarget
            results = .action(evidence)
            warning = nil
        case .wait:
            capabilityPath = nil
            invocationDisplayName = nil
            command = nil
            target = nil
            results = .wait(step.waitEvidence)
            warning = nil
        case .repeatUntil, .repeatUntilIteration:
            capabilityPath = nil
            invocationDisplayName = nil
            command = nil
            target = nil
            results = .repeatUntil(step.repeatUntilEvidence)
            warning = nil
        case .invocation(let path, let argument, _):
            let evidence = step.invocationEvidence
            let invocation = HeistInvocationStep(path: path, argument: argument)
            capabilityPath = path
            invocationDisplayName = invocation.runHeistSummary
            command = nil
            target = nil
            results = .invocation(evidence)
            warning = nil
        case .warning:
            capabilityPath = nil
            invocationDisplayName = nil
            command = nil
            target = nil
            results = .none
            warning = step.warningEvidence
        case .conditional,
             .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .failure,
             .heist:
            capabilityPath = nil
            invocationDisplayName = nil
            command = nil
            target = nil
            results = .none
            warning = nil
        }
    }

    private static func successMessage(for step: HeistExecutionStepResult) -> String? {
        switch step.node {
        case .conditional:
            guard let evidence = step.caseSelectionEvidence else { return nil }
            switch evidence.selection.outcome {
            case .matchedCase(let selected): return "matched case \(selected)"
            case .elseBranch(reason: .timedOut): return "timed out; else ran"
            case .elseBranch(reason: .noMatch): return "no case matched; else ran"
            case .timedOut: return "timed out"
            case .noMatch: return "no case matched"
            }
        case .forEachString(let declaration, _), .forEachStringIteration(let declaration, _):
            guard let evidence = step.forEachStringEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal, let value = evidence.value {
                return "iteration \(ordinal) value \"\(value)\""
            }
            return "completed \(evidence.iterationCount) of \(declaration.count) value(s)"
        case .forEachElement, .forEachElementIteration:
            guard let evidence = step.forEachElementEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal, let targetOrdinal = evidence.targetOrdinal {
                return "iteration \(ordinal) target ordinal \(targetOrdinal)"
            }
            return "completed \(evidence.iterationCount) of \(evidence.matchedCount) matched element(s)"
        case .repeatUntil, .repeatUntilIteration:
            guard let evidence = step.repeatUntilEvidence else { return nil }
            if let failureReason = evidence.failureReason { return failureReason }
            if let ordinal = evidence.iterationOrdinal {
                return "iteration \(ordinal) predicate \(evidence.expectation.met ? "met" : "not met")"
            }
            return evidence.expectation.met
                ? "predicate met after \(evidence.iterationCount) iteration(s)"
                : "timed out after \(evidence.iterationCount) iteration(s)"
        case .invocation(let invocationPath, _, _):
            guard let evidence = step.invocationEvidence else { return nil }
            if let childFailedPath = evidence.childFailedPath { return "child failed at \(childFailedPath)" }
            return invocationPath.description
        case .warning(let message, .passed):
            return message.description
        case .action, .wait, .failure, .heist, .warning:
            return nil
        }
    }

    private static func failureMessage(for step: HeistExecutionStepResult) -> String? {
        guard let failure = step.failure else { return nil }
        if step.children.contains(where: { $0.status == .failed }) {
            switch step.kind {
            case .conditional, .forEachIteration, .repeatUntilIteration, .heist, .invoke:
                return nil
            case .action, .wait, .forEachElement, .forEachString, .repeatUntil, .warn, .fail:
                break
            }
        }
        return failure.observed
    }
}

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

    var reportFacts: HeistExecutionStepReportFacts {
        HeistExecutionStepReportFacts(step: self)
    }
}

public extension HeistExecutionStepResult {
    /// Human-facing display label for a step. Invoke steps surface the product
    /// capability that ran rather than the bare `invoke` kind.
    var reportDisplayName: String {
        reportFacts.invocationDisplayName ?? reportFacts.command?.rawValue ?? reportFacts.kind.rawValue
    }

    /// Wire command name for an action-kind step.
    var reportCommandName: String? {
        reportFacts.command?.rawValue
    }

    /// Durable matcher target for an action-kind step, if any.
    var reportTarget: AccessibilityTarget? {
        reportFacts.target
    }

    /// Message to surface for this step. Failure evidence wins over compact
    /// success summaries because failed receipts are the detail-oriented case.
    var reportMessage: String? {
        reportFacts.message
    }

    /// Action result surfaced to human/report adapters. For an action with an
    /// expectation, the expectation wait result wins over the dispatch result.
    var reportActionResult: ActionResult? {
        reportFacts.results.actionResult
    }

    /// Expectation to surface for this step. Action dispatch failure suppresses
    /// expectation details so the dispatch failure remains the headline.
    var reportExpectation: ExpectationResult? {
        reportFacts.results.expectation
    }

    /// Public-facing failure message for a failed step, derived from factual
    /// execution evidence.
    var reportFailureMessage: String? {
        reportFacts.failureMessage
    }
}

import Foundation
import ThePlans

// MARK: - Heist Report Facts
//
// Reporting consumes the execution tree directly. These derived facts live on
// the execution result types so encoders, formatters, and report adapters walk
// `HeistExecutionResult.steps` without a second report model.

package struct HeistExecutionEvidenceRollup: Sendable, Equatable {
    package let durationMs: Int
    package let nodes: [HeistExecutionEvidenceNode]

    package var summary: HeistExecutionEvidenceSummary {
        HeistExecutionEvidenceSummary(rollup: self)
    }

    package var actions: HeistExecutionActionEvidenceRollup {
        HeistExecutionActionEvidenceRollup(nodes: nodes)
    }

    package var warnings: HeistExecutionWarningEvidenceRollup {
        HeistExecutionWarningEvidenceRollup(nodes: nodes)
    }

    package init(result: HeistExecutionResult) {
        self.init(steps: result.steps, durationMs: result.durationMs)
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 0
    ) {
        self.durationMs = durationMs
        self.nodes = steps.flatMap(Self.nodes(from:))
    }

    package var outputReceiptNodes: [HeistExecutionStepResult] {
        nodes.map(\.step)
    }

    package var firstFailedStep: HeistExecutionStepResult? {
        nodes.lazy.compactMap(\.firstFailedStepInSubtree).first
    }

    private static func nodes(from step: HeistExecutionStepResult) -> [HeistExecutionEvidenceNode] {
        let childNodes = step.children.flatMap(Self.nodes(from:))
        let firstFailedStep = childNodes.lazy.compactMap(\.firstFailedStepInSubtree).first
            ?? (step.status == .failed ? step : nil)
        return [
            HeistExecutionEvidenceNode(
                step: step,
                firstFailedStepInSubtree: firstFailedStep
            ),
        ] + childNodes
    }
}

package struct HeistExecutionEvidenceNode: Sendable, Equatable {
    package let step: HeistExecutionStepResult
    package let reportFacts: HeistExecutionStepReportFacts
    package let firstFailedStepInSubtree: HeistExecutionStepResult?

    package init(
        step: HeistExecutionStepResult,
        firstFailedStepInSubtree: HeistExecutionStepResult?
    ) {
        self.step = step
        self.reportFacts = HeistExecutionStepReportFacts(step: step)
        self.firstFailedStepInSubtree = firstFailedStepInSubtree
    }

    package var isExecuted: Bool {
        step.status != .skipped
    }

    package var isRootBodyStep: Bool {
        step.isRootBodyStep
    }
}

package struct HeistExecutionEvidenceSummary: Sendable, Equatable {
    package let executedTopLevelStepCount: Int
    package let executedNodeCount: Int
    package let outputReceiptNodeCount: Int
    package let abortedAtPath: String?
    package let durationMs: Int
    package let expectationsChecked: Int
    package let expectationsMet: Int

    package init(rollup: HeistExecutionEvidenceRollup) {
        executedTopLevelStepCount = rollup.nodes.count { $0.isExecuted && $0.isRootBodyStep }
        executedNodeCount = rollup.nodes.count { $0.isExecuted }
        outputReceiptNodeCount = rollup.nodes.count
        abortedAtPath = rollup.firstFailedStep?.path
        durationMs = rollup.durationMs
        expectationsChecked = rollup.nodes.count { node in
            node.isExecuted && node.reportFacts.expectation != nil
        }
        expectationsMet = rollup.nodes.count { node in
            node.isExecuted && node.reportFacts.expectation?.met == true
        }
    }
}

package struct HeistExecutionActionEvidenceRollup: Sendable, Equatable {
    fileprivate let nodes: [HeistExecutionEvidenceNode]

    package var dispatchedResults: [ActionResult] {
        nodes.compactMap { node in
            guard node.step.kind == .action else { return nil }
            return node.step.actionEvidence?.actionResult
        }
    }

    package var reportedResults: [ActionResult] {
        nodes.compactMap { node in
            guard node.step.kind == .action else { return nil }
            return node.reportFacts.actionResult
        }
    }

    package var traceResultsInExecutionOrder: [ActionResult] {
        nodes.compactMap(\.reportFacts.traceEvidenceResult)
    }
}

package struct HeistExecutionWarningEvidenceRollup: Sendable, Equatable {
    fileprivate let nodes: [HeistExecutionEvidenceNode]

    package var all: [HeistExecutionEvidenceWarning] {
        nodes.compactMap { node in
            let path = node.step.path
            switch node.step.evidence {
            case .action(let evidence):
                return evidence.warning.map { .action(path: path, warning: $0) }
            case .wait(let evidence):
                return evidence.warning.map { .wait(path: path, warning: $0) }
            case .warning(let warning):
                return .explicit(warning)
            case .caseSelection, .forEachString, .forEachElement, .repeatUntil, .invocation, .none:
                return nil
            }
        }
    }

    package var explicit: [HeistExecutionWarning] {
        all.compactMap(\.explicitWarning)
    }
}

package enum HeistExecutionEvidenceWarning: Sendable, Equatable {
    case action(path: String, warning: HeistActionWarning)
    case wait(path: String, warning: HeistPredicateWarning)
    case explicit(HeistExecutionWarning)

    package var explicitWarning: HeistExecutionWarning? {
        guard case .explicit(let warning) = self else { return nil }
        return warning
    }
}

package struct HeistExecutionReportSummaryFacts: Sendable, Equatable {
    package let executedTopLevelStepCount: Int
    package let executedNodeCount: Int
    package let outputReceiptNodeCount: Int
    package let abortedAtPath: String?
    package let durationMs: Int
    package let expectationsChecked: Int
    package let expectationsMet: Int

    package init(result: HeistExecutionResult) {
        self.init(summary: HeistExecutionEvidenceRollup(result: result).summary)
    }

    package init(summary: HeistExecutionEvidenceSummary) {
        executedTopLevelStepCount = summary.executedTopLevelStepCount
        executedNodeCount = summary.executedNodeCount
        outputReceiptNodeCount = summary.outputReceiptNodeCount
        abortedAtPath = summary.abortedAtPath
        durationMs = summary.durationMs
        expectationsChecked = summary.expectationsChecked
        expectationsMet = summary.expectationsMet
    }
}

package struct HeistExecutionStepReportFacts: Sendable, Equatable {
    package let path: String
    package let kind: String
    package let capabilityName: String?
    package let displayName: String
    package let commandName: String?
    package let target: ElementTarget?
    package let status: HeistExecutionStepStatus
    package let message: String?
    package let actionResult: ActionResult?
    package let expectation: ExpectationResult?
    package let failureMessage: String?
    package let failureCategory: HeistFailureCategory?
    package let actionErrorKind: ErrorKind?
    package let traceEvidenceResult: ActionResult?

    package init(step: HeistExecutionStepResult) {
        let actionEvidence = step.actionEvidence
        let waitEvidence = step.waitEvidence
        let repeatUntilEvidence = step.repeatUntilEvidence
        let invocationEvidence = step.invocationEvidence
        let expectation = Self.expectation(
            kind: step.kind,
            actionEvidence: actionEvidence,
            waitEvidence: waitEvidence,
            repeatUntilEvidence: repeatUntilEvidence,
            invocationEvidence: invocationEvidence
        )
        let commandName = step.kind == .action ? actionEvidence?.command?.runtimeActionType.rawValue : nil
        let actionResult = Self.actionResult(
            kind: step.kind,
            actionEvidence: actionEvidence,
            waitEvidence: waitEvidence,
            repeatUntilEvidence: repeatUntilEvidence,
            invocationEvidence: invocationEvidence
        )
        let reportedActionResult = step.kind == .action
            ? actionEvidence?.expectationActionResult ?? actionEvidence?.actionResult
            : nil

        path = step.path
        kind = Self.stepName(for: step.kind)
        capabilityName = invocationEvidence?.invocation?.capabilityName
        displayName = invocationEvidence?.invocation?.runHeistSummary ?? commandName ?? kind
        self.commandName = commandName
        target = actionEvidence?.command?.reportTarget
        status = step.status
        message = Self.message(for: step)
        self.actionResult = actionResult
        self.expectation = expectation
        failureMessage = Self.failureMessage(for: step)
        failureCategory = step.failure?.category
        actionErrorKind = reportedActionResult?.success == false ? reportedActionResult?.errorKind : nil
        traceEvidenceResult = Self.traceEvidenceResult(
            kind: step.kind,
            actionEvidence: actionEvidence,
            waitEvidence: waitEvidence,
            repeatUntilEvidence: repeatUntilEvidence,
            invocationEvidence: invocationEvidence
        )
    }

    private static func stepName(for kind: HeistExecutionStepKind) -> String {
        switch kind {
        case .action:
            return "action"
        case .wait:
            return "wait"
        case .conditional:
            return "if"
        case .forEachElement:
            return "for_each_element"
        case .forEachString:
            return "for_each_string"
        case .forEachIteration:
            return "for_each_iteration"
        case .repeatUntil:
            return "repeat_until"
        case .repeatUntilIteration:
            return "repeat_until_iteration"
        case .warn:
            return "warn"
        case .fail:
            return "fail"
        case .heist:
            return "heist"
        case .invoke:
            return "invoke"
        }
    }

    private static func actionResult(
        kind: HeistExecutionStepKind,
        actionEvidence: HeistActionEvidence?,
        waitEvidence: HeistWaitEvidence?,
        repeatUntilEvidence: HeistRepeatUntilEvidence?,
        invocationEvidence: HeistInvocationEvidence?
    ) -> ActionResult? {
        switch kind {
        case .action:
            return actionEvidence?.expectationActionResult ?? actionEvidence?.actionResult
        case .wait:
            return waitEvidence?.actionResult
        case .repeatUntil:
            return repeatUntilEvidence?.actionResult
        case .invoke:
            return invocationEvidence?.expectationActionResult
        default:
            return nil
        }
    }

    private static func traceEvidenceResult(
        kind: HeistExecutionStepKind,
        actionEvidence: HeistActionEvidence?,
        waitEvidence: HeistWaitEvidence?,
        repeatUntilEvidence: HeistRepeatUntilEvidence?,
        invocationEvidence: HeistInvocationEvidence?
    ) -> ActionResult? {
        actionResult(
            kind: kind,
            actionEvidence: actionEvidence,
            waitEvidence: waitEvidence,
            repeatUntilEvidence: repeatUntilEvidence,
            invocationEvidence: invocationEvidence
        )
    }

    private static func expectation(
        kind: HeistExecutionStepKind,
        actionEvidence: HeistActionEvidence?,
        waitEvidence: HeistWaitEvidence?,
        repeatUntilEvidence: HeistRepeatUntilEvidence?,
        invocationEvidence: HeistInvocationEvidence?
    ) -> ExpectationResult? {
        switch kind {
        case .action:
            if actionEvidence?.actionResult?.success == false { return nil }
            return actionEvidence?.expectation
        case .wait:
            return waitEvidence?.expectation
        case .repeatUntil:
            return repeatUntilEvidence?.expectation
        case .invoke:
            return invocationEvidence?.expectation
        default:
            return nil
        }
    }

    private static func message(for step: HeistExecutionStepResult) -> String? {
        if case .failed(let outcome) = step.outcome {
            return outcome.failure.observed
        }
        if let warning = step.warningEvidence {
            return warning.message
        }
        if let caseSelection = step.caseSelectionEvidence?.selection {
            switch caseSelection.outcome {
            case .matchedCase(let selected):
                return "matched case \(selected)"
            case .elseBranch(reason: .timedOut):
                return "timed out; else ran"
            case .elseBranch(reason: .noMatch):
                return "no case matched; else ran"
            case .timedOut:
                return "timed out"
            case .noMatch:
                return "no case matched"
            }
        }
        if let forEach = step.forEachStringEvidence {
            if let failureReason = forEach.failureReason {
                return failureReason
            }
            if let ordinal = forEach.iterationOrdinal, let value = forEach.value {
                return "iteration \(ordinal) value \"\(value)\""
            }
            return "completed \(forEach.iterationCount) of \(forEach.count) value(s)"
        }
        if let forEach = step.forEachElementEvidence {
            if let failureReason = forEach.failureReason {
                return failureReason
            }
            if let ordinal = forEach.iterationOrdinal, let targetOrdinal = forEach.targetOrdinal {
                return "iteration \(ordinal) target ordinal \(targetOrdinal)"
            }
            return "completed \(forEach.iterationCount) of \(forEach.matchedCount) matched element(s)"
        }
        if let repeatUntil = step.repeatUntilEvidence {
            if let failureReason = repeatUntil.failureReason {
                return failureReason
            }
            if let ordinal = repeatUntil.iterationOrdinal {
                return "iteration \(ordinal) predicate \(repeatUntil.expectation.met ? "met" : "not met")"
            }
            if repeatUntil.expectation.met {
                return "predicate met after \(repeatUntil.iterationCount) iteration(s)"
            }
            return "timed out after \(repeatUntil.iterationCount) iteration(s)"
        }
        if let invocation = step.invocationEvidence {
            if let childFailedPath = invocation.childFailedPath {
                return "child failed at \(childFailedPath)"
            }
            return invocation.name
        }
        switch step.intent {
        case .warn(let message), .fail(let message):
            return message
        default:
            return nil
        }
    }

    private static func failureMessage(for step: HeistExecutionStepResult) -> String? {
        guard case .failed(let outcome) = step.outcome else { return nil }
        if step.children.contains(where: { $0.status == .failed }) {
            switch step.kind {
            case .conditional, .forEachIteration, .repeatUntilIteration, .heist, .invoke:
                return nil
            case .action, .wait, .forEachElement, .forEachString, .repeatUntil, .warn, .fail:
                break
            }
        }
        return outcome.failure.observed
    }
}

package extension HeistExecutionStepResult {
    var reportFacts: HeistExecutionStepReportFacts {
        HeistExecutionStepReportFacts(step: self)
    }
}

public extension HeistExecutionStepResult {
    /// Number of executed receipt nodes in this subtree, including this node.
    var executedNodeCount: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.executedNodeCount
    }

    var isFailure: Bool {
        switch outcome {
        case .failed:
            return true
        case .passed, .skipped:
            return children.contains(where: \.isFailure)
        }
    }

    var firstFailedStep: HeistExecutionStepResult? {
        HeistExecutionEvidenceRollup(steps: [self]).firstFailedStep
    }

    var reportStatus: HeistExecutionStepStatus {
        outcome.status
    }

    var actionEvidence: HeistActionEvidence? {
        guard case .action(let evidence) = evidence else { return nil }
        return evidence
    }

    var waitEvidence: HeistWaitEvidence? {
        guard case .wait(let evidence) = evidence else { return nil }
        return evidence
    }

    var caseSelectionEvidence: HeistCaseSelectionEvidence? {
        guard case .caseSelection(let evidence) = evidence else { return nil }
        return evidence
    }

    var forEachStringEvidence: HeistForEachStringEvidence? {
        guard case .forEachString(let evidence) = evidence else { return nil }
        return evidence
    }

    var forEachElementEvidence: HeistForEachElementEvidence? {
        guard case .forEachElement(let evidence) = evidence else { return nil }
        return evidence
    }

    var repeatUntilEvidence: HeistRepeatUntilEvidence? {
        guard case .repeatUntil(let evidence) = evidence else { return nil }
        return evidence
    }

    var invocationEvidence: HeistInvocationEvidence? {
        guard case .invocation(let evidence) = evidence else { return nil }
        return evidence
    }

    var warningEvidence: HeistExecutionWarning? {
        guard case .warning(let warning) = evidence else { return nil }
        return warning
    }

    /// Wire-format step name. Renames `conditional` -> `if`.
    var reportStepName: String {
        reportFacts.kind
    }

    /// Human-facing display label for a step. Invoke steps surface the product
    /// capability that ran rather than the bare `invoke` kind.
    var reportDisplayName: String {
        reportFacts.displayName
    }

    /// Wire command name for an action-kind step.
    var reportCommandName: String? {
        reportFacts.commandName
    }

    /// Durable matcher target for an action-kind step, if any.
    var reportTarget: ElementTarget? {
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
        reportFacts.actionResult
    }

    /// Runtime dispatch evidence for actual action steps.
    var dispatchedActionResult: ActionResult? {
        guard kind == .action else { return nil }
        return actionEvidence?.actionResult
    }

    /// Human/report-facing result for actual action steps.
    var reportedActionResult: ActionResult? {
        guard kind == .action else { return nil }
        return actionEvidence?.expectationActionResult ?? actionEvidence?.actionResult
    }

    /// Expectation to surface for this step. Action dispatch failure suppresses
    /// expectation details so the dispatch failure remains the headline.
    var reportExpectation: ExpectationResult? {
        reportFacts.expectation
    }

    /// Number of expectations evaluated in this subtree.
    var expectationsChecked: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.expectationsChecked
    }

    /// Number of evaluated expectations that were met in this subtree.
    var expectationsMet: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.expectationsMet
    }

    /// Action result that contributes accessibility-trace evidence for this step.
    var traceEvidenceResult: ActionResult? {
        reportFacts.traceEvidenceResult
    }

    /// Trace-contributing results in execution order across this subtree.
    var traceResultsInExecutionOrder: [ActionResult] {
        HeistExecutionEvidenceRollup(steps: [self]).actions.traceResultsInExecutionOrder
    }

    /// Public-facing failure message for a failed step, derived from factual
    /// execution evidence.
    var reportFailureMessage: String? {
        reportFacts.failureMessage
    }
}

public extension Array where Element == HeistExecutionStepResult {
    var firstFailedStep: HeistExecutionStepResult? {
        for step in self {
            if let failed = step.firstFailedStep {
                return failed
            }
        }
        return nil
    }
}

public extension HeistExecutionResult {
    package var evidenceRollup: HeistExecutionEvidenceRollup {
        HeistExecutionEvidenceRollup(result: self)
    }

    /// Top-level heist body steps that actually began execution/evaluation.
    var executedTopLevelStepCount: Int {
        evidenceRollup.summary.executedTopLevelStepCount
    }

    /// All executed receipt nodes in the tree, including nested structural
    /// frames, iterations, and leaf action/wait/warn/fail nodes.
    var executedNodeCount: Int {
        evidenceRollup.summary.executedNodeCount
    }

    /// Whether any step in the execution tree failed.
    var isFailure: Bool {
        switch outcome {
        case .failed:
            return true
        case .passed:
            return false
        }
    }

    /// First failed receipt node. Child failures are canonical before compound
    /// parent frames that merely report an aborted child.
    var firstFailedStep: HeistExecutionStepResult? {
        evidenceRollup.firstFailedStep
    }

    var failedStepPath: String? {
        firstFailedStep?.path
    }

    /// Kind of the first failed receipt node, not a flattened report-row kind.
    var failedStepKind: HeistExecutionStepKind? {
        firstFailedStep?.kind
    }

    /// Total expectations evaluated across the whole execution tree.
    var expectationsChecked: Int {
        evidenceRollup.summary.expectationsChecked
    }

    /// Total met expectations across the whole execution tree.
    var expectationsMet: Int {
        evidenceRollup.summary.expectationsMet
    }

    /// Runtime-evidence-facing action results for action commands actually
    /// dispatched.
    var dispatchedActionResults: [ActionResult] {
        evidenceRollup.actions.dispatchedResults
    }

    /// Human/report-facing action results. Expectation wait evidence may be the
    /// surfaced result when an action has an expectation.
    var reportedActionResults: [ActionResult] {
        evidenceRollup.actions.reportedResults
    }

    /// Trace-contributing results in execution order across the whole tree.
    var traceResultsInExecutionOrder: [ActionResult] {
        evidenceRollup.actions.traceResultsInExecutionOrder
    }

    /// Receipt nodes surfaced by linear output adapters in execution order.
    /// Skipped nodes remain visible because they are first-class receipt facts.
    var outputReceiptNodes: [HeistExecutionStepResult] {
        evidenceRollup.outputReceiptNodes
    }

    /// Warnings emitted by executed `Warn(...)` steps, in execution order.
    var warnings: [HeistExecutionWarning] {
        evidenceRollup.warnings.explicit
    }
}

private extension HeistExecutionStepResult {
    var isRootBodyStep: Bool {
        let prefix = "$.body["
        guard path.hasPrefix(prefix) else { return false }
        let suffix = path.dropFirst(prefix.count)
        guard let closeBracket = suffix.firstIndex(of: "]") else { return false }
        return suffix.index(after: closeBracket) == suffix.endIndex
    }

    var dispatchedActionResults: [ActionResult] {
        HeistExecutionEvidenceRollup(steps: [self]).actions.dispatchedResults
    }

    var reportedActionResults: [ActionResult] {
        HeistExecutionEvidenceRollup(steps: [self]).actions.reportedResults
    }
}

import Foundation
import ThePlans

// MARK: - Heist Report Facts
//
// Reporting consumes a typed evidence event stream derived from the execution
// tree. These facts live on the execution result types so encoders, formatters,
// and report adapters share one report model.

package struct HeistExecutionEvidenceRollup: Sendable, Equatable {
    package let durationMs: Int
    package let rootNodes: [HeistExecutionEvidenceNode]
    package let nodes: [HeistExecutionEvidenceNode]
    package let events: [HeistExecutionEvidenceEvent]
    package let summary: HeistExecutionEvidenceSummary
    package let actions: HeistExecutionActionEvidenceRollup
    package let warnings: HeistExecutionWarningEvidenceRollup
    package let outputNodes: [HeistExecutionEvidenceNode]
    package let outputReceiptNodes: [HeistExecutionStepResult]
    package let firstFailedStep: HeistExecutionStepResult?

    package init(result: HeistExecutionResult) {
        self.init(steps: result.steps, durationMs: result.durationMs)
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 0
    ) {
        self.durationMs = durationMs
        let rootNodes = steps.map(Self.node(from:))
        var accumulator = HeistExecutionEvidenceAccumulator(durationMs: durationMs)
        for node in rootNodes {
            accumulator.visit(node)
        }
        self.rootNodes = rootNodes
        nodes = accumulator.nodes
        events = accumulator.events
        summary = accumulator.summary
        actions = accumulator.actions
        warnings = accumulator.warnings
        outputNodes = accumulator.outputNodes
        outputReceiptNodes = accumulator.outputReceiptNodes
        firstFailedStep = accumulator.firstFailedStep
    }

    private static func node(from step: HeistExecutionStepResult) -> HeistExecutionEvidenceNode {
        let childNodes = step.children.map(Self.node(from:))
        let firstFailedStep = Self.firstFailedStep(in: childNodes)
            ?? (step.status == .failed ? step : nil)
        return HeistExecutionEvidenceNode(
            step: step,
            children: childNodes,
            firstFailedStepInSubtree: firstFailedStep
        )
    }

    private static func firstFailedStep(in nodes: [HeistExecutionEvidenceNode]) -> HeistExecutionStepResult? {
        for node in nodes {
            if let failedStep = node.firstFailedStepInSubtree {
                return failedStep
            }
        }
        return nil
    }
}

package struct HeistExecutionEvidenceNode: Sendable, Equatable {
    package let step: HeistExecutionStepResult
    package let reportFacts: HeistExecutionStepReportFacts
    package let children: [HeistExecutionEvidenceNode]
    package let firstFailedStepInSubtree: HeistExecutionStepResult?

    package init(
        step: HeistExecutionStepResult,
        children: [HeistExecutionEvidenceNode] = [],
        firstFailedStepInSubtree: HeistExecutionStepResult?
    ) {
        self.step = step
        self.reportFacts = HeistExecutionStepReportFacts(step: step)
        self.children = children
        self.firstFailedStepInSubtree = firstFailedStepInSubtree
    }

    package var isExecuted: Bool {
        step.status != .skipped
    }

    package var isRootBodyStep: Bool {
        step.isRootBodyStep
    }
}

package enum HeistExecutionEvidenceEvent: Sendable, Equatable {
    case nodeVisited(HeistExecutionEvidenceNode)
    case dispatchedActionResult(path: String, result: ActionResult)
    case reportedActionResult(path: String, result: ActionResult)
    case traceResult(path: String, result: ActionResult)
    case expectationChecked(path: String, result: ExpectationResult)
    case expectationMet(path: String, result: ExpectationResult)
    case warning(HeistExecutionEvidenceWarning)
    case firstFailure(HeistExecutionStepResult)
    case finalScreen(path: String, screenId: String)
}

private struct HeistExecutionEvidenceAccumulator {
    let durationMs: Int
    var nodes: [HeistExecutionEvidenceNode] = []
    var events: [HeistExecutionEvidenceEvent] = []
    var outputNodes: [HeistExecutionEvidenceNode] = []
    var outputReceiptNodes: [HeistExecutionStepResult] = []
    var firstFailedStep: HeistExecutionStepResult?
    var executedTopLevelStepCount = 0
    var executedNodeCount = 0
    var outputReceiptNodeCount = 0
    var abortedAtPath: String?
    var expectationsChecked = 0
    var expectationsMet = 0
    var finalScreenId: String?
    var dispatchedResults: [ActionResult] = []
    var reportedResults: [ActionResult] = []
    var traceResultsInExecutionOrder: [ActionResult] = []
    var allWarnings: [HeistExecutionEvidenceWarning] = []
    var explicitWarnings: [HeistExecutionWarning] = []
    var didEmitFirstFailure = false

    var summary: HeistExecutionEvidenceSummary {
        HeistExecutionEvidenceSummary(
            executedTopLevelStepCount: executedTopLevelStepCount,
            executedNodeCount: executedNodeCount,
            outputReceiptNodeCount: outputReceiptNodeCount,
            abortedAtPath: abortedAtPath,
            durationMs: durationMs,
            expectationsChecked: expectationsChecked,
            expectationsMet: expectationsMet,
            finalScreenId: finalScreenId
        )
    }

    var actions: HeistExecutionActionEvidenceRollup {
        HeistExecutionActionEvidenceRollup(
            dispatchedResults: dispatchedResults,
            reportedResults: reportedResults,
            traceResultsInExecutionOrder: traceResultsInExecutionOrder,
            finalScreenId: finalScreenId
        )
    }

    var warnings: HeistExecutionWarningEvidenceRollup {
        HeistExecutionWarningEvidenceRollup(all: allWarnings, explicit: explicitWarnings)
    }

    mutating func visit(_ node: HeistExecutionEvidenceNode) {
        nodes.append(node)
        outputNodes.append(node)
        outputReceiptNodes.append(node.step)
        events.append(.nodeVisited(node))
        outputReceiptNodeCount += 1
        if node.isExecuted {
            executedNodeCount += 1
            if node.isRootBodyStep {
                executedTopLevelStepCount += 1
            }
        }

        appendNodeEvidenceEvents(for: node)

        if !didEmitFirstFailure, node.firstFailedStepInSubtree?.path == node.step.path {
            firstFailedStep = node.step
            abortedAtPath = node.step.path
            events.append(.firstFailure(node.step))
            didEmitFirstFailure = true
        }

        for child in node.children {
            visit(child)
        }
    }

    private mutating func appendNodeEvidenceEvents(for node: HeistExecutionEvidenceNode) {
        let path = node.step.path
        if let dispatchResult = node.reportFacts.dispatchedActionResult {
            dispatchedResults.append(dispatchResult)
            events.append(.dispatchedActionResult(path: path, result: dispatchResult))
        }
        if node.step.kind == .action, let reportedResult = node.reportFacts.actionResult {
            reportedResults.append(reportedResult)
            events.append(.reportedActionResult(path: path, result: reportedResult))
        }
        if let traceResult = node.reportFacts.traceEvidenceResult {
            traceResultsInExecutionOrder.append(traceResult)
            events.append(.traceResult(path: path, result: traceResult))
            if let finalScreenId = traceResult.accessibilityTrace?.endpointScreenId {
                self.finalScreenId = finalScreenId
                events.append(.finalScreen(path: path, screenId: finalScreenId))
            }
        }
        if let expectation = node.reportFacts.expectation {
            expectationsChecked += 1
            events.append(.expectationChecked(path: path, result: expectation))
            if expectation.met {
                expectationsMet += 1
                events.append(.expectationMet(path: path, result: expectation))
            }
        }
        if let warning = Self.warningEvent(for: node) {
            allWarnings.append(warning)
            if let explicitWarning = warning.explicitWarning {
                explicitWarnings.append(explicitWarning)
            }
            events.append(.warning(warning))
        }
    }

    private static func warningEvent(for node: HeistExecutionEvidenceNode) -> HeistExecutionEvidenceWarning? {
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

package struct HeistExecutionEvidenceSummary: Sendable, Equatable {
    package let executedTopLevelStepCount: Int
    package let executedNodeCount: Int
    package let outputReceiptNodeCount: Int
    package let abortedAtPath: String?
    package let durationMs: Int
    package let expectationsChecked: Int
    package let expectationsMet: Int
    package let finalScreenId: String?

    package init(
        executedTopLevelStepCount: Int,
        executedNodeCount: Int,
        outputReceiptNodeCount: Int,
        abortedAtPath: String?,
        durationMs: Int,
        expectationsChecked: Int,
        expectationsMet: Int,
        finalScreenId: String?
    ) {
        self.executedTopLevelStepCount = executedTopLevelStepCount
        self.executedNodeCount = executedNodeCount
        self.outputReceiptNodeCount = outputReceiptNodeCount
        self.abortedAtPath = abortedAtPath
        self.durationMs = durationMs
        self.expectationsChecked = expectationsChecked
        self.expectationsMet = expectationsMet
        self.finalScreenId = finalScreenId
    }
}

package struct HeistExecutionActionEvidenceRollup: Sendable, Equatable {
    package let dispatchedResults: [ActionResult]
    package let reportedResults: [ActionResult]
    package let traceResultsInExecutionOrder: [ActionResult]
    package let finalScreenId: String?

    package init(
        dispatchedResults: [ActionResult],
        reportedResults: [ActionResult],
        traceResultsInExecutionOrder: [ActionResult],
        finalScreenId: String?
    ) {
        self.dispatchedResults = dispatchedResults
        self.reportedResults = reportedResults
        self.traceResultsInExecutionOrder = traceResultsInExecutionOrder
        self.finalScreenId = finalScreenId
    }
}

package struct HeistExecutionWarningEvidenceRollup: Sendable, Equatable {
    package let all: [HeistExecutionEvidenceWarning]
    package let explicit: [HeistExecutionWarning]

    package init(all: [HeistExecutionEvidenceWarning], explicit: [HeistExecutionWarning]) {
        self.all = all
        self.explicit = explicit
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
    package let finalScreenId: String?

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
        finalScreenId = summary.finalScreenId
    }
}

package enum HeistExecutionStepReportDetail: Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case caseSelection(HeistCaseSelectionEvidence)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case warning(HeistExecutionWarning)
    case none

    package init(kind: HeistExecutionStepKind, evidence: HeistStepEvidence?) {
        switch (kind, evidence) {
        case (.action, .some(.action(let evidence))):
            self = .action(evidence)
        case (.wait, .some(.wait(let evidence))):
            self = .wait(evidence)
        case (.conditional, .some(.caseSelection(let evidence))):
            self = .caseSelection(evidence)
        case (.forEachString, .some(.forEachString(let evidence))),
             (.forEachIteration, .some(.forEachString(let evidence))):
            self = .forEachString(evidence)
        case (.forEachElement, .some(.forEachElement(let evidence))),
             (.forEachIteration, .some(.forEachElement(let evidence))):
            self = .forEachElement(evidence)
        case (.repeatUntil, .some(.repeatUntil(let evidence))),
             (.repeatUntilIteration, .some(.repeatUntil(let evidence))):
            self = .repeatUntil(evidence)
        case (.invoke, .some(.invocation(let evidence))):
            self = .invocation(evidence)
        case (.warn, .some(.warning(let warning))):
            self = .warning(warning)
        default:
            self = .none
        }
    }

    package var commandName: String? {
        guard case .action(let evidence) = self else { return nil }
        return evidence.command?.runtimeActionType.rawValue
    }

    package var target: ElementTarget? {
        guard case .action(let evidence) = self else { return nil }
        return evidence.command?.reportTarget
    }

    package var capabilityName: String? {
        guard case .invocation(let evidence) = self else { return nil }
        return evidence.invocation?.capabilityName
    }

    package var invocationDisplayName: String? {
        guard case .invocation(let evidence) = self else { return nil }
        return evidence.invocation?.runHeistSummary
    }

    package var dispatchedActionResult: ActionResult? {
        guard case .action(let evidence) = self else { return nil }
        return evidence.dispatchResult
    }

    package var actionResult: ActionResult? {
        switch self {
        case .action(let evidence):
            return evidence.reportedResult
        case .wait(let evidence):
            return evidence.actionResult
        case .repeatUntil(let evidence):
            return evidence.actionResult
        case .invocation(let evidence):
            return evidence.expectationActionResult
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            return nil
        }
    }

    package var traceEvidenceResult: ActionResult? {
        switch self {
        case .action(let evidence):
            return evidence.traceResult
        case .wait(let evidence):
            return evidence.actionResult
        case .repeatUntil(let evidence):
            return evidence.actionResult
        case .invocation(let evidence):
            return evidence.expectationActionResult
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            return nil
        }
    }

    package var expectation: ExpectationResult? {
        switch self {
        case .action(let evidence):
            if evidence.dispatchResult?.success == false { return nil }
            return evidence.expectation
        case .wait(let evidence):
            return evidence.expectation
        case .repeatUntil(let evidence):
            return evidence.expectation
        case .invocation(let evidence):
            return evidence.expectation
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            return nil
        }
    }

    package var actionErrorKind: ErrorKind? {
        guard case .action(let evidence) = self, evidence.reportedResult?.success == false else {
            return nil
        }
        return evidence.reportedResult?.errorKind
    }

    package var message: String? {
        switch self {
        case .caseSelection(let evidence):
            switch evidence.selection.outcome {
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
        case .forEachString(let evidence):
            if let failureReason = evidence.failureReason {
                return failureReason
            }
            if let ordinal = evidence.iterationOrdinal, let value = evidence.value {
                return "iteration \(ordinal) value \"\(value)\""
            }
            return "completed \(evidence.iterationCount) of \(evidence.count) value(s)"
        case .forEachElement(let evidence):
            if let failureReason = evidence.failureReason {
                return failureReason
            }
            if let ordinal = evidence.iterationOrdinal, let targetOrdinal = evidence.targetOrdinal {
                return "iteration \(ordinal) target ordinal \(targetOrdinal)"
            }
            return "completed \(evidence.iterationCount) of \(evidence.matchedCount) matched element(s)"
        case .repeatUntil(let evidence):
            if let failureReason = evidence.failureReason {
                return failureReason
            }
            if let ordinal = evidence.iterationOrdinal {
                return "iteration \(ordinal) predicate \(evidence.expectation.met ? "met" : "not met")"
            }
            if evidence.expectation.met {
                return "predicate met after \(evidence.iterationCount) iteration(s)"
            }
            return "timed out after \(evidence.iterationCount) iteration(s)"
        case .invocation(let evidence):
            if let childFailedPath = evidence.childFailedPath {
                return "child failed at \(childFailedPath)"
            }
            return evidence.name
        case .warning(let warning):
            return warning.message
        case .action, .wait, .none:
            return nil
        }
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
    package let dispatchedActionResult: ActionResult?
    package let traceEvidenceResult: ActionResult?

    package init(step: HeistExecutionStepResult) {
        let detail = HeistExecutionStepReportDetail(kind: step.kind, evidence: step.evidence)
        let commandName = detail.commandName

        path = step.path
        kind = Self.stepName(for: step.kind)
        capabilityName = detail.capabilityName
        displayName = detail.invocationDisplayName ?? commandName ?? kind
        self.commandName = commandName
        target = detail.target
        status = step.status
        message = Self.message(for: step, detail: detail)
        self.actionResult = detail.actionResult
        self.expectation = detail.expectation
        failureMessage = Self.failureMessage(for: step)
        failureCategory = step.failure?.category
        actionErrorKind = detail.actionErrorKind
        dispatchedActionResult = detail.dispatchedActionResult
        traceEvidenceResult = detail.traceEvidenceResult
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

    private static func message(for step: HeistExecutionStepResult, detail: HeistExecutionStepReportDetail) -> String? {
        if let failure = step.failure {
            return failure.observed
        }
        if let message = detail.message {
            return message
        }
        switch step.intent {
        case .warn(let message), .fail(let message):
            return message
        default:
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
        case .failed, .childAborted:
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
        reportFacts.dispatchedActionResult
    }

    /// Human/report-facing result for actual action steps.
    var reportedActionResult: ActionResult? {
        guard kind == .action else { return nil }
        return reportFacts.actionResult
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

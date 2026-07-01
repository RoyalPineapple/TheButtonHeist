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

    package var summary: HeistExecutionEvidenceSummary {
        HeistExecutionEvidenceSummary(rollup: self)
    }

    package var actions: HeistExecutionActionEvidenceRollup {
        HeistExecutionActionEvidenceRollup(events: events)
    }

    package var warnings: HeistExecutionWarningEvidenceRollup {
        HeistExecutionWarningEvidenceRollup(events: events)
    }

    package init(result: HeistExecutionResult) {
        self.init(steps: result.steps, durationMs: result.durationMs)
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 0
    ) {
        self.durationMs = durationMs
        let rootNodes = steps.map(Self.node(from:))
        self.rootNodes = rootNodes
        self.nodes = rootNodes.flatMap(\.preorder)
        self.events = HeistExecutionEvidenceEventBuilder().events(rootNodes: rootNodes)
    }

    package var outputNodes: [HeistExecutionEvidenceNode] {
        var output: [HeistExecutionEvidenceNode] = []
        for event in events {
            guard case .nodeVisited(let node) = event else { continue }
            output.append(node)
        }
        return output
    }

    package var outputReceiptNodes: [HeistExecutionStepResult] {
        var output: [HeistExecutionStepResult] = []
        for event in events {
            guard case .nodeVisited(let node) = event else { continue }
            output.append(node.step)
        }
        return output
    }

    package var firstFailedStep: HeistExecutionStepResult? {
        for event in events {
            guard case .firstFailure(let step) = event else { continue }
            return step
        }
        return nil
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

    package var preorder: [HeistExecutionEvidenceNode] {
        [self] + children.flatMap(\.preorder)
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

package struct HeistExecutionEvidenceEventBuilder: Sendable, Equatable {
    package init() {}

    package func events(rootNodes: [HeistExecutionEvidenceNode]) -> [HeistExecutionEvidenceEvent] {
        var events: [HeistExecutionEvidenceEvent] = []
        var didEmitFirstFailure = false
        for node in rootNodes {
            appendEvents(for: node, to: &events, didEmitFirstFailure: &didEmitFirstFailure)
        }
        return events
    }

    private func appendEvents(
        for node: HeistExecutionEvidenceNode,
        to events: inout [HeistExecutionEvidenceEvent],
        didEmitFirstFailure: inout Bool
    ) {
        events.append(.nodeVisited(node))
        appendNodeEvidenceEvents(for: node, to: &events)

        if !didEmitFirstFailure, node.firstFailedStepInSubtree?.path == node.step.path {
            events.append(.firstFailure(node.step))
            didEmitFirstFailure = true
        }

        for child in node.children {
            appendEvents(for: child, to: &events, didEmitFirstFailure: &didEmitFirstFailure)
        }
    }

    private func appendNodeEvidenceEvents(
        for node: HeistExecutionEvidenceNode,
        to events: inout [HeistExecutionEvidenceEvent]
    ) {
        let path = node.step.path
        if node.step.kind == .action, let dispatchResult = node.step.actionEvidence?.dispatchResult {
            events.append(.dispatchedActionResult(path: path, result: dispatchResult))
        }
        if node.step.kind == .action, let reportedResult = node.reportFacts.actionResult {
            events.append(.reportedActionResult(path: path, result: reportedResult))
        }
        if let traceResult = node.reportFacts.traceEvidenceResult {
            events.append(.traceResult(path: path, result: traceResult))
            if let finalScreenId = traceResult.accessibilityTrace?.endpointScreenId {
                events.append(.finalScreen(path: path, screenId: finalScreenId))
            }
        }
        if let expectation = node.reportFacts.expectation {
            events.append(.expectationChecked(path: path, result: expectation))
            if expectation.met {
                events.append(.expectationMet(path: path, result: expectation))
            }
        }
        if let warning = Self.warningEvent(for: node) {
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

    package init(rollup: HeistExecutionEvidenceRollup) {
        var executedTopLevelStepCount = 0
        var executedNodeCount = 0
        var outputReceiptNodeCount = 0
        var abortedAtPath: String?
        var expectationsChecked = 0
        var expectationsMet = 0
        var finalScreenId: String?

        for event in rollup.events {
            switch event {
            case .nodeVisited(let node):
                outputReceiptNodeCount += 1
                guard node.isExecuted else { continue }
                executedNodeCount += 1
                if node.isRootBodyStep {
                    executedTopLevelStepCount += 1
                }
            case .expectationChecked:
                expectationsChecked += 1
            case .expectationMet:
                expectationsMet += 1
            case .firstFailure(let step):
                if abortedAtPath == nil {
                    abortedAtPath = step.path
                }
            case .finalScreen(_, let screenId):
                finalScreenId = screenId
            case .dispatchedActionResult, .reportedActionResult, .traceResult, .warning:
                break
            }
        }

        self.executedTopLevelStepCount = executedTopLevelStepCount
        self.executedNodeCount = executedNodeCount
        self.outputReceiptNodeCount = outputReceiptNodeCount
        self.abortedAtPath = abortedAtPath
        durationMs = rollup.durationMs
        self.expectationsChecked = expectationsChecked
        self.expectationsMet = expectationsMet
        self.finalScreenId = finalScreenId
    }
}

package struct HeistExecutionActionEvidenceRollup: Sendable, Equatable {
    fileprivate let events: [HeistExecutionEvidenceEvent]

    package var dispatchedResults: [ActionResult] {
        var results: [ActionResult] = []
        for event in events {
            guard case .dispatchedActionResult(_, let result) = event else { continue }
            results.append(result)
        }
        return results
    }

    package var reportedResults: [ActionResult] {
        var results: [ActionResult] = []
        for event in events {
            guard case .reportedActionResult(_, let result) = event else { continue }
            results.append(result)
        }
        return results
    }

    package var traceResultsInExecutionOrder: [ActionResult] {
        var results: [ActionResult] = []
        for event in events {
            guard case .traceResult(_, let result) = event else { continue }
            results.append(result)
        }
        return results
    }

    package var finalScreenId: String? {
        var screenId: String?
        for event in events {
            guard case .finalScreen(_, let finalScreenId) = event else { continue }
            screenId = finalScreenId
        }
        return screenId
    }
}

package struct HeistExecutionWarningEvidenceRollup: Sendable, Equatable {
    fileprivate let events: [HeistExecutionEvidenceEvent]

    package var all: [HeistExecutionEvidenceWarning] {
        var warnings: [HeistExecutionEvidenceWarning] = []
        for event in events {
            guard case .warning(let warning) = event else { continue }
            warnings.append(warning)
        }
        return warnings
    }

    package var explicit: [HeistExecutionWarning] {
        var explicit: [HeistExecutionWarning] = []
        for warning in all {
            guard let explicitWarning = warning.explicitWarning else { continue }
            explicit.append(explicitWarning)
        }
        return explicit
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
        let reportedActionResult = step.kind == .action ? actionEvidence?.reportedResult : nil

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
            return actionEvidence?.reportedResult
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
        switch kind {
        case .action:
            return actionEvidence?.traceResult
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

    private static func expectation(
        kind: HeistExecutionStepKind,
        actionEvidence: HeistActionEvidence?,
        waitEvidence: HeistWaitEvidence?,
        repeatUntilEvidence: HeistRepeatUntilEvidence?,
        invocationEvidence: HeistInvocationEvidence?
    ) -> ExpectationResult? {
        switch kind {
        case .action:
            if actionEvidence?.dispatchResult?.success == false { return nil }
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
        if let failure = step.failure {
            return failure.observed
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
        guard kind == .action else { return nil }
        return actionEvidence?.dispatchResult
    }

    /// Human/report-facing result for actual action steps.
    var reportedActionResult: ActionResult? {
        guard kind == .action else { return nil }
        return actionEvidence?.reportedResult
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

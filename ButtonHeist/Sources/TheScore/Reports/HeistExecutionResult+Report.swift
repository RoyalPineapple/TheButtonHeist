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
    package let metrics: HeistExecutionMetricProjection
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
        var accumulator = HeistExecutionEvidenceAccumulator()
        accumulator.metricBuilder.append(.heistDurationMs, valueMs: durationMs)
        for node in rootNodes {
            accumulator.visit(node)
        }
        self.rootNodes = rootNodes
        nodes = accumulator.nodes
        events = accumulator.events
        summary = HeistExecutionEvidenceSummary(
            executedTopLevelStepCount: rootNodes.count(where: \.isExecuted),
            executedNodeCount: accumulator.executedNodeCount,
            outputReceiptNodeCount: accumulator.nodes.count,
            abortedAtPath: accumulator.firstFailedStep?.path,
            durationMs: durationMs,
            expectationsChecked: accumulator.expectationsChecked,
            expectationsMet: accumulator.expectationsMet,
            finalScreenId: accumulator.finalScreenId
        )
        actions = HeistExecutionActionEvidenceRollup(
            dispatchedResults: accumulator.dispatchedResults,
            reportedResults: accumulator.reportedResults,
            traceResultsInExecutionOrder: accumulator.traceResultsInExecutionOrder,
            finalScreenId: accumulator.finalScreenId
        )
        warnings = HeistExecutionWarningEvidenceRollup(
            all: accumulator.allWarnings,
            explicit: accumulator.explicitWarnings
        )
        metrics = HeistExecutionMetricProjection(
            samples: accumulator.metricBuilder.samples,
            ceilings: accumulator.metricBuilder.ceilings
        )
        outputNodes = accumulator.nodes
        outputReceiptNodes = accumulator.nodes.map(\.step)
        firstFailedStep = accumulator.firstFailedStep
    }

    private static func node(from step: HeistExecutionStepResult) -> HeistExecutionEvidenceNode {
        let childNodes = step.children.map(Self.node(from:))
        let firstFailedStep = childNodes.lazy.compactMap(\.firstFailedStepInSubtree).first
            ?? (step.status == .failed ? step : nil)
        return HeistExecutionEvidenceNode(
            step: step,
            reportFacts: HeistExecutionStepReportFacts(step: step),
            children: childNodes,
            firstFailedStepInSubtree: firstFailedStep
        )
    }
}

package struct HeistExecutionEvidenceNode: Sendable, Equatable {
    package let step: HeistExecutionStepResult
    package let reportFacts: HeistExecutionStepReportFacts
    package let children: [HeistExecutionEvidenceNode]
    package let firstFailedStepInSubtree: HeistExecutionStepResult?

    package var isExecuted: Bool {
        step.status != .skipped
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
    var nodes: [HeistExecutionEvidenceNode] = []
    var events: [HeistExecutionEvidenceEvent] = []
    var firstFailedStep: HeistExecutionStepResult?
    var executedNodeCount = 0
    var expectationsChecked = 0
    var expectationsMet = 0
    var finalScreenId: String?
    var dispatchedResults: [ActionResult] = []
    var reportedResults: [ActionResult] = []
    var traceResultsInExecutionOrder: [ActionResult] = []
    var allWarnings: [HeistExecutionEvidenceWarning] = []
    var explicitWarnings: [HeistExecutionWarning] = []
    var metricBuilder = HeistExecutionMetricProjectionBuilder()

    mutating func visit(_ node: HeistExecutionEvidenceNode) {
        record(.nodeVisited(node))
        let results = node.reportFacts.results
        if let dispatchResult = results.dispatchedActionResult {
            record(.dispatchedActionResult(path: node.step.path, result: dispatchResult))
        }
        if node.step.kind == .action, let reportedResult = results.actionResult {
            record(.reportedActionResult(path: node.step.path, result: reportedResult))
        }
        if let traceResult = results.traceEvidenceResult {
            record(.traceResult(path: node.step.path, result: traceResult))
            if let screenId = traceResult.accessibilityTrace?.endpointScreenId {
                record(.finalScreen(path: node.step.path, screenId: screenId))
            }
        }
        if let expectation = results.expectation {
            record(.expectationChecked(path: node.step.path, result: expectation))
            if expectation.met {
                record(.expectationMet(path: node.step.path, result: expectation))
            }
        }
        switch node.step.evidence {
        case .action(let evidence):
            if let warning = evidence.warning {
                record(.warning(.action(path: node.step.path, warning: warning)))
            }
        case .wait(let evidence):
            if let warning = evidence.warning {
                record(.warning(.wait(path: node.step.path, warning: warning)))
            }
        case .warning(let warning):
            record(.warning(.explicit(warning)))
        case .caseSelection, .forEachString, .forEachElement, .repeatUntil, .invocation, .none:
            break
        }
        if firstFailedStep == nil, node.firstFailedStepInSubtree?.path == node.step.path {
            record(.firstFailure(node.step))
        }

        for child in node.children {
            visit(child)
        }
    }

    private mutating func record(_ event: HeistExecutionEvidenceEvent) {
        events.append(event)
        switch event {
        case .nodeVisited(let node):
            nodes.append(node)
            executedNodeCount += node.isExecuted ? 1 : 0
            metricBuilder.appendMetrics(for: node)
        case .dispatchedActionResult(_, let result):
            dispatchedResults.append(result)
        case .reportedActionResult(_, let result):
            reportedResults.append(result)
        case .traceResult(_, let traceResult):
            traceResultsInExecutionOrder.append(traceResult)
        case .expectationChecked:
            expectationsChecked += 1
        case .expectationMet:
            expectationsMet += 1
        case .warning(let warning):
            allWarnings.append(warning)
            if let explicitWarning = warning.explicitWarning {
                explicitWarnings.append(explicitWarning)
            }
        case .firstFailure(let step):
            firstFailedStep = step
        case .finalScreen(_, let screenId):
            finalScreenId = screenId
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
}

package struct HeistExecutionActionEvidenceRollup: Sendable, Equatable {
    package let dispatchedResults: [ActionResult]
    package let reportedResults: [ActionResult]
    package let traceResultsInExecutionOrder: [ActionResult]
    package let finalScreenId: String?
}

package struct HeistExecutionWarningEvidenceRollup: Sendable, Equatable {
    package let all: [HeistExecutionEvidenceWarning]
    package let explicit: [HeistExecutionWarning]
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

package struct HeistExecutionMetricProjection: Codable, Sendable, Equatable {
    package let samples: [HeistExecutionMetricSample]
    package let ceilings: [HeistExecutionCeilingMetric]

    package init(result: HeistExecutionResult) {
        self.init(rollup: HeistExecutionEvidenceRollup(result: result))
    }

    package init(rollup: HeistExecutionEvidenceRollup) {
        self = rollup.metrics
    }

    fileprivate init(
        samples: [HeistExecutionMetricSample],
        ceilings: [HeistExecutionCeilingMetric]
    ) {
        self.samples = samples
        self.ceilings = ceilings
    }
}

package enum HeistExecutionMetricName: String, Codable, Sendable, Equatable, CaseIterable {
    case heistDurationMs
    case actionPipelineTargetResolutionMs = "actionPipeline.targetResolutionMs"
    case actionPipelineActionDispatchMs = "actionPipeline.actionDispatchMs"
    case actionPipelineSettleMs = "actionPipeline.settleMs"
    case actionPipelineBeforeObservationMs = "actionPipeline.beforeObservationMs"
    case actionPipelineFinalSemanticEvidenceMs = "actionPipeline.finalSemanticEvidenceMs"
    case actionPipelineTotalMs = "actionPipeline.totalMs"
    case waitPipelineTargetResolutionMs = "waitPipeline.targetResolutionMs"
    case waitPipelineActionDispatchMs = "waitPipeline.actionDispatchMs"
    case waitPipelineSettleMs = "waitPipeline.settleMs"
    case waitPipelineBeforeObservationMs = "waitPipeline.beforeObservationMs"
    case waitPipelineFinalSemanticEvidenceMs = "waitPipeline.finalSemanticEvidenceMs"
    case waitPipelineTotalMs = "waitPipeline.totalMs"
    case expectationWaitMs
}

package struct HeistExecutionMetricSample: Codable, Sendable, Equatable {
    package let name: HeistExecutionMetricName
    package let valueMs: Int
    package let path: String?
    package let kind: String?
    package let status: HeistExecutionStepStatus?

    package init(
        name: HeistExecutionMetricName,
        valueMs: Int,
        path: String? = nil,
        kind: String? = nil,
        status: HeistExecutionStepStatus? = nil
    ) {
        self.name = name
        self.valueMs = valueMs
        self.path = path
        self.kind = kind
        self.status = status
    }
}

package enum HeistExecutionCeilingMetricSource: String, Codable, Sendable, Equatable, CaseIterable {
    case intentWaitTimeout = "intent.wait.timeout"
    case repeatUntilTimeout = "repeatUntil.timeout"
    case caseSelectionTimeout = "caseSelection.timeout"
}

package struct HeistExecutionCeilingMetric: Codable, Sendable, Equatable {
    package let source: HeistExecutionCeilingMetricSource
    package let budgetMs: Int
    package let elapsedMs: Int
    package let path: String
    package let kind: String
    package let status: HeistExecutionStepStatus

    package init(
        source: HeistExecutionCeilingMetricSource,
        budgetMs: Int,
        elapsedMs: Int,
        path: String,
        kind: String,
        status: HeistExecutionStepStatus
    ) {
        self.source = source
        self.budgetMs = budgetMs
        self.elapsedMs = elapsedMs
        self.path = path
        self.kind = kind
        self.status = status
    }
}

private struct HeistExecutionMetricProjectionBuilder {
    var samples: [HeistExecutionMetricSample] = []
    var ceilings: [HeistExecutionCeilingMetric] = []

    mutating func appendMetrics(for node: HeistExecutionEvidenceNode) {
        switch node.step.evidence {
        case .action(let evidence):
            appendActionTiming(evidence.dispatchResult?.timing, node: node)
            if let expectationResult = evidence.expectationResult {
                appendWaitTiming(expectationResult.timing, node: node)
                append(.expectationWaitMs, valueMs: expectationResult.timing?.totalMs, node: node)
            }
        case .wait(let evidence):
            appendWaitTiming(evidence.actionResult.timing, node: node)
            guard case .wait(_, let timeout) = node.step.intent else { return }
            appendCeiling(
                .intentWaitTimeout,
                budgetMs: Self.milliseconds(seconds: timeout),
                elapsedMs: evidence.actionResult.timing?.totalMs ?? node.step.durationMs,
                node: node
            )
        case .repeatUntil(let evidence):
            appendWaitTiming(evidence.actionResult?.timing, node: node)
            appendCeiling(
                .repeatUntilTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.timeout),
                elapsedMs: node.step.durationMs,
                node: node
            )
        case .invocation(let evidence):
            let expectationResult = evidence.expectationEvidence?.actionResult ?? evidence.expectationActionResult
            appendWaitTiming(expectationResult?.timing, node: node)
            append(.expectationWaitMs, valueMs: expectationResult?.timing?.totalMs, node: node)
        case .caseSelection(let evidence):
            appendCeiling(
                .caseSelectionTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.selection.timeout),
                elapsedMs: evidence.selection.elapsedMs,
                node: node
            )
        case .forEachString, .forEachElement, .warning, .none:
            break
        }
    }

    mutating func append(
        _ name: HeistExecutionMetricName,
        valueMs: Int?,
        node: HeistExecutionEvidenceNode? = nil
    ) {
        guard let valueMs else { return }
        samples.append(HeistExecutionMetricSample(
            name: name,
            valueMs: max(0, valueMs),
            path: node?.reportFacts.path,
            kind: node?.reportFacts.kind,
            status: node?.reportFacts.status
        ))
    }

    private mutating func appendActionTiming(_ timing: ActionPerformanceTiming?, node: HeistExecutionEvidenceNode) {
        guard let timing else { return }
        append(.actionPipelineTargetResolutionMs, valueMs: timing.targetResolutionMs, node: node)
        append(.actionPipelineActionDispatchMs, valueMs: timing.actionDispatchMs, node: node)
        append(.actionPipelineSettleMs, valueMs: timing.settleMs, node: node)
        append(.actionPipelineBeforeObservationMs, valueMs: timing.beforeObservationMs, node: node)
        append(.actionPipelineFinalSemanticEvidenceMs, valueMs: timing.finalSemanticEvidenceMs, node: node)
        append(.actionPipelineTotalMs, valueMs: timing.totalMs, node: node)
    }

    private mutating func appendWaitTiming(_ timing: ActionPerformanceTiming?, node: HeistExecutionEvidenceNode) {
        guard let timing else { return }
        append(.waitPipelineTargetResolutionMs, valueMs: timing.targetResolutionMs, node: node)
        append(.waitPipelineActionDispatchMs, valueMs: timing.actionDispatchMs, node: node)
        append(.waitPipelineSettleMs, valueMs: timing.settleMs, node: node)
        append(.waitPipelineBeforeObservationMs, valueMs: timing.beforeObservationMs, node: node)
        append(.waitPipelineFinalSemanticEvidenceMs, valueMs: timing.finalSemanticEvidenceMs, node: node)
        append(.waitPipelineTotalMs, valueMs: timing.totalMs, node: node)
    }

    private mutating func appendCeiling(
        _ source: HeistExecutionCeilingMetricSource,
        budgetMs: Int?,
        elapsedMs: Int,
        node: HeistExecutionEvidenceNode
    ) {
        guard let budgetMs else { return }
        ceilings.append(HeistExecutionCeilingMetric(
            source: source,
            budgetMs: budgetMs,
            elapsedMs: max(0, elapsedMs),
            path: node.reportFacts.path,
            kind: node.reportFacts.kind,
            status: node.reportFacts.status
        ))
    }

    private static func milliseconds(seconds: Double?) -> Int? {
        guard let seconds, seconds.isFinite else { return nil }
        return max(0, Int((seconds * 1_000).rounded()))
    }
}

package struct HeistExecutionStepReportResults: Sendable, Equatable {
    package let dispatchedActionResult: ActionResult?
    package let actionResult: ActionResult?
    package let expectation: ExpectationResult?

    package var traceEvidenceResult: ActionResult? {
        actionResult
    }

    package var actionErrorKind: ErrorKind? {
        actionResult?.outcome.isSuccess == false ? actionResult?.outcome.errorKind : nil
    }

    package init(
        dispatchedActionResult: ActionResult? = nil,
        actionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.dispatchedActionResult = dispatchedActionResult
        self.actionResult = actionResult
        self.expectation = expectation
    }

    package static let none = HeistExecutionStepReportResults()
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
        switch evidence {
        case .action(let evidence):
            self = .action(evidence)
        case .wait(let evidence):
            self = .wait(evidence)
        case .caseSelection(let evidence):
            self = .caseSelection(evidence)
        case .forEachString(let evidence):
            self = .forEachString(evidence)
        case .forEachElement(let evidence):
            self = .forEachElement(evidence)
        case .repeatUntil(let evidence):
            self = .repeatUntil(evidence)
        case .invocation(let evidence):
            self = kind == .invoke ? .invocation(evidence) : .none
        case .warning(let warning):
            self = .warning(warning)
        case .none:
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

    package var results: HeistExecutionStepReportResults {
        switch self {
        case .action(let evidence):
            let actionResult = evidence.reportedResult
            return HeistExecutionStepReportResults(
                dispatchedActionResult: evidence.dispatchResult,
                actionResult: actionResult,
                expectation: evidence.dispatchResult?.outcome.isSuccess == false ? nil : evidence.expectation
            )
        case .wait(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.actionResult,
                expectation: evidence.expectation
            )
        case .repeatUntil(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.actionResult,
                expectation: evidence.expectation
            )
        case .invocation(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.expectationActionResult,
                expectation: evidence.expectation
            )
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            return .none
        }
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
    package let failureMessage: String?
    package let failureCategory: HeistFailureCategory?
    package let results: HeistExecutionStepReportResults

    package init(step: HeistExecutionStepResult) {
        let detail = HeistExecutionStepReportDetail(kind: step.kind, evidence: step.evidence)
        let commandName = detail.commandName
        let results = detail.results

        path = step.path
        kind = Self.stepName(for: step.kind)
        capabilityName = detail.capabilityName
        displayName = detail.invocationDisplayName ?? commandName ?? kind
        self.commandName = commandName
        target = detail.target
        status = step.status
        message = Self.message(for: step, detail: detail)
        failureMessage = Self.failureMessage(for: step)
        failureCategory = step.failure?.category
        self.results = results
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
        reportFacts.results.actionResult
    }

    /// Expectation to surface for this step. Action dispatch failure suppresses
    /// expectation details so the dispatch failure remains the headline.
    var reportExpectation: ExpectationResult? {
        reportFacts.results.expectation
    }

    /// Number of expectations evaluated in this subtree.
    var expectationsChecked: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.expectationsChecked
    }

    /// Number of evaluated expectations that were met in this subtree.
    var expectationsMet: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.expectationsMet
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

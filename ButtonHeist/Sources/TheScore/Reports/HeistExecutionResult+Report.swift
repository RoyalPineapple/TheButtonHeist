import Foundation
import ThePlans

// MARK: - Heist Report Facts
//
// These facts live on the execution result types so encoders, formatters, and
// report adapters share one report model.

package struct HeistExecutionEvidenceRollup: Sendable, Equatable {
    package let rootNodes: [HeistExecutionEvidenceNode]
    package let nodes: [HeistExecutionEvidenceNode]
    package let summary: HeistExecutionEvidenceSummary
    package let actions: HeistExecutionActionEvidenceRollup
    package let metrics: HeistExecutionMetricProjection
    package let firstFailedStep: HeistExecutionStepResult?
    package let failureScreenshotStep: HeistExecutionStepResult?

    package var outputReceiptNodes: [HeistExecutionStepResult] {
        nodes.map(\.step)
    }

    package init(result: HeistExecutionResult) {
        self.init(
            steps: result.steps,
            durationMs: result.durationMs,
            failureScreenshotStep: result.trailingFailureScreenshotStep
        )
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 0
    ) {
        self.init(steps: steps, durationMs: durationMs, failureScreenshotStep: nil)
    }

    private init(
        steps: [HeistExecutionStepResult],
        durationMs: Int,
        failureScreenshotStep: HeistExecutionStepResult?
    ) {
        let rootNodes = steps.map(HeistExecutionEvidenceNode.init(step:))
        let reportRootNodes = rootNodes.dropLast(failureScreenshotStep == nil ? 0 : 1)
        var accumulator = HeistExecutionEvidenceAccumulator(durationMs: durationMs)
        steps.walk(enter: { accumulator.enter($0) }, leave: { accumulator.leave($0) })

        self.rootNodes = rootNodes
        nodes = accumulator.nodes
        summary = HeistExecutionEvidenceSummary(
            executedTopLevelStepCount: reportRootNodes.count(where: \.isExecuted),
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
            traceResultsInExecutionOrder: accumulator.traceResultsInExecutionOrder
        )
        metrics = HeistExecutionMetricProjection(
            samples: accumulator.metricBuilder.samples,
            ceilings: accumulator.metricBuilder.ceilings
        )
        firstFailedStep = accumulator.firstFailedStep
        self.failureScreenshotStep = failureScreenshotStep
    }
}

private extension HeistExecutionResult {
    var trailingFailureScreenshotStep: HeistExecutionStepResult? {
        guard case .failed(let outcome) = outcome,
              let candidate = outcome.steps.last,
              candidate.path != outcome.abortedAtPath,
              case .action(let command, _) = candidate.node,
              let evidence = candidate.actionEvidence,
              case .dispatch(let result) = evidence
        else { return nil }
        return command == .takeScreenshot && result.method == .takeScreenshot ? candidate : nil
    }
}

package struct HeistExecutionEvidenceNode: Sendable, Equatable {
    package let step: HeistExecutionStepResult
    package let reportFacts: HeistExecutionStepReportFacts

    package init(step: HeistExecutionStepResult) {
        self.step = step
        reportFacts = step.reportFacts
    }

    package var children: [HeistExecutionEvidenceNode] {
        step.children.map(HeistExecutionEvidenceNode.init(step:))
    }

    package var isExecuted: Bool {
        step.status != .skipped
    }
}

private struct HeistExecutionEvidenceAccumulator {
    var nodes: [HeistExecutionEvidenceNode] = []
    var firstFailedStep: HeistExecutionStepResult?
    var executedNodeCount = 0
    var expectationsChecked = 0
    var expectationsMet = 0
    var finalScreenId: String?
    var dispatchedResults: [ActionResult] = []
    var reportedResults: [ActionResult] = []
    var traceResultsInExecutionOrder: [ActionResult] = []
    var metricBuilder: HeistExecutionMetricProjectionBuilder

    init(durationMs: Int) {
        var metricBuilder = HeistExecutionMetricProjectionBuilder()
        metricBuilder.append(.heistDurationMs, valueMs: durationMs)
        self.metricBuilder = metricBuilder
    }

    mutating func enter(_ step: HeistExecutionStepResult) {
        let node = HeistExecutionEvidenceNode(step: step)
        nodes.append(node)
        executedNodeCount += node.isExecuted ? 1 : 0
        metricBuilder.appendMetrics(for: node)
        let results = node.reportFacts.results
        if let dispatchResult = results.dispatchedActionResult {
            dispatchedResults.append(dispatchResult)
        }
        if let reportedResult = results.reportedActionResult {
            reportedResults.append(reportedResult)
        }
        if let traceResult = results.traceEvidenceResult {
            traceResultsInExecutionOrder.append(traceResult)
            if let screenId = traceResult.accessibilityTrace?.endpointScreenId {
                finalScreenId = screenId
            }
        }
        if let expectation = results.expectation {
            expectationsChecked += 1
            expectationsMet += expectation.met ? 1 : 0
        }
    }

    mutating func leave(_ step: HeistExecutionStepResult) {
        if firstFailedStep == nil, step.status == .failed {
            firstFailedStep = step
        }
    }
}

package struct HeistExecutionEvidenceSummary: Sendable, Equatable {
    package let executedTopLevelStepCount: Int
    package let executedNodeCount: Int
    package let outputReceiptNodeCount: Int
    package let abortedAtPath: HeistExecutionPath?
    package let durationMs: Int
    package let expectationsChecked: Int
    package let expectationsMet: Int
    package let finalScreenId: String?

    package init(
        executedTopLevelStepCount: Int,
        executedNodeCount: Int,
        outputReceiptNodeCount: Int,
        abortedAtPath: HeistExecutionPath?,
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

    package init(
        dispatchedResults: [ActionResult],
        reportedResults: [ActionResult],
        traceResultsInExecutionOrder: [ActionResult]
    ) {
        self.dispatchedResults = dispatchedResults
        self.reportedResults = reportedResults
        self.traceResultsInExecutionOrder = traceResultsInExecutionOrder
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
    package let path: HeistExecutionPath?
    package let kind: HeistExecutionStepKind?
    package let status: HeistExecutionStepStatus?

    package init(
        name: HeistExecutionMetricName,
        valueMs: Int,
        path: HeistExecutionPath? = nil,
        kind: HeistExecutionStepKind? = nil,
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
    package let path: HeistExecutionPath
    package let kind: HeistExecutionStepKind
    package let status: HeistExecutionStepStatus

    package init(
        source: HeistExecutionCeilingMetricSource,
        budgetMs: Int,
        elapsedMs: Int,
        path: HeistExecutionPath,
        kind: HeistExecutionStepKind,
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
        switch node.step.node {
        case .action:
            guard let evidence = node.step.actionEvidence else { return }
            appendActionTiming(evidence.dispatchResult?.timing, node: node)
            if let expectationResult = evidence.expectationResult {
                appendWaitTiming(expectationResult.timing, node: node)
                append(.expectationWaitMs, valueMs: expectationResult.timing?.totalMs, node: node)
            }
        case .wait(_, let timeout, _):
            guard let evidence = node.step.waitEvidence else { return }
            appendWaitTiming(evidence.actionResult.timing, node: node)
            appendCeiling(
                .intentWaitTimeout,
                budgetMs: Self.milliseconds(seconds: timeout.seconds),
                elapsedMs: evidence.actionResult.timing?.totalMs ?? node.step.durationMs,
                node: node
            )
        case .repeatUntil(let declaration, _), .repeatUntilIteration(let declaration, _):
            guard let evidence = node.step.repeatUntilEvidence else { return }
            appendWaitTiming(evidence.actionResult?.timing, node: node)
            appendCeiling(
                .repeatUntilTimeout,
                budgetMs: Self.milliseconds(seconds: declaration.timeout.seconds),
                elapsedMs: node.step.durationMs,
                node: node
            )
        case .heist:
            break
        case .invocation:
            guard let evidence = node.step.invocationEvidence else { return }
            let expectationResult = evidence.waitEvidence?.actionResult ?? evidence.expectationActionResult
            appendWaitTiming(expectationResult?.timing, node: node)
            append(.expectationWaitMs, valueMs: expectationResult?.timing?.totalMs, node: node)
        case .conditional:
            guard let evidence = node.step.caseSelectionEvidence else { return }
            appendCeiling(
                .caseSelectionTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.selection.timeout),
                elapsedMs: evidence.selection.elapsedMs,
                node: node
            )
        case .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .warning,
             .failure:
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

public extension HeistExecutionStepResult {
    /// Number of executed receipt nodes in this subtree, including this node.
    var executedNodeCount: Int {
        HeistExecutionEvidenceRollup(steps: [self]).summary.executedNodeCount
    }

    var isFailure: Bool {
        firstFailedStepInReceiptOrder != nil
    }

    var firstFailedStep: HeistExecutionStepResult? {
        firstFailedStepInReceiptOrder
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
}

public extension Array where Element == HeistExecutionStepResult {
    var firstFailedStep: HeistExecutionStepResult? {
        firstFailedStepInReceiptOrder
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

    var failedStepPath: HeistExecutionPath? {
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
        evidenceRollup.nodes.compactMap(\.reportFacts.warning)
    }
}

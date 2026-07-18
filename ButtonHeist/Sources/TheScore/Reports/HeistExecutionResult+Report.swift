import Foundation
import ThePlans

package enum HeistExecutionReport {
    package struct Projection: Sendable, Equatable {
        package let summary: Summary
        package let metrics: HeistExecutionMetricProjection
    }

    package struct Summary: Sendable, Equatable {
        package let executedTopLevelStepCount: Int
        package let executedNodeCount: Int
        package let outputReceiptNodeCount: Int
        package let abortedAtPath: HeistExecutionPath?
        package let durationMs: Int
        package let expectationsChecked: Int
        package let expectationsMet: Int
        package let finalScreenId: String?
    }

    package static func project(_ result: HeistExecutionResult) -> Projection {
        var reducer = Reducer(durationMs: result.durationMs)
        result.steps.walk(enter: { reducer.reduce($0) }, leave: { _ in })
        let reportRootSteps = result.steps.dropLast(result.failureScreenshotStep == nil ? 0 : 1)
        return reducer.projection(
            executedTopLevelStepCount: reportRootSteps.count { $0.status != .skipped },
            abortedAtPath: result.abortedAtPath
        )
    }

    private struct Reducer {
        let durationMs: Int
        var executedNodeCount = 0
        var outputReceiptNodeCount = 0
        var expectationsChecked = 0
        var expectationsMet = 0
        var finalScreenId: String?
        var metricBuilder: HeistExecutionMetricProjectionBuilder

        init(durationMs: Int) {
            self.durationMs = durationMs
            var metricBuilder = HeistExecutionMetricProjectionBuilder()
            metricBuilder.append(.heistDurationMs, valueMs: durationMs)
            self.metricBuilder = metricBuilder
        }

        mutating func reduce(_ step: HeistExecutionStepResult) {
            outputReceiptNodeCount += 1
            executedNodeCount += step.status == .skipped ? 0 : 1
            metricBuilder.appendMetrics(for: step)
            if let screenId = step.reportActionResult?.accessibilityTrace?.endpointScreenId {
                finalScreenId = screenId
            }
            if let expectation = step.reportExpectation {
                expectationsChecked += 1
                expectationsMet += expectation.met ? 1 : 0
            }
        }

        func projection(
            executedTopLevelStepCount: Int,
            abortedAtPath: HeistExecutionPath?
        ) -> Projection {
            Projection(
                summary: Summary(
                    executedTopLevelStepCount: executedTopLevelStepCount,
                    executedNodeCount: executedNodeCount,
                    outputReceiptNodeCount: outputReceiptNodeCount,
                    abortedAtPath: abortedAtPath,
                    durationMs: durationMs,
                    expectationsChecked: expectationsChecked,
                    expectationsMet: expectationsMet,
                    finalScreenId: finalScreenId
                ),
                metrics: HeistExecutionMetricProjection(
                    samples: metricBuilder.samples,
                    ceilings: metricBuilder.ceilings
                )
            )
        }
    }
}

package struct HeistExecutionMetricProjection: Codable, Sendable, Equatable {
    package let samples: [HeistExecutionMetricSample]
    package let ceilings: [HeistExecutionCeilingMetric]

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

    mutating func appendMetrics(for step: HeistExecutionStepResult) {
        switch step.node {
        case .action:
            guard let evidence = step.actionEvidence else { return }
            appendActionTiming(evidence.dispatchResult, step: step)
            if let expectationResult = evidence.expectationResult {
                appendWaitTiming(expectationResult, step: step)
                append(.expectationWaitMs, valueMs: expectationResult.timing?.totalMs, step: step)
            }
        case .wait(_, let timeout, _):
            guard let evidence = step.waitEvidence else { return }
            appendWaitTiming(evidence.actionResult, step: step)
            appendCeiling(
                .intentWaitTimeout,
                budgetMs: Self.milliseconds(seconds: timeout.seconds),
                elapsedMs: evidence.actionResult.timing?.totalMs ?? step.durationMs,
                step: step
            )
        case .repeatUntil(let declaration, _), .repeatUntilIteration(let declaration, _):
            guard let evidence = step.repeatUntilEvidence else { return }
            appendWaitTiming(evidence.actionResult, step: step)
            appendCeiling(
                .repeatUntilTimeout,
                budgetMs: Self.milliseconds(seconds: declaration.timeout.seconds),
                elapsedMs: step.durationMs,
                step: step
            )
        case .invocation:
            guard let evidence = step.invocationEvidence else { return }
            let expectationResult = evidence.waitEvidence?.actionResult ?? evidence.expectationActionResult
            appendWaitTiming(expectationResult, step: step)
            append(.expectationWaitMs, valueMs: expectationResult?.timing?.totalMs, step: step)
        case .conditional:
            guard let evidence = step.caseSelectionEvidence else { return }
            appendCeiling(
                .caseSelectionTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.selection.timeout),
                elapsedMs: evidence.selection.elapsedMs,
                step: step
            )
        case .forEachElement,
             .forEachString,
             .forEachElementIteration,
             .forEachStringIteration,
             .warning,
             .failure,
             .heist:
            break
        }
    }

    mutating func append(
        _ name: HeistExecutionMetricName,
        valueMs: Int?,
        step: HeistExecutionStepResult? = nil
    ) {
        guard let valueMs else { return }
        samples.append(HeistExecutionMetricSample(
            name: name,
            valueMs: max(0, valueMs),
            path: step?.path,
            kind: step?.kind,
            status: step?.status
        ))
    }

    private mutating func appendActionTiming(
        _ result: ActionResult?,
        step: HeistExecutionStepResult
    ) {
        guard let result else { return }
        append(.actionPipelineTargetResolutionMs, valueMs: result.timing?.targetResolutionMs, step: step)
        append(.actionPipelineActionDispatchMs, valueMs: result.timing?.actionDispatchMs, step: step)
        append(.actionPipelineSettleMs, valueMs: result.settleTimeMs, step: step)
        append(.actionPipelineBeforeObservationMs, valueMs: result.timing?.beforeObservationMs, step: step)
        append(.actionPipelineFinalSemanticEvidenceMs, valueMs: result.timing?.finalSemanticEvidenceMs, step: step)
        append(.actionPipelineTotalMs, valueMs: result.timing?.totalMs, step: step)
    }

    private mutating func appendWaitTiming(
        _ result: ActionResult?,
        step: HeistExecutionStepResult
    ) {
        guard let result else { return }
        append(.waitPipelineTargetResolutionMs, valueMs: result.timing?.targetResolutionMs, step: step)
        append(.waitPipelineActionDispatchMs, valueMs: result.timing?.actionDispatchMs, step: step)
        append(.waitPipelineSettleMs, valueMs: result.settleTimeMs, step: step)
        append(.waitPipelineBeforeObservationMs, valueMs: result.timing?.beforeObservationMs, step: step)
        append(.waitPipelineFinalSemanticEvidenceMs, valueMs: result.timing?.finalSemanticEvidenceMs, step: step)
        append(.waitPipelineTotalMs, valueMs: result.timing?.totalMs, step: step)
    }

    private mutating func appendCeiling(
        _ source: HeistExecutionCeilingMetricSource,
        budgetMs: Int?,
        elapsedMs: Int,
        step: HeistExecutionStepResult
    ) {
        guard let budgetMs else { return }
        ceilings.append(HeistExecutionCeilingMetric(
            source: source,
            budgetMs: budgetMs,
            elapsedMs: max(0, elapsedMs),
            path: step.path,
            kind: step.kind,
            status: step.status
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
        [self].compactMapInReceiptOrder { $0.status == .skipped ? nil : $0 }.count
    }

    var isFailure: Bool {
        firstFailedStepInReceiptOrder != nil
    }

    var firstFailedStep: HeistExecutionStepResult? {
        firstFailedStepInReceiptOrder
    }

    /// Number of expectations evaluated in this subtree.
    var expectationsChecked: Int {
        [self].compactMapInReceiptOrder(\.reportExpectation).count
    }

    /// Number of evaluated expectations that were met in this subtree.
    var expectationsMet: Int {
        [self].compactMapInReceiptOrder(\.reportExpectation).count(where: \.met)
    }

    /// Trace-contributing results in execution order across this subtree.
    var traceResultsInExecutionOrder: [ActionResult] {
        [self].compactMapInReceiptOrder(\.reportActionResult)
    }
}

public extension Array where Element == HeistExecutionStepResult {
    var firstFailedStep: HeistExecutionStepResult? {
        firstFailedStepInReceiptOrder
    }
}

public extension HeistExecutionResult {
    /// Top-level heist body steps that actually began execution/evaluation.
    var executedTopLevelStepCount: Int {
        HeistExecutionReport.project(self).summary.executedTopLevelStepCount
    }

    /// All executed receipt nodes in the tree, including nested structural
    /// frames, iterations, and leaf action/wait/warn/fail nodes.
    var executedNodeCount: Int {
        HeistExecutionReport.project(self).summary.executedNodeCount
    }

    /// Whether any step in the execution tree failed.
    var isFailure: Bool {
        switch outcome {
        case .failed: true
        case .passed: false
        }
    }

    /// First failed receipt node. Child failures are canonical before compound
    /// parent frames that merely report an aborted child.
    var firstFailedStep: HeistExecutionStepResult? {
        steps.firstFailedStepInReceiptOrder
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
        HeistExecutionReport.project(self).summary.expectationsChecked
    }

    /// Total met expectations across the whole execution tree.
    var expectationsMet: Int {
        HeistExecutionReport.project(self).summary.expectationsMet
    }

    /// Runtime-evidence-facing action results for action commands actually
    /// dispatched.
    var dispatchedActionResults: [ActionResult] {
        steps.compactMapInReceiptOrder { $0.actionEvidence?.dispatchResult }
    }

    /// Human/report-facing action results. Expectation wait evidence may be the
    /// surfaced result when an action has an expectation.
    var reportedActionResults: [ActionResult] {
        steps.compactMapInReceiptOrder { $0.actionEvidence?.reportedResult }
    }

    /// Trace-contributing results in execution order across the whole tree.
    var traceResultsInExecutionOrder: [ActionResult] {
        steps.compactMapInReceiptOrder(\.reportActionResult)
    }

    /// Receipt nodes surfaced by linear output adapters in execution order.
    /// Skipped nodes remain visible because they are first-class receipt facts.
    var outputReceiptNodes: [HeistExecutionStepResult] {
        steps.compactMapInReceiptOrder { Optional($0) }
    }

    /// Warnings emitted by executed `Warn(...)` steps, in execution order.
    var warnings: [HeistExecutionWarning] {
        steps.compactMapInReceiptOrder(\.reportWarning)
    }
}

package extension HeistExecutionResult {
    var failureScreenshotStep: HeistExecutionStepResult? {
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

private extension Sequence where Element == HeistExecutionStepResult {
    func compactMapInReceiptOrder<Value>(_ transform: (Element) -> Value?) -> [Value] {
        var values: [Value] = []
        walk(enter: {
            if let value = transform($0) { values.append(value) }
        }, leave: { _ in })
        return values
    }
}

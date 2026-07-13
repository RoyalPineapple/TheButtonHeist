import Foundation
import ThePlans

// MARK: - Heist Report Facts
//
// Reporting consumes a typed evidence event stream derived from the execution
// tree. These facts live on the execution result types so encoders, formatters,
// and report adapters share one report model.

package struct HeistExecutionEvidenceRollup: Sendable, Equatable {
    package let rootNodes: [HeistExecutionEvidenceNode]
    package let nodes: [HeistExecutionEvidenceNode]
    package let events: [HeistExecutionEvidenceEvent]
    package let summary: HeistExecutionEvidenceSummary
    package let actions: HeistExecutionActionEvidenceRollup
    package let warnings: [HeistExecutionWarning]
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
        let rootNodes = steps.map(Self.node(from:))
        let reportRootNodes = rootNodes.dropLast(failureScreenshotStep == nil ? 0 : 1)
        var accumulator = HeistExecutionEvidenceAccumulator(durationMs: durationMs)
        for node in rootNodes {
            accumulator.visit(node)
        }

        self.rootNodes = rootNodes
        nodes = accumulator.nodes
        events = accumulator.events
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
        warnings = accumulator.warnings
        metrics = HeistExecutionMetricProjection(
            samples: accumulator.metricBuilder.samples,
            ceilings: accumulator.metricBuilder.ceilings
        )
        firstFailedStep = accumulator.firstFailedStep
        self.failureScreenshotStep = failureScreenshotStep
    }

    private static func node(from step: HeistExecutionStepResult) -> HeistExecutionEvidenceNode {
        HeistExecutionEvidenceNode(
            step: step,
            children: step.children.map(Self.node(from:))
        )
    }
}

private extension HeistExecutionResult {
    var trailingFailureScreenshotStep: HeistExecutionStepResult? {
        guard case .failed(let outcome) = outcome,
              let candidate = outcome.steps.last,
              candidate.path != outcome.abortedAtPath,
              case .action(let evidence)? = candidate.evidence,
              case .dispatch(let command, let result) = evidence
        else { return nil }
        return command == .takeScreenshot && result.method == .takeScreenshot ? candidate : nil
    }
}

package struct HeistExecutionEvidenceNode: Sendable, Equatable {
    package let step: HeistExecutionStepResult
    package let children: [HeistExecutionEvidenceNode]
    package let reportFacts: HeistExecutionStepReportFacts

    package init(
        step: HeistExecutionStepResult,
        children: [HeistExecutionEvidenceNode] = []
    ) {
        self.step = step
        self.children = children
        reportFacts = step.reportFacts
    }

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
    case firstFailure(HeistExecutionStepResult)
    case finalScreen(path: String, screenId: String)
}

private struct HeistExecutionEvidenceAccumulator {
    var nodes: [HeistExecutionEvidenceNode] = []
    var events: [HeistExecutionEvidenceEvent] = []
    var warnings: [HeistExecutionWarning] = []
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

    mutating func visit(_ node: HeistExecutionEvidenceNode) {
        record(.nodeVisited(node))
        let results = node.reportFacts.results
        if let dispatchResult = results.dispatchedActionResult {
            record(.dispatchedActionResult(path: node.step.path, result: dispatchResult))
        }
        if let reportedResult = results.reportedActionResult {
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

        let firstFailureEventIndex = events.count
        for child in node.children {
            visit(child)
        }
        if firstFailedStep == nil, node.step.status == .failed {
            firstFailedStep = node.step
            events.insert(.firstFailure(node.step), at: firstFailureEventIndex)
        }
    }

    private mutating func record(_ event: HeistExecutionEvidenceEvent) {
        events.append(event)
        switch event {
        case .nodeVisited(let node):
            nodes.append(node)
            executedNodeCount += node.isExecuted ? 1 : 0
            if let warning = node.reportFacts.warning {
                warnings.append(warning)
            }
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
    package let path: String?
    package let kind: HeistExecutionStepKind?
    package let status: HeistExecutionStepStatus?

    package init(
        name: HeistExecutionMetricName,
        valueMs: Int,
        path: String? = nil,
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
    package let path: String
    package let kind: HeistExecutionStepKind
    package let status: HeistExecutionStepStatus

    package init(
        source: HeistExecutionCeilingMetricSource,
        budgetMs: Int,
        elapsedMs: Int,
        path: String,
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
            let expectationResult = evidence.waitEvidence?.actionResult ?? evidence.expectationActionResult
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

package enum HeistExecutionStepReportResults: Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case none

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
        case .none:
            return nil
        }
    }

    package var reportedActionResult: ActionResult? {
        guard case .action(let evidence) = self else { return nil }
        return evidence.reportedResult
    }

    package var expectation: ExpectationResult? {
        switch self {
        case .action(let evidence):
            return evidence.dispatchResult?.outcome.isSuccess == false ? nil : evidence.checkedExpectation
        case .wait(let evidence):
            return evidence.expectation
        case .repeatUntil(let evidence):
            return evidence.expectation
        case .invocation(let evidence):
            return evidence.expectation
        case .none:
            return nil
        }
    }

    package var traceEvidenceResult: ActionResult? {
        actionResult
    }

    package var actionErrorKind: ErrorKind? {
        actionResult?.outcome.isSuccess == false ? actionResult?.outcome.errorKind : nil
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

    package var command: HeistActionCommandType? {
        guard case .action(let evidence) = self else { return nil }
        return evidence.command?.wireType
    }

    package var target: AccessibilityTarget? {
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

    package var warning: HeistExecutionWarning? {
        guard case .warning(let warning) = self else { return nil }
        return warning
    }

    package var results: HeistExecutionStepReportResults {
        switch self {
        case .action(let evidence):
            return .action(evidence)
        case .wait(let evidence):
            return .wait(evidence)
        case .repeatUntil(let evidence):
            return .repeatUntil(evidence)
        case .invocation(let evidence):
            return .invocation(evidence)
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
    package let kind: HeistExecutionStepKind
    package let capabilityName: String?
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
        let detail = HeistExecutionStepReportDetail(kind: step.kind, evidence: step.evidence)
        let results = detail.results

        path = step.path
        kind = step.kind
        capabilityName = detail.capabilityName
        invocationDisplayName = detail.invocationDisplayName
        command = detail.command
        target = detail.target
        status = step.status
        message = Self.message(for: step, detail: detail)
        failureMessage = Self.failureMessage(for: step)
        failureCategory = step.failure?.category
        self.results = results
        warning = detail.warning
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
        HeistExecutionEvidenceRollup(steps: self).firstFailedStep
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
        evidenceRollup.warnings
    }
}

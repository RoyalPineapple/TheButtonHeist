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
        let results = node.reportFacts.results
        if let dispatchResult = results.dispatchedActionResult {
            dispatchedResults.append(dispatchResult)
            events.append(.dispatchedActionResult(path: path, result: dispatchResult))
        }
        if node.step.kind == .action, let reportedResult = results.actionResult {
            reportedResults.append(reportedResult)
            events.append(.reportedActionResult(path: path, result: reportedResult))
        }
        if let traceResult = results.traceEvidenceResult {
            traceResultsInExecutionOrder.append(traceResult)
            events.append(.traceResult(path: path, result: traceResult))
            if let finalScreenId = traceResult.accessibilityTrace?.endpointScreenId {
                self.finalScreenId = finalScreenId
                events.append(.finalScreen(path: path, screenId: finalScreenId))
            }
        }
        if let expectation = results.expectation {
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

package struct HeistExecutionMetricProjection: Codable, Sendable, Equatable {
    package let samples: [HeistExecutionMetricSample]
    package let ceilings: [HeistExecutionCeilingMetric]

    package init(result: HeistExecutionResult) {
        self.init(rollup: HeistExecutionEvidenceRollup(result: result))
    }

    package init(rollup: HeistExecutionEvidenceRollup) {
        var builder = HeistExecutionMetricProjectionBuilder()
        builder.append(.heistDurationMs, valueMs: rollup.summary.durationMs)
        for node in rollup.nodes {
            builder.appendMetrics(for: node)
        }
        samples = builder.samples
        ceilings = builder.ceilings
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
        appendTimingMetrics(for: node)
        appendCeilingMetrics(for: node)
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

    private mutating func appendTimingMetrics(for node: HeistExecutionEvidenceNode) {
        switch node.step.evidence {
        case .action(let evidence):
            appendActionTiming(evidence.dispatchResult?.timing, node: node)
            if let expectationResult = evidence.expectationResult {
                appendWaitTiming(expectationResult.timing, node: node)
                append(.expectationWaitMs, valueMs: expectationResult.timing?.totalMs, node: node)
            }
        case .wait(let evidence):
            appendWaitTiming(evidence.actionResult.timing, node: node)
        case .repeatUntil(let evidence):
            appendWaitTiming(evidence.actionResult?.timing, node: node)
        case .invocation(let evidence):
            let expectationResult = evidence.expectationEvidence?.actionResult ?? evidence.expectationActionResult
            appendWaitTiming(expectationResult?.timing, node: node)
            append(.expectationWaitMs, valueMs: expectationResult?.timing?.totalMs, node: node)
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            break
        }
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

    private mutating func appendCeilingMetrics(for node: HeistExecutionEvidenceNode) {
        switch node.step.evidence {
        case .wait(let evidence):
            guard case .wait(_, let timeout) = node.step.intent else { return }
            appendCeiling(
                .intentWaitTimeout,
                budgetMs: Self.milliseconds(seconds: timeout),
                elapsedMs: evidence.actionResult.timing?.totalMs ?? node.step.durationMs,
                node: node
            )
        case .repeatUntil(let evidence):
            appendCeiling(
                .repeatUntilTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.timeout),
                elapsedMs: node.step.durationMs,
                node: node
            )
        case .caseSelection(let evidence):
            appendCeiling(
                .caseSelectionTimeout,
                budgetMs: Self.milliseconds(seconds: evidence.selection.timeout),
                elapsedMs: evidence.selection.elapsedMs,
                node: node
            )
        case .action, .forEachString, .forEachElement, .invocation, .warning, .none:
            break
        }
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
    package let traceEvidenceResult: ActionResult?
    package let expectation: ExpectationResult?
    package let actionErrorKind: ErrorKind?

    package init(
        dispatchedActionResult: ActionResult? = nil,
        actionResult: ActionResult? = nil,
        traceEvidenceResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        actionErrorKind: ErrorKind? = nil
    ) {
        self.dispatchedActionResult = dispatchedActionResult
        self.actionResult = actionResult
        self.traceEvidenceResult = traceEvidenceResult
        self.expectation = expectation
        self.actionErrorKind = actionErrorKind
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
        results.dispatchedActionResult
    }

    package var actionResult: ActionResult? {
        results.actionResult
    }

    package var traceEvidenceResult: ActionResult? {
        results.traceEvidenceResult
    }

    package var expectation: ExpectationResult? {
        results.expectation
    }

    package var actionErrorKind: ErrorKind? {
        results.actionErrorKind
    }

    package var results: HeistExecutionStepReportResults {
        switch self {
        case .action(let evidence):
            let actionResult = evidence.reportedResult
            return HeistExecutionStepReportResults(
                dispatchedActionResult: evidence.dispatchResult,
                actionResult: actionResult,
                traceEvidenceResult: evidence.traceResult,
                expectation: evidence.dispatchResult?.success == false ? nil : evidence.expectation,
                actionErrorKind: actionResult?.success == false ? actionResult?.errorKind : nil
            )
        case .wait(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.actionResult,
                traceEvidenceResult: evidence.actionResult,
                expectation: evidence.expectation
            )
        case .repeatUntil(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.actionResult,
                traceEvidenceResult: evidence.actionResult,
                expectation: evidence.expectation
            )
        case .invocation(let evidence):
            return HeistExecutionStepReportResults(
                actionResult: evidence.expectationActionResult,
                traceEvidenceResult: evidence.expectationActionResult,
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

    package var actionResult: ActionResult? {
        results.actionResult
    }

    package var expectation: ExpectationResult? {
        results.expectation
    }

    package var actionErrorKind: ErrorKind? {
        results.actionErrorKind
    }

    package var dispatchedActionResult: ActionResult? {
        results.dispatchedActionResult
    }

    package var traceEvidenceResult: ActionResult? {
        results.traceEvidenceResult
    }

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

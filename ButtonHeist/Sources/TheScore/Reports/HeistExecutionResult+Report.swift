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

    package var outputReceiptNodes: [HeistExecutionStepResult] {
        nodes.map(\.step)
    }

    package init(result: HeistExecutionResult) {
        self.init(steps: result.steps, durationMs: result.durationMs)
    }

    package init(
        steps: [HeistExecutionStepResult],
        durationMs: Int = 0
    ) {
        let folds = steps.map(HeistExecutionEvidenceFold.init(step:))
        let firstFailedStep = folds.lazy.compactMap(\.firstFailedStep).first
        let orderedFacts = folds.flatMap(\.orderedFacts)
        let events = orderedFacts.flatMap { $0.events(firstFailedStep: firstFailedStep) }
        let rootNodes = folds.map(\.node)
        let nodes = orderedFacts.map(\.node)
        let finalScreenId = events.compactMap(\.finalScreenId).last

        self.rootNodes = rootNodes
        self.nodes = nodes
        self.events = events
        summary = HeistExecutionEvidenceSummary(
            executedTopLevelStepCount: rootNodes.count {
                $0.isExecuted && HeistExecutionReceiptPlacement(step: $0.step) != .failureHookAction
            },
            executedNodeCount: nodes.count(where: \.isExecuted),
            outputReceiptNodeCount: nodes.count,
            abortedAtPath: firstFailedStep?.path,
            durationMs: durationMs,
            expectationsChecked: events.count(where: \.isExpectationChecked),
            expectationsMet: events.count(where: \.isExpectationMet),
            finalScreenId: finalScreenId
        )
        actions = HeistExecutionActionEvidenceRollup(
            dispatchedResults: events.compactMap(\.dispatchedActionResult),
            reportedResults: events.compactMap(\.reportedActionResult),
            traceResultsInExecutionOrder: events.compactMap(\.traceResult)
        )
        warnings = orderedFacts.compactMap(\.warning)
        metrics = HeistExecutionMetricProjection(durationMs: durationMs, orderedFacts: orderedFacts)
        self.firstFailedStep = firstFailedStep
    }
}

private struct HeistExecutionEvidenceFold {
    let node: HeistExecutionEvidenceNode
    let orderedFacts: [HeistExecutionNodeFacts]
    let firstFailedStep: HeistExecutionStepResult?

    init(step: HeistExecutionStepResult) {
        let childFolds = step.children.map(Self.init(step:))
        let childNodes = childFolds.map(\.node)
        let firstFailedStep = childFolds.lazy.compactMap(\.firstFailedStep).first
            ?? (step.status == .failed ? step : nil)
        let node = HeistExecutionEvidenceNode(
            step: step,
            children: childNodes
        )

        self.node = node
        orderedFacts = [HeistExecutionNodeFacts(node: node)]
            + childFolds.flatMap(\.orderedFacts)
        self.firstFailedStep = firstFailedStep
    }
}

private struct HeistExecutionNodeFacts {
    let node: HeistExecutionEvidenceNode
    let evidenceEvents: [HeistExecutionEvidenceEvent]
    let warning: HeistExecutionWarning?
    let metrics: HeistExecutionMetricProjection

    init(node: HeistExecutionEvidenceNode) {
        let path = node.step.path
        let results = node.reportFacts.results
        let traceResult = results.traceEvidenceResult
        let expectation = results.expectation
        self.node = node
        evidenceEvents = [
            .nodeVisited(node),
            results.dispatchedActionResult.map { .dispatchedActionResult(path: path, result: $0) },
            results.reportedActionResult.map { .reportedActionResult(path: path, result: $0) },
            traceResult.map { .traceResult(path: path, result: $0) },
            traceResult?.accessibilityTrace?.endpointScreenId.map { .finalScreen(path: path, screenId: $0) },
            expectation.map { .expectationChecked(path: path, result: $0) },
            expectation?.met == true ? expectation.map { .expectationMet(path: path, result: $0) } : nil,
        ].compactMap { $0 }
        warning = node.reportFacts.warning
        metrics = HeistExecutionMetricProjection(node: node)
    }

    func events(firstFailedStep: HeistExecutionStepResult?) -> [HeistExecutionEvidenceEvent] {
        guard let firstFailedStep, node.step == firstFailedStep else { return evidenceEvents }
        return evidenceEvents + [.firstFailure(node.step)]
    }
}

private enum HeistExecutionReceiptPlacement: Equatable {
    case ordinary
    case failureHookAction

    init(step: HeistExecutionStepResult) {
        let bodyPrefix = "$.body["
        let failureHookSuffix = ".failure.actions[0]"
        guard step.kind == .action,
              step.path.hasPrefix(bodyPrefix),
              step.path.hasSuffix(failureHookSuffix),
              let bodyClose = step.path.dropFirst(bodyPrefix.count).firstIndex(of: "]")
        else {
            self = .ordinary
            return
        }
        let bodyOrdinal = step.path[
            step.path.index(step.path.startIndex, offsetBy: bodyPrefix.count)..<bodyClose
        ]
        self = !bodyOrdinal.isEmpty && bodyOrdinal.utf8.allSatisfy { (48...57).contains($0) }
            ? .failureHookAction
            : .ordinary
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

private extension HeistExecutionEvidenceEvent {
    var dispatchedActionResult: ActionResult? {
        guard case .dispatchedActionResult(_, let result) = self else { return nil }
        return result
    }

    var reportedActionResult: ActionResult? {
        guard case .reportedActionResult(_, let result) = self else { return nil }
        return result
    }

    var traceResult: ActionResult? {
        guard case .traceResult(_, let result) = self else { return nil }
        return result
    }

    var isExpectationChecked: Bool {
        if case .expectationChecked = self { return true }
        return false
    }

    var isExpectationMet: Bool {
        if case .expectationMet = self { return true }
        return false
    }

    var finalScreenId: String? {
        guard case .finalScreen(_, let screenId) = self else { return nil }
        return screenId
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
        durationMs: Int,
        orderedFacts: [HeistExecutionNodeFacts]
    ) {
        samples = [HeistExecutionMetricSample(name: .heistDurationMs, valueMs: max(0, durationMs))]
            + orderedFacts.flatMap(\.metrics.samples)
        ceilings = orderedFacts.flatMap(\.metrics.ceilings)
    }

    fileprivate init(node: HeistExecutionEvidenceNode) {
        samples = Self.samples(for: node)
        ceilings = Self.ceiling(for: node).map { [$0] } ?? []
    }

    private static func samples(for node: HeistExecutionEvidenceNode) -> [HeistExecutionMetricSample] {
        switch node.step.evidence {
        case .action(let evidence):
            let expectationTiming = evidence.expectationResult?.timing
            return actionTimingSamples(evidence.dispatchResult?.timing, node: node)
                + waitTimingSamples(expectationTiming, node: node)
                + sample(.expectationWaitMs, valueMs: expectationTiming?.totalMs, node: node)
        case .wait(let evidence):
            return waitTimingSamples(evidence.actionResult.timing, node: node)
        case .repeatUntil(let evidence):
            return waitTimingSamples(evidence.actionResult?.timing, node: node)
        case .invocation(let evidence):
            let timing = (evidence.waitEvidence?.actionResult ?? evidence.expectationActionResult)?.timing
            return waitTimingSamples(timing, node: node)
                + sample(.expectationWaitMs, valueMs: timing?.totalMs, node: node)
        case .caseSelection, .forEachString, .forEachElement, .warning, .none:
            return []
        }
    }

    private static func actionTimingSamples(
        _ timing: ActionPerformanceTiming?,
        node: HeistExecutionEvidenceNode
    ) -> [HeistExecutionMetricSample] {
        guard let timing else { return [] }
        return [
            sample(.actionPipelineTargetResolutionMs, valueMs: timing.targetResolutionMs, node: node),
            sample(.actionPipelineActionDispatchMs, valueMs: timing.actionDispatchMs, node: node),
            sample(.actionPipelineSettleMs, valueMs: timing.settleMs, node: node),
            sample(.actionPipelineBeforeObservationMs, valueMs: timing.beforeObservationMs, node: node),
            sample(.actionPipelineFinalSemanticEvidenceMs, valueMs: timing.finalSemanticEvidenceMs, node: node),
            sample(.actionPipelineTotalMs, valueMs: timing.totalMs, node: node),
        ].flatMap { $0 }
    }

    private static func waitTimingSamples(
        _ timing: ActionPerformanceTiming?,
        node: HeistExecutionEvidenceNode
    ) -> [HeistExecutionMetricSample] {
        guard let timing else { return [] }
        return [
            sample(.waitPipelineTargetResolutionMs, valueMs: timing.targetResolutionMs, node: node),
            sample(.waitPipelineActionDispatchMs, valueMs: timing.actionDispatchMs, node: node),
            sample(.waitPipelineSettleMs, valueMs: timing.settleMs, node: node),
            sample(.waitPipelineBeforeObservationMs, valueMs: timing.beforeObservationMs, node: node),
            sample(.waitPipelineFinalSemanticEvidenceMs, valueMs: timing.finalSemanticEvidenceMs, node: node),
            sample(.waitPipelineTotalMs, valueMs: timing.totalMs, node: node),
        ].flatMap { $0 }
    }

    private static func sample(
        _ name: HeistExecutionMetricName,
        valueMs: Int?,
        node: HeistExecutionEvidenceNode
    ) -> [HeistExecutionMetricSample] {
        guard let valueMs else { return [] }
        return [HeistExecutionMetricSample(
            name: name,
            valueMs: max(0, valueMs),
            path: node.reportFacts.path,
            kind: node.reportFacts.kind,
            status: node.reportFacts.status
        )]
    }

    private static func ceiling(for node: HeistExecutionEvidenceNode) -> HeistExecutionCeilingMetric? {
        let source: HeistExecutionCeilingMetricSource
        let budgetMs: Int?
        let elapsedMs: Int
        switch node.step.evidence {
        case .wait(let evidence):
            guard case .wait(_, let timeout) = node.step.intent else { return nil }
            source = .intentWaitTimeout
            budgetMs = milliseconds(seconds: timeout)
            elapsedMs = evidence.actionResult.timing?.totalMs ?? node.step.durationMs
        case .repeatUntil(let evidence):
            source = .repeatUntilTimeout
            budgetMs = milliseconds(seconds: evidence.timeout)
            elapsedMs = node.step.durationMs
        case .caseSelection(let evidence):
            source = .caseSelectionTimeout
            budgetMs = milliseconds(seconds: evidence.selection.timeout)
            elapsedMs = evidence.selection.elapsedMs
        case .action, .forEachString, .forEachElement, .invocation, .warning, .none:
            return nil
        }
        guard let budgetMs else { return nil }
        return HeistExecutionCeilingMetric(
            source: source,
            budgetMs: budgetMs,
            elapsedMs: max(0, elapsedMs),
            path: node.reportFacts.path,
            kind: node.reportFacts.kind,
            status: node.reportFacts.status
        )
    }

    private static func milliseconds(seconds: Double?) -> Int? {
        guard let seconds, seconds.isFinite else { return nil }
        return max(0, Int((seconds * 1_000).rounded()))
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

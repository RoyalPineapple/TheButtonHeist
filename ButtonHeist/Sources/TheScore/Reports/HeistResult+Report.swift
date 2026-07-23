import Foundation
import ThePlans

/// The canonical semantic interpretation of a completed heist execution.
public struct HeistReport: Sendable, Equatable {
    public struct Summary: Sendable, Equatable {
        public let executedTopLevelStepCount: Int
        public let executedNodeCount: Int
        public let outputNodeCount: Int
        public let abortedAtPath: HeistExecutionPath?
        public let durationMs: Int
        public let expectations: Expectations?
        public let finalScreenId: String?

        public var expectationsChecked: Int { expectations?.checked ?? 0 }
        public var expectationsMet: Int { expectations?.met ?? 0 }
    }

    public struct Expectations: Sendable, Equatable {
        public let checked: Int
        public let met: Int
        public var allMet: Bool { checked == met }
    }

    public struct Failure: Sendable, Equatable {
        public let detail: HeistFailureDetail
        /// The failure headline for this node. Compound wrappers whose child
        /// supplies the actionable failure intentionally have no headline.
        public let message: String?
        public let actionKind: ActionFailure.Kind?

        package var diagnosticMessage: String { message ?? detail.observed }
    }

    public struct Node: Sendable, Equatable {
        public let path: HeistExecutionPath
        public let kind: HeistExecutionStepKind
        public let capability: HeistInvocationPath?
        public let invocationDisplayName: String?
        public let command: HeistActionCommandType?
        public let target: AccessibilityTarget?
        public let status: HeistExecutionStepStatus
        public let message: String?
        public let durationMs: Int
        public let failure: Failure?
        public let abortedAtChildPath: HeistExecutionPath?
        public let expectation: ExpectationResult?
        public let settlement: ActionSettlementEvidence?
        public let activationTrace: ActivationTrace?
        public let children: [Node]
        package let evidence: Evidence?

        public var warning: HeistExecutionWarning? {
            guard case .warning(let warning) = evidence else { return nil }
            return warning
        }

        package init(step: HeistExecutionStepResult, children: [Node]) {
            let actionResult = step.reportActionResult
            path = step.path
            kind = step.kind
            capability = step.invocation?.path
            invocationDisplayName = step.invocation?.runHeistSummary
            command = step.actionCommand?.wireType
            target = step.reportTarget
            status = step.status
            message = step.reportMessage
            durationMs = step.durationMs.milliseconds
            failure = step.failure.map {
                Failure(
                    detail: $0,
                    message: step.reportFailureMessage,
                    actionKind: actionResult.flatMap {
                        $0.outcome.isSuccess ? nil : $0.outcome.failureKind
                    }
                )
            }
            abortedAtChildPath = step.abortedAtChildPath
            expectation = step.reportExpectation
            settlement = actionResult?.evidence.settlement
            activationTrace = actionResult?.activationTrace
            self.children = children
            evidence = Evidence(step: step)
        }
    }

    package enum Evidence: Sendable, Equatable {
        case action(command: HeistActionCommand, evidence: HeistActionEvidence)
        case wait(HeistWaitEvidence)
        case caseSelection(HeistCaseSelectionEvidence)
        case forEachString(declaration: HeistForEachStringDeclaration, evidence: HeistForEachStringEvidence)
        case forEachElement(declaration: HeistForEachElementDeclaration, evidence: HeistForEachElementEvidence)
        case repeatUntil(declaration: HeistRepeatUntilDeclaration, evidence: HeistRepeatUntilEvidence)
        case invocation(invocation: HeistInvocationStep, evidence: HeistInvocationEvidence)
        case warning(HeistExecutionWarning)

        init?(step: HeistExecutionStepResult) {
            switch step.node {
            case .action(let command, _):
                guard let evidence = step.actionEvidence else { return nil }
                self = .action(command: command, evidence: evidence)
            case .wait:
                guard let evidence = step.waitEvidence else { return nil }
                self = .wait(evidence)
            case .conditional:
                guard let evidence = step.caseSelectionEvidence else { return nil }
                self = .caseSelection(evidence)
            case .forEachString(let declaration, _), .forEachStringIteration(let declaration, _):
                guard let evidence = step.forEachStringEvidence else { return nil }
                self = .forEachString(declaration: declaration, evidence: evidence)
            case .forEachElement(let declaration, _), .forEachElementIteration(let declaration, _):
                guard let evidence = step.forEachElementEvidence else { return nil }
                self = .forEachElement(declaration: declaration, evidence: evidence)
            case .repeatUntil(let declaration, _), .repeatUntilIteration(let declaration, _):
                guard let evidence = step.repeatUntilEvidence else { return nil }
                self = .repeatUntil(declaration: declaration, evidence: evidence)
            case .invocation(let path, let argument, _):
                guard let evidence = step.invocationEvidence else { return nil }
                self = .invocation(
                    invocation: HeistInvocationStep(path: path, argument: argument),
                    evidence: evidence
                )
            case .warning:
                guard let warning = step.warningEvidence else { return nil }
                self = .warning(warning)
            case .failure, .heist:
                return nil
            }
        }
    }

    public struct Diagnostics: Sendable, Equatable {
        public let failureScreenshotSummary: String?
        package let failureInterface: Interface?

        package func failureInterfaceDump(elementLimit: Int) -> String? {
            failureInterface.map {
                HeistFailureDiagnostics.interfaceDump($0, elementLimit: elementLimit)
            }
        }
    }

    public enum AccessibilityChange: Sendable, Equatable {
        case notApplicable
        case incomplete
        case unchanged
        case changed(AccessibilityTrace)
    }

    public struct Metrics: Codable, Sendable, Equatable {
        public let measurements: [Measurement]
        public let ceilings: [CeilingMetric]
    }

    public enum MetricName: String, Codable, Sendable, Equatable, CaseIterable {
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

    public struct Measurement: Codable, Sendable, Equatable {
        public let name: MetricName
        public let valueMs: ElapsedMilliseconds
        public let path: HeistExecutionPath?
        public let kind: HeistExecutionStepKind?
        public let status: HeistExecutionStepStatus?

        public init(
            name: MetricName,
            valueMs: ElapsedMilliseconds,
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

    public enum CeilingMetricSource: String, Codable, Sendable, Equatable, CaseIterable {
        case intentWaitTimeout = "intent.wait.timeout"
        case repeatUntilTimeout = "repeatUntil.timeout"
        case caseSelectionTimeout = "caseSelection.timeout"
    }

    public struct CeilingMetric: Codable, Sendable, Equatable {
        public let source: CeilingMetricSource
        public let budgetMs: ElapsedMilliseconds
        public let elapsedMs: ElapsedMilliseconds
        public let path: HeistExecutionPath
        public let kind: HeistExecutionStepKind
        public let status: HeistExecutionStepStatus

        public init(
            source: CeilingMetricSource,
            budgetMs: ElapsedMilliseconds,
            elapsedMs: ElapsedMilliseconds,
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

    public let summary: Summary
    public let metrics: Metrics
    public let nodes: [Node]
    public let outputNodes: [Node]
    public let failure: Failure?
    public let warnings: [HeistExecutionWarning]
    public let diagnostics: Diagnostics
    public let accessibilityChange: AccessibilityChange

    /// Interprets the result tree once and produces every semantic report fact.
    public static func project(result: HeistResult) -> HeistReport {
        var reducer = Reducer(durationMs: result.durationMs)
        result.steps.walk(enter: { reducer.enter($0) }, leave: { reducer.leave($0) })
        return reducer.report(result: result)
    }
}

private extension HeistReport {
    struct Frame {
        let sequence: Int
        let step: HeistExecutionStepResult
        var children: [Node] = []
    }

    struct Reducer {
        let durationMs: ElapsedMilliseconds
        var frames: [Frame] = []
        var roots: [Node] = []
        var outputNodes: [Node?] = []
        var executedNodeCount = 0
        var expectationsChecked = 0
        var expectationsMet = 0
        var finalScreenId: String?
        var firstFailedStep: HeistExecutionStepResult?
        var firstFailure: Failure?
        var warnings: [HeistExecutionWarning] = []
        var metricAccumulator: MetricAccumulator

        init(durationMs: ElapsedMilliseconds) {
            self.durationMs = durationMs
            var metricAccumulator = MetricAccumulator()
            metricAccumulator.append(.heistDurationMs, valueMs: durationMs)
            self.metricAccumulator = metricAccumulator
        }

        mutating func enter(_ step: HeistExecutionStepResult) {
            frames.append(Frame(sequence: outputNodes.count, step: step))
            outputNodes.append(nil)
            executedNodeCount += step.status == .skipped ? 0 : 1
            metricAccumulator.appendMetrics(for: step)
            if let screenId = step.reportActionResult?.accessibilityTrace?.endpointScreenId {
                finalScreenId = screenId
            }
            if let expectation = step.reportExpectation {
                expectationsChecked += 1
                expectationsMet += expectation.met ? 1 : 0
            }
            if let warning = step.warningEvidence {
                warnings.append(warning)
            }
        }

        mutating func leave(_ step: HeistExecutionStepResult) {
            guard let frame = frames.popLast() else { return }
            let node = Node(step: step, children: frame.children)
            outputNodes[frame.sequence] = node
            if firstFailure == nil, let failure = node.failure, node.status == .failed {
                firstFailedStep = step
                firstFailure = failure
            }
            if frames.isEmpty {
                roots.append(node)
            } else {
                frames[frames.index(before: frames.endIndex)].children.append(node)
            }
        }

        func report(result: HeistResult) -> HeistReport {
            let executedRoots = result.steps.dropLast(result.failureScreenshotStep == nil ? 0 : 1)
            let expectations = expectationsChecked > 0
                ? Expectations(checked: expectationsChecked, met: expectationsMet)
                : nil

            return HeistReport(
                summary: Summary(
                    executedTopLevelStepCount: executedRoots.count { $0.status != .skipped },
                    executedNodeCount: executedNodeCount,
                    outputNodeCount: outputNodes.count,
                    abortedAtPath: firstFailedStep?.path,
                    durationMs: durationMs.milliseconds,
                    expectations: expectations,
                    finalScreenId: finalScreenId
                ),
                metrics: Metrics(
                    measurements: metricAccumulator.measurements,
                    ceilings: metricAccumulator.ceilings
                ),
                nodes: roots,
                outputNodes: outputNodes.compactMap { $0 },
                failure: firstFailure,
                warnings: warnings,
                diagnostics: Diagnostics(
                    failureScreenshotSummary: result.failureScreenshotSummary,
                    failureInterface: result.failureDiagnosticInterface
                ),
                accessibilityChange: AccessibilityChange(result: result)
            )
        }
    }
}

private extension HeistReport.AccessibilityChange {
    init(result: HeistResult) {
        let dispatchedActions = result.steps.compactMapInResultOrder {
            $0.actionEvidence?.dispatchResult
        }
        guard !dispatchedActions.isEmpty else {
            self = .notApplicable
            return
        }
        guard dispatchedActions.allSatisfy({ $0.traceEvidence?.isComplete == true }) else {
            self = .incomplete
            return
        }

        let traceResults = result.steps.compactMapInResultOrder(\.reportActionResult)
        guard traceResults.allSatisfy({ $0.traceEvidence?.isComplete == true }) else {
            self = .incomplete
            return
        }
        guard let trace = AccessibilityTrace.combinedTrace(
            from: traceResults.compactMap(\.accessibilityTrace)
        ) else {
            self = .unchanged
            return
        }
        self = .changed(trace)
    }
}

private struct MetricAccumulator {
    var measurements: [HeistReport.Measurement] = []
    var ceilings: [HeistReport.CeilingMetric] = []

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
        _ name: HeistReport.MetricName,
        valueMs: ElapsedMilliseconds?,
        step: HeistExecutionStepResult? = nil
    ) {
        guard let valueMs else { return }
        measurements.append(HeistReport.Measurement(
            name: name,
            valueMs: valueMs,
            path: step?.path,
            kind: step?.kind,
            status: step?.status
        ))
    }

    private mutating func appendActionTiming(_ result: ActionResult?, step: HeistExecutionStepResult) {
        guard let result else { return }
        append(.actionPipelineTargetResolutionMs, valueMs: result.timing?.targetResolutionMs, step: step)
        append(.actionPipelineActionDispatchMs, valueMs: result.timing?.actionDispatchMs, step: step)
        append(.actionPipelineSettleMs, valueMs: result.settleTimeMs, step: step)
        append(.actionPipelineBeforeObservationMs, valueMs: result.timing?.beforeObservationMs, step: step)
        append(.actionPipelineFinalSemanticEvidenceMs, valueMs: result.timing?.finalSemanticEvidenceMs, step: step)
        append(.actionPipelineTotalMs, valueMs: result.timing?.totalMs, step: step)
    }

    private mutating func appendWaitTiming(_ result: ActionResult?, step: HeistExecutionStepResult) {
        guard let result else { return }
        append(.waitPipelineTargetResolutionMs, valueMs: result.timing?.targetResolutionMs, step: step)
        append(.waitPipelineActionDispatchMs, valueMs: result.timing?.actionDispatchMs, step: step)
        append(.waitPipelineSettleMs, valueMs: result.settleTimeMs, step: step)
        append(.waitPipelineBeforeObservationMs, valueMs: result.timing?.beforeObservationMs, step: step)
        append(.waitPipelineFinalSemanticEvidenceMs, valueMs: result.timing?.finalSemanticEvidenceMs, step: step)
        append(.waitPipelineTotalMs, valueMs: result.timing?.totalMs, step: step)
    }

    private mutating func appendCeiling(
        _ source: HeistReport.CeilingMetricSource,
        budgetMs: ElapsedMilliseconds?,
        elapsedMs: ElapsedMilliseconds,
        step: HeistExecutionStepResult
    ) {
        guard let budgetMs else { return }
        ceilings.append(HeistReport.CeilingMetric(
            source: source,
            budgetMs: budgetMs,
            elapsedMs: elapsedMs,
            path: step.path,
            kind: step.kind,
            status: step.status
        ))
    }

    private static func milliseconds(seconds: Double?) -> ElapsedMilliseconds? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let roundedMilliseconds = (seconds * 1_000).rounded()
        guard roundedMilliseconds.isFinite, roundedMilliseconds <= Double(Int.max) else { return nil }
        return requireValidLiteralPayload {
            try ElapsedMilliseconds(validatingMilliseconds: Int(roundedMilliseconds))
        }
    }
}

public extension HeistExecutionStepResult {
    var isFailure: Bool { firstFailedStepInResultOrder != nil }
    var firstFailedStep: HeistExecutionStepResult? { firstFailedStepInResultOrder }
}

public extension Array where Element == HeistExecutionStepResult {
    var firstFailedStep: HeistExecutionStepResult? { firstFailedStepInResultOrder }
}

public extension HeistResult {
    var isFailure: Bool {
        switch outcome {
        case .failed: true
        case .passed: false
        }
    }

    var firstFailedStep: HeistExecutionStepResult? { steps.firstFailedStepInResultOrder }
    var failedStepPath: HeistExecutionPath? { firstFailedStep?.path }
    var failedStepKind: HeistExecutionStepKind? { firstFailedStep?.kind }

    var outputNodes: [HeistExecutionStepResult] {
        steps.compactMapInResultOrder { Optional($0) }
    }

}

package extension HeistReport {
    var failedNode: Node? {
        if let abortedAtPath = summary.abortedAtPath,
           let node = outputNodes.first(where: { $0.path == abortedAtPath }) {
            return node
        }
        return outputNodes.first(where: { $0.status == .failed })
    }
}

package extension HeistResult {
    var failureScreenshotStep: HeistExecutionStepResult? {
        guard case .failed(let abortedAtPath) = outcome,
              let candidate = steps.last,
              candidate.path != abortedAtPath,
              candidate.actionCommand == .takeScreenshot,
              candidate.actionEvidence?.dispatchResult?.method == .takeScreenshot
        else { return nil }
        return candidate
    }

}

private extension Sequence where Element == HeistExecutionStepResult {
    func compactMapInResultOrder<Value>(_ transform: (Element) -> Value?) -> [Value] {
        var values: [Value] = []
        walk(enter: {
            if let value = transform($0) { values.append(value) }
        }, leave: { _ in })
        return values
    }
}

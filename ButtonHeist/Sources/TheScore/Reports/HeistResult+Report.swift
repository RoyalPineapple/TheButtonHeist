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
        public let failure: Failure?
        public let abortedAtChildPath: HeistExecutionPath?
        public let activationTrace: ActivationTrace?
        public let children: [Node]
        package let evidence: Evidence?

        public var expectation: ExpectationResult? {
            switch evidence {
            case .action(_, _, let expectation):
                expectation
            case .wait(_, let expectation, _):
                expectation
            case .caseSelection,
                 .forEachString,
                 .forEachElement,
                 .repeatUntil,
                 .invocation,
                 .warning,
                 nil:
                nil
            }
        }

        public var warning: HeistExecutionWarning? {
            guard case .warning(let warning) = evidence else { return nil }
            return warning
        }

        package init(
            step: HeistExecutionStepResult,
            children: [Node]
        ) throws(Observation.Gap) {
            let actionResult = step.reportActionResult
            path = step.path
            kind = step.kind
            capability = step.invocation?.path
            invocationDisplayName = step.invocation?.runHeistSummary
            command = step.actionCommand?.wireType
            target = step.reportTarget
            status = step.status
            message = step.reportMessage
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
            activationTrace = actionResult?.activationTrace
            self.children = children
            evidence = try Evidence(step: step)
        }
    }

    package enum Evidence: Sendable, Equatable {
        case action(
            command: HeistActionCommand,
            evidence: HeistActionEvidence,
            expectation: ExpectationResult?
        )
        case wait(
            evidence: HeistExpectationEvidence,
            expectation: ExpectationResult,
            outcome: HeistPredicateEvidenceOutcome
        )
        case caseSelection(HeistCaseSelectionEvidence)
        case forEachString(declaration: HeistForEachStringDeclaration, evidence: HeistForEachStringEvidence)
        case forEachElement(declaration: HeistForEachElementDeclaration, evidence: HeistForEachElementEvidence)
        case repeatUntil(declaration: HeistRepeatUntilDeclaration, evidence: HeistRepeatUntilEvidence)
        case invocation(invocation: HeistInvocationStep, evidence: HeistInvocationEvidence)
        case warning(HeistExecutionWarning)

        init?(step: HeistExecutionStepResult) throws(Observation.Gap) {
            switch step.node {
            case .action(let command, _):
                guard let evidence = step.actionEvidence else { return nil }
                self = .action(
                    command: command,
                    evidence: evidence,
                    expectation: try step.replayExpectation()
                )
            case .wait:
                guard let evidence = step.waitEvidence else { return nil }
                let expectation = try evidence.replay()
                let outcome: HeistPredicateEvidenceOutcome = switch (step.status, expectation.met) {
                case (.passed, true): .matched
                case (.passed, false): .handledElse
                default: .failed
                }
                self = .wait(
                    evidence: evidence,
                    expectation: expectation,
                    outcome: outcome
                )
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

    public struct Metrics: Codable, Sendable, Equatable {
        public let measurements: [Measurement]
        public let ceilings: [CeilingMetric]
    }

    public enum MetricName: String, Codable, Sendable, Equatable, CaseIterable {
        case heistDurationMs
        case actionPipelineTargetResolutionMs = "actionPipeline.targetResolutionMs"
        case actionPipelineActionDispatchMs = "actionPipeline.actionDispatchMs"
        case actionPipelineTotalMs = "actionPipeline.totalMs"
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
    public let failure: Failure?
    public let warnings: [HeistExecutionWarning]
    public let diagnostics: Diagnostics

    public var outputNodes: [Node] {
        var output: [Node] = []
        for node in nodes {
            node.appendInExecutionOrder(to: &output)
        }
        return output
    }

    /// Interprets the result tree once and produces every semantic report fact.
    ///
    /// Throws the recorded observation gap when expectation truth cannot be
    /// replayed from complete evidence.
    public static func project(result: HeistResult) throws(Observation.Gap) -> HeistReport {
        var reducer = Reducer(durationMs: result.durationMs)
        try result.steps.walk(
            enter: { (step: HeistExecutionStepResult) throws(Observation.Gap) in
                reducer.enter(step)
            },
            leave: { (step: HeistExecutionStepResult) throws(Observation.Gap) in
                try reducer.leave(step)
            }
        )
        return reducer.report(result: result)
    }
}

private extension HeistReport {
    struct Frame {
        let step: HeistExecutionStepResult
        var children: [Node] = []
    }

    struct Reducer {
        let durationMs: ElapsedMilliseconds
        var frames: [Frame] = []
        var roots: [Node] = []
        var outputNodeCount = 0
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
            frames.append(Frame(step: step))
            outputNodeCount += 1
            executedNodeCount += step.status == .skipped ? 0 : 1
            metricAccumulator.appendMetrics(for: step)
            if let screenId = step.reportActionResult?
                .observationEvidence?
                .current?
                .context
                .screenId {
                finalScreenId = screenId
            }
            if let warning = step.warningEvidence {
                warnings.append(warning)
            }
        }

        mutating func leave(_ step: HeistExecutionStepResult) throws(Observation.Gap) {
            guard let frame = frames.popLast() else { return }
            let node = try Node(step: step, children: frame.children)
            if let expectation = node.expectation {
                expectationsChecked += 1
                expectationsMet += expectation.met ? 1 : 0
            }
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
                    outputNodeCount: outputNodeCount,
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
                failure: firstFailure,
                warnings: warnings,
                diagnostics: Diagnostics(
                    failureScreenshotSummary: result.failureScreenshotSummary,
                    failureInterface: result.failureDiagnosticInterface
                )
            )
        }
    }
}

private extension HeistReport.Node {
    func appendInExecutionOrder(to nodes: inout [HeistReport.Node]) {
        nodes.append(self)
        for child in children {
            child.appendInExecutionOrder(to: &nodes)
        }
    }
}

private struct MetricAccumulator {
    var measurements: [HeistReport.Measurement] = []
    var ceilings: [HeistReport.CeilingMetric] = []

    mutating func appendMetrics(for step: HeistExecutionStepResult) {
        switch step.node {
        case .action:
            guard let evidence = step.actionEvidence else { return }
            appendActionTiming(evidence.result, step: step)
        case .wait:
            break
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
             .repeatUntil,
             .repeatUntilIteration,
             .warning,
             .failure,
             .heist,
             .invocation:
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
        append(.actionPipelineTotalMs, valueMs: result.timing?.totalMs, step: step)
    }

    private mutating func appendCeiling(
        _ source: HeistReport.CeilingMetricSource,
        budgetMs: ElapsedMilliseconds?,
        elapsedMs: ElapsedMilliseconds?,
        step: HeistExecutionStepResult
    ) {
        guard let budgetMs, let elapsedMs else { return }
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
              candidate.actionEvidence?.result?.method == .takeScreenshot
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

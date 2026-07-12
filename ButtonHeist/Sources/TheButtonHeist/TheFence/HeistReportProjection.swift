import ThePlans
import TheScore

struct HeistReportFailureProjection: Sendable {
    let detail: HeistFailureDetail
    let diagnosticFailure: DiagnosticFailure

    init(detail: HeistFailureDetail, message: String, actionErrorKind: ErrorKind?) {
        self.detail = detail
        if let actionErrorKind {
            diagnosticFailure = DiagnosticFailureMapper.map(errorKind: actionErrorKind, message: message)
        } else {
            diagnosticFailure = DiagnosticFailureMapper.map(reportFailure: detail, message: message)
        }
    }
}

struct HeistReportSummaryProjection: Sendable {
    private let summary: HeistExecutionEvidenceSummary

    init(summary: HeistExecutionEvidenceSummary) {
        self.summary = summary
    }

    var executedTopLevelStepCount: Int { summary.executedTopLevelStepCount }
    var executedNodeCount: Int { summary.executedNodeCount }
    var outputReceiptNodeCount: Int { summary.outputReceiptNodeCount }
    var abortedAtPath: String? { summary.abortedAtPath }
    var durationMs: Int { summary.durationMs }
    var expectations: HeistExpectationsProjection? {
        summary.expectationsChecked > 0
            ? HeistExpectationsProjection(checked: summary.expectationsChecked, met: summary.expectationsMet)
            : nil
    }
    var finalScreenId: String? { summary.finalScreenId }
}

struct HeistExpectationsProjection: Sendable {
    let checked: Int
    let met: Int
    var allMet: Bool { checked == met }

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
    }
}

struct HeistReportProjection: Sendable {
    let status: PublicResponseStatus
    let summary: HeistReportSummaryProjection
    let metrics: HeistExecutionMetricProjection
    let nodes: [HeistReportNodeProjection]
    let outputNodes: [HeistReportNodeProjection]
    let failedStepPath: String?
    let failureScreenshotSummary: String?
    let failureInterfaceDump: String?
    let netDelta: DeltaProjection?

    init(
        result: HeistExecutionResult,
        accessibilityTrace: AccessibilityTrace?,
        profile: ProjectionProfile
    ) {
        let profile = profile.heistReport
        let rollup = result.evidenceRollup
        let reportSummary = rollup.summary
        status = reportSummary.abortedAtPath == nil ? .ok : .partial
        nodes = rollup.rootNodes.map { HeistReportNodeProjection(node: $0, profile: profile) }
        outputNodes = rollup.nodes.map { HeistReportNodeProjection(node: $0, profile: profile) }
        summary = HeistReportSummaryProjection(summary: reportSummary)
        metrics = HeistExecutionMetricProjection(rollup: rollup)
        failedStepPath = reportSummary.abortedAtPath
        failureScreenshotSummary = result.failureScreenshotSummary
        failureInterfaceDump = result.failureInterfaceDump(
            elementLimit: profile.limits.failureInterfaceElements
        )
        self.netDelta = accessibilityTrace.flatMap {
            DeltaProjection(trace: $0, isComplete: true, profile: profile, includeScreenInterface: true)
        }
    }
}

private extension ProjectionProfile {
    var heistReport: ProjectionProfile {
        kind == .summary ? .mcp : self
    }
}

struct HeistReportNodeProjection: Sendable {
    private let node: HeistExecutionEvidenceNode
    private let profile: ProjectionProfile
    let children: [HeistReportNodeProjection]

    init(node: HeistExecutionEvidenceNode, profile: ProjectionProfile) {
        self.node = node
        self.profile = profile
        children = node.children.map { HeistReportNodeProjection(node: $0, profile: profile) }
    }

    private var step: HeistExecutionStepResult { node.step }
    private var report: HeistExecutionStepReportFacts { node.reportFacts }
    private var results: HeistExecutionStepReportResults { report.results }

    var path: String { report.path }
    var kind: String { report.kind }
    var capability: String? { report.capabilityName }
    var displayName: String { report.displayName }
    var commandName: String? { report.commandName }
    var target: AccessibilityTarget? { report.target }
    var status: HeistExecutionStepStatus { report.status }
    var message: String? { report.message }
    var durationMs: Int { step.durationMs }
    var intent: HeistStepIntent? { step.intent }
    var evidence: HeistReportEvidenceProjection? { HeistReportEvidenceProjection(node: node, profile: profile) }
    var failureMessage: String? { report.failureMessage }
    var failure: HeistReportFailureProjection? {
        step.failure.map {
            HeistReportFailureProjection(
                detail: $0,
                message: report.failureMessage ?? $0.observed,
                actionErrorKind: results.actionErrorKind
            )
        }
    }
    var failureCategory: HeistFailureCategory? { report.failureCategory }
    var abortedAtChildPath: String? { step.abortedAtChildPath }
    var expectation: ExpectationProjection? { results.expectation.map { ExpectationProjection(result: $0) } }
    var actionErrorKind: ErrorKind? { results.actionErrorKind }
    var traceDelta: DeltaProjection? {
        results.traceEvidenceResult.flatMap { result in
            result.accessibilityTrace.flatMap {
                DeltaProjection(
                    trace: $0,
                    isComplete: result.settled != false,
                    profile: profile,
                    includeScreenInterface: true
                )
            }
        }
    }
}

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
    private let summary: HeistExecutionReport.Summary

    init(summary: HeistExecutionReport.Summary) {
        self.summary = summary
    }

    var executedTopLevelStepCount: Int { summary.executedTopLevelStepCount }
    var executedNodeCount: Int { summary.executedNodeCount }
    var outputReceiptNodeCount: Int { summary.outputReceiptNodeCount }
    var abortedAtPath: String? { summary.abortedAtPath?.description }
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
        let report = HeistExecutionReport.project(result)
        let reportSummary = report.summary
        status = reportSummary.abortedAtPath == nil ? .ok : .partial
        nodes = result.steps.map { HeistReportNodeProjection(step: $0, profile: profile) }
        outputNodes = result.outputReceiptNodes.map { HeistReportNodeProjection(step: $0, profile: profile) }
        summary = HeistReportSummaryProjection(summary: reportSummary)
        metrics = report.metrics
        failedStepPath = reportSummary.abortedAtPath?.description
        failureScreenshotSummary = result.failureScreenshotSummary
        failureInterfaceDump = result.failureInterfaceDump(
            elementLimit: profile.limits.failureInterfaceElements
        )
        self.netDelta = accessibilityTrace.flatMap {
            DeltaProjection(trace: $0, isComplete: true, profile: profile, includeScreenInterface: true)
        }
    }
}

struct HeistReportNodeProjection: Sendable {
    private let step: HeistExecutionStepResult
    private let profile: ProjectionProfile
    let children: [HeistReportNodeProjection]

    init(step: HeistExecutionStepResult, profile: ProjectionProfile) {
        self.step = step
        self.profile = profile
        children = step.children.map { HeistReportNodeProjection(step: $0, profile: profile) }
    }

    var path: String { step.path.description }
    var kind: HeistExecutionStepKind { step.kind }
    var capability: String? { step.reportCapabilityPath?.description }
    var invocationDisplayName: String? { step.reportInvocationDisplayName }
    var command: HeistActionCommandType? { step.reportCommand }
    var target: AccessibilityTarget? { step.reportTarget }
    var status: HeistExecutionStepStatus { step.status }
    var message: String? { step.reportMessage }
    var durationMs: Int { step.durationMs }
    var evidence: HeistReportEvidenceProjection? { HeistReportEvidenceProjection(step: step, profile: profile) }
    var warning: HeistExecutionWarning? { step.reportWarning }
    var failureMessage: String? { step.reportFailureMessage }
    var failure: HeistReportFailureProjection? {
        step.failure.map {
            HeistReportFailureProjection(
                detail: $0,
                message: step.reportFailureMessage ?? $0.observed,
                actionErrorKind: step.reportActionErrorKind
            )
        }
    }
    var failureCategory: HeistFailureCategory? { step.failure?.category }
    var abortedAtChildPath: String? { step.abortedAtChildPath?.description }
    var expectation: ExpectationProjection? { step.reportExpectation.map { ExpectationProjection(result: $0) } }
    var actionErrorKind: ErrorKind? { step.reportActionErrorKind }
    var activationTrace: ActivationTrace? { step.reportActionResult?.activationTrace }
    var traceDelta: DeltaProjection? {
        evidence?.traceDelta
    }
}

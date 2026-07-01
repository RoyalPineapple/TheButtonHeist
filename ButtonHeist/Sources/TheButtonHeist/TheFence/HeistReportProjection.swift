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
    let executedTopLevelStepCount: Int
    let executedNodeCount: Int
    let outputReceiptNodeCount: Int
    let abortedAtPath: String?
    let durationMs: Int
    let expectations: HeistExpectationsProjection?
    let finalScreenId: String?

    init(summary: HeistExecutionReportSummaryFacts) {
        executedTopLevelStepCount = summary.executedTopLevelStepCount
        executedNodeCount = summary.executedNodeCount
        outputReceiptNodeCount = summary.outputReceiptNodeCount
        abortedAtPath = summary.abortedAtPath
        durationMs = summary.durationMs
        expectations = summary.expectationsChecked > 0
            ? HeistExpectationsProjection(checked: summary.expectationsChecked, met: summary.expectationsMet)
            : nil
        finalScreenId = summary.finalScreenId
    }
}

struct HeistExpectationsProjection: Sendable {
    let checked: Int
    let met: Int
    let allMet: Bool

    init(checked: Int, met: Int) {
        self.checked = checked
        self.met = met
        allMet = checked == met
    }
}

struct HeistReportProjection: Sendable {
    let status: PublicResponseStatus
    let summary: HeistReportSummaryProjection
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
        self.init(
            result: result,
            netDelta: accessibilityTrace?.meaningfulEndpointDelta,
            profile: profile.heistReport
        )
    }

    init(
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?,
        profile: ProjectionProfile
    ) {
        let rollup = result.evidenceRollup
        let reportSummary = HeistExecutionReportSummaryFacts(summary: rollup.summary)
        status = reportSummary.abortedAtPath == nil ? .ok : .partial
        nodes = rollup.rootNodes.map { HeistReportNodeProjection(node: $0, profile: profile) }
        outputNodes = rollup.outputNodes.map { HeistReportNodeProjection(node: $0, profile: profile) }
        summary = HeistReportSummaryProjection(summary: reportSummary)
        failedStepPath = reportSummary.abortedAtPath
        failureScreenshotSummary = result.failureScreenshotSummary
        failureInterfaceDump = result.failureInterfaceDump(
            elementLimit: profile.limits.failureInterfaceElements
        )
        self.netDelta = netDelta.map { DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true) }
    }
}

private extension ProjectionProfile {
    var heistReport: ProjectionProfile {
        kind == .summary ? .mcp : self
    }
}

struct HeistReportNodeProjection: Sendable {
    let path: String
    let kind: String
    let capability: String?
    let displayName: String
    let commandName: String?
    let target: ElementTarget?
    let status: HeistExecutionStepStatus
    let message: String?
    let durationMs: Int
    let intent: HeistStepIntent?
    let evidence: HeistReportEvidenceProjection?
    let failure: HeistReportFailureProjection?
    let failureMessage: String?
    let failureCategory: HeistFailureCategory?
    let abortedAtChildPath: String?
    let expectation: ExpectationProjection?
    let actionErrorKind: ErrorKind?
    let traceDelta: DeltaProjection?
    let children: [HeistReportNodeProjection]

    init(node: HeistExecutionEvidenceNode, profile: ProjectionProfile) {
        let step = node.step
        let report = node.reportFacts
        path = report.path
        kind = report.kind
        capability = report.capabilityName
        displayName = report.displayName
        commandName = report.commandName
        target = report.target
        status = report.status
        message = report.message
        durationMs = step.durationMs
        intent = step.intent
        evidence = HeistReportEvidenceProjection(node: node, profile: profile)
        failureMessage = report.failureMessage
        failure = step.failure.map {
            HeistReportFailureProjection(
                detail: $0,
                message: report.failureMessage ?? $0.observed,
                actionErrorKind: report.actionErrorKind
            )
        }
        failureCategory = report.failureCategory
        abortedAtChildPath = step.abortedAtChildPath
        expectation = report.expectation.map { ExpectationProjection(result: $0) }
        actionErrorKind = report.actionErrorKind
        traceDelta = report.traceEvidenceResult?.accessibilityTrace?.endpointDelta.map {
            DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true)
        }
        children = node.children.map { HeistReportNodeProjection(node: $0, profile: profile) }
    }
}

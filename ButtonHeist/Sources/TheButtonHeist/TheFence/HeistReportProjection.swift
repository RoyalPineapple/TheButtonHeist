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
    let expectationsChecked: Int
    let expectationsMet: Int

    var expectations: HeistExpectationsProjection? {
        expectationsChecked > 0
            ? HeistExpectationsProjection(checked: expectationsChecked, met: expectationsMet)
            : nil
    }

    init(result: HeistExecutionResult, outputReceiptNodeCount: Int) {
        executedTopLevelStepCount = result.executedTopLevelStepCount
        executedNodeCount = result.executedNodeCount
        self.outputReceiptNodeCount = outputReceiptNodeCount
        abortedAtPath = result.abortedAtPath
        durationMs = result.durationMs
        expectationsChecked = result.expectationsChecked
        expectationsMet = result.expectationsMet
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
    let finalScreenId: String?

    init(
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?,
        profile: ProjectionProfile
    ) {
        status = result.abortedAtPath == nil ? .ok : .partial
        nodes = result.steps.map { HeistReportNodeProjection(step: $0, profile: profile) }
        outputNodes = nodes.flatMap(\.flattened)
        summary = HeistReportSummaryProjection(result: result, outputReceiptNodeCount: outputNodes.count)
        failedStepPath = result.failedStepPath
        failureScreenshotSummary = result.failureScreenshotSummary
        failureInterfaceDump = result.failureInterfaceDump(
            elementLimit: profile.limits.failureInterfaceElements
        )
        self.netDelta = netDelta.map { DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true) }
        finalScreenId = result.traceResultsInExecutionOrder
            .compactMap { $0.accessibilityTrace?.endpointScreenId }
            .last
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

    init(step: HeistExecutionStepResult, profile: ProjectionProfile) {
        let reportedFailureMessage = step.reportFailureMessage
        let reportedActionErrorKind = step.reportActionResult?.success == false ? step.reportActionResult?.errorKind : nil

        path = step.path
        kind = step.reportStepName
        capability = step.invocationEvidence?.invocation?.capabilityName
        displayName = step.reportDisplayName
        commandName = step.reportCommandName
        target = step.reportTarget
        status = step.status
        message = step.reportMessage
        durationMs = step.durationMs
        intent = step.intent
        evidence = HeistReportEvidenceProjection(step: step, profile: profile)
        failureMessage = reportedFailureMessage
        failure = step.failure.map {
            HeistReportFailureProjection(
                detail: $0,
                message: reportedFailureMessage ?? $0.observed,
                actionErrorKind: reportedActionErrorKind
            )
        }
        failureCategory = step.failure?.category
        abortedAtChildPath = step.abortedAtChildPath
        expectation = step.reportExpectation.map { ExpectationProjection(result: $0) }
        actionErrorKind = reportedActionErrorKind
        traceDelta = step.traceEvidenceResult?.accessibilityTrace?.endpointDelta.map {
            DeltaProjection(delta: $0, profile: profile, includeScreenInterface: true)
        }
        children = step.children.map { HeistReportNodeProjection(step: $0, profile: profile) }
    }

    var flattened: [HeistReportNodeProjection] {
        [self] + children.flatMap(\.flattened)
    }
}

import TheScore

// JUnit is an external linear projection of the canonical semantic report.
// Its XML entries are output-only and never drive runtime failure logic.

extension TheFence {

    // MARK: - JUnit Report

    /// Project a finished heist report into the JUnit format consumed by
    /// `run_heist --junit`.
    public func junitReport(
        for report: HeistReport,
        heistName: String
    ) -> HeistJUnitReport {
        return HeistJUnitReport(
            heistName: heistName,
            app: handoff.connectionLifecycle.serverInfo?.bundleIdentifier.description ?? "unknown",
            totalTimeSeconds: Double(report.summary.durationMs) / 1000,
            steps: junitSteps(report: report)
        )
    }

    // MARK: - JUnit Steps

    private func junitSteps(report: HeistReport) -> [HeistJUnitReport.StepResult] {
        report.outputNodes.enumerated().map { index, step in
            HeistJUnitReport.StepResult(
                index: index,
                command: step.command?.rawValue ?? step.kind.rawValue,
                target: step.target,
                timeSeconds: Double(step.durationMs) / 1000,
                outcome: Self.junitOutcome(for: step, report: report)
            )
        }
    }

    // MARK: - Private Helpers

    private static func junitOutcome(
        for step: HeistReport.Node,
        report: HeistReport
    ) -> HeistJUnitReport.Outcome {
        if step.status == .failed {
            let message = step.failure?.diagnosticMessage ?? step.message ?? "heist failed"
            let failure = step.failure.map(diagnosticFailure)
            let enriched = step.path == report.summary.abortedAtPath
                ? junitFailureMessage(message, report: report, failure: failure)
                : junitFailureMessage(message, failure: failure)
            return .failed(message: enriched, failureKind: junitFailureKind(for: step))
        }
        if step.status == .skipped {
            return .skipped
        }
        return .passed
    }

    private static func junitFailureMessage(
        _ message: String,
        report: HeistReport? = nil,
        failure: DiagnosticFailure?
    ) -> String {
        var lines = [message]
        if let failure {
            lines.append("code: \(failure.code)")
            lines.append("kind: \(failure.kind.rawValue)")
            lines.append("phase: \(failure.phase.rawValue)")
            lines.append("retryable: \(failure.retryable)")
        }
        if let screenshot = report?.diagnostics.failureScreenshotSummary {
            lines.append(screenshot)
        }
        if let interfaceDump = report?.diagnostics.failureInterfaceDump(
            elementLimit: ProjectionProfile.junit.limits.failureInterfaceElements
        ) {
            lines.append(interfaceDump)
        }
        return lines.joined(separator: "\n")
    }

    private static func diagnosticFailure(_ failure: HeistReport.Failure) -> DiagnosticFailure {
        failure.actionKind.map {
            DiagnosticFailure(failureKind: $0, message: failure.diagnosticMessage)
        } ?? DiagnosticFailure(
            reportFailure: failure.detail,
            message: failure.diagnosticMessage
        )
    }

    private static func junitFailureKind(for step: HeistReport.Node) -> HeistJUnitReport.ReportErrorKind? {
        if let failureKind = step.failure?.actionKind {
            return .action(failureKind)
        }
        switch step.failure?.detail.category {
        case .internalInvariant,
             .validation,
             .runtimeUnavailable,
             .targetResolution,
             .invocation,
             .loop,
             .explicitFailure:
            return .commandError
        case .action, .expectation, .wait, .none:
            return nil
        }
    }
}

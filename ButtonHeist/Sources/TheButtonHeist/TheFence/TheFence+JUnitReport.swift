import TheScore

// The JUnit report is an external linear format derived from the heist execution
// tree. The execution tree stays the product model; these XML entries are
// output-only and never drive runtime failure logic.

extension TheFence {

    // MARK: - JUnit Report

    /// Build the external JUnit report for a finished run_heist execution. The
    /// execution tree stays the product model; this report is an output-only
    /// projection consumed by `run_heist --junit`.
    public func junitReport(
        for result: HeistExecutionResult,
        heistName: String,
        totalTimeSeconds: Double
    ) -> HeistJUnitReport {
        let projection = HeistReportProjection(result: result, accessibilityTrace: nil, profile: .junit)
        let steps = junitSteps(projection: projection)
        return HeistJUnitReport(
            heistName: heistName,
            app: handoff.serverInfo?.bundleIdentifier ?? "unknown",
            receiptNodeCount: steps.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: steps
        )
    }

    // MARK: - JUnit Steps

    /// Output-only step entries for the JUnit report, walked from the execution
    /// receipt tree in execution order.
    func junitSteps(result: HeistExecutionResult) -> [HeistJUnitReport.StepResult] {
        junitSteps(projection: HeistReportProjection(result: result, accessibilityTrace: nil, profile: .junit))
    }

    func junitSteps(projection: HeistReportProjection) -> [HeistJUnitReport.StepResult] {
        projection.outputNodes.enumerated().map { index, step in
            HeistJUnitReport.StepResult(
                index: index,
                command: step.command?.rawValue ?? step.kind.rawValue,
                target: step.target,
                timeSeconds: Double(step.durationMs) / 1000,
                outcome: Self.junitOutcome(for: step, projection: projection)
            )
        }
    }

    // MARK: - Private Helpers

    private static func junitOutcome(
        for step: HeistReportNodeProjection,
        projection: HeistReportProjection
    ) -> HeistJUnitReport.Outcome {
        if step.status == .failed {
            let message = step.failureMessage ?? step.failure?.detail.observed ?? step.message ?? "heist failed"
            let failure = step.failure?.diagnosticFailure
            let enriched = step.path == projection.failedStepPath
                ? junitFailureMessage(message, projection: projection, failure: failure)
                : junitFailureMessage(message, failure: failure)
            return .failed(message: enriched, errorKind: junitErrorKind(for: step))
        }
        if step.status == .skipped {
            return .skipped
        }
        return .passed
    }

    private static func junitFailureMessage(
        _ message: String,
        projection: HeistReportProjection? = nil,
        failure: DiagnosticFailure?
    ) -> String {
        var lines = [message]
        if let failure {
            lines.append("code: \(failure.code)")
            lines.append("kind: \(failure.kind.rawValue)")
            lines.append("phase: \(failure.phase.rawValue)")
            lines.append("retryable: \(failure.retryable)")
        }
        if let screenshot = projection?.failureScreenshotSummary {
            lines.append(screenshot)
        }
        if let interfaceDump = projection?.failureInterfaceDump {
            lines.append(interfaceDump)
        }
        return lines.joined(separator: "\n")
    }

    private static func junitErrorKind(for step: HeistReportNodeProjection) -> HeistJUnitReport.ReportErrorKind? {
        if let errorKind = step.actionErrorKind {
            return .action(errorKind)
        }
        switch step.failureCategory {
        case .validation, .runtimeUnavailable, .targetResolution, .invocation, .loop, .explicitFailure:
            return .commandError
        case .action, .expectation, .wait, .none:
            return nil
        }
    }
}

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
        let steps = junitSteps(result: result)
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
        result.outputReceiptNodes.enumerated().map { index, step in
            HeistJUnitReport.StepResult(
                index: index,
                command: step.reportCommandName ?? step.reportStepName,
                target: step.reportTarget,
                timeSeconds: Double(step.durationMs) / 1000,
                outcome: Self.junitOutcome(for: step, result: result)
            )
        }
    }

    // MARK: - Private Helpers

    private static func junitOutcome(
        for step: HeistExecutionStepResult,
        result: HeistExecutionResult
    ) -> HeistJUnitReport.Outcome {
        if let message = step.reportFailureMessage {
            let enriched = step.path == result.failedStepPath
                ? junitFailureMessage(message, result: result)
                : message
            return .failed(message: enriched, errorKind: junitErrorKind(for: step))
        }
        return step.status == .skipped ? .skipped : .passed
    }

    private static func junitFailureMessage(
        _ message: String,
        result: HeistExecutionResult
    ) -> String {
        var lines = [message]
        if let screenshot = result.failureScreenshotSummary {
            lines.append(screenshot)
        }
        if let interfaceDump = result.failureInterfaceDump() {
            lines.append(interfaceDump)
        }
        return lines.joined(separator: "\n")
    }

    private static func junitErrorKind(for step: HeistExecutionStepResult) -> HeistJUnitReport.ReportErrorKind? {
        if let result = step.reportActionResult, !result.success {
            return result.errorKind.map(HeistJUnitReport.ReportErrorKind.action)
        }
        switch step.failure?.category {
        case .validation, .runtimeUnavailable, .targetResolution, .invocation, .loop, .explicitFailure:
            return .commandError
        case .action, .expectation, .wait, .none:
            return nil
        }
    }
}

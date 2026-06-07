import TheScore

// The JUnit report is an external linear format derived from the heist execution
// tree. The execution tree stays the product model; these rows are output-only
// and never drive runtime failure logic.

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
        let stepRows = reportStepRows(result: result)
        return HeistJUnitReport(
            heistName: heistName,
            app: handoff.serverInfo?.bundleIdentifier ?? "unknown",
            reportRowCount: stepRows.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: stepRows
        )
    }

    // MARK: - Report Rows

    /// Output-only step rows for the JUnit report, flattened from the execution
    /// tree in execution order.
    func reportStepRows(result: HeistExecutionResult) -> [HeistJUnitReport.StepResult] {
        reportOutcomes(result: result).map(\.row)
    }

    // MARK: - Private Helpers

    private func reportOutcomes(
        result: HeistExecutionResult
    ) -> [(row: HeistJUnitReport.StepResult, failure: ReportFailure?)] {
        result.reportRows.enumerated().map { index, step in
            let failure = reportFailure(for: step)
            let outcome: HeistJUnitReport.Outcome = failure.map {
                .failed(message: $0.errorMessage, errorKind: Self.reportErrorKind($0))
            } ?? .passed
            let row = HeistJUnitReport.StepResult(
                index: index,
                command: step.reportCommandName ?? step.reportStepName,
                target: step.reportTarget,
                timeSeconds: Double(step.durationMs) / 1000,
                outcome: outcome
            )
            return (row, failure)
        }
    }

    private func reportFailure(for step: HeistExecutionStepResult) -> ReportFailure? {
        let failedStep: ReportFailure.FailedStep
        if let command = step.reportClientWireType.flatMap(TheFence.Command.init(clientWireType:)) {
            failedStep = ReportFailure.FailedStep(command: command, target: step.reportTarget)
        } else {
            failedStep = ReportFailure.FailedStep(
                commandName: step.reportCommandName ?? step.reportStepName,
                target: step.reportTarget
            )
        }

        let expectationFailed = step.reportExpectation.map { !$0.met } ?? false
        if let result = step.reportActionResult, !result.success || expectationFailed {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: expectationFailed ? step.reportExpectation : nil,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }

        guard let failureMessage = step.reportFailureMessage else { return nil }
        return .fenceError(
            step: failedStep,
            message: failureMessage,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }

    private static func reportErrorKind(_ failure: ReportFailure) -> HeistJUnitReport.ReportErrorKind? {
        switch failure {
        case .fenceError:
            return .commandError
        case .actionFailed(_, let result, _, _, _):
            guard let errorKind = result.errorKind else { return nil }
            return .action(errorKind)
        case .thrown:
            return .thrown
        }
    }
}

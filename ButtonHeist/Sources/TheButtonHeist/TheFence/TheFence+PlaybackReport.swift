import TheScore

// Playback reports are an external linear (JUnit/legacy) format derived from the
// heist execution tree. The execution tree stays the product model; these rows
// are output-only and never drive runtime failure logic.

extension TheFence {

    // MARK: - Playback Report

    /// Build the external JUnit/legacy playback report for a finished run_heist
    /// execution. The execution tree stays the product model; this report is an
    /// output-only projection consumed by `run_heist --junit`.
    public func playbackReport(
        for result: HeistExecutionResult,
        heistName: String,
        totalTimeSeconds: Double
    ) -> HeistPlaybackReport {
        let stepRows = playbackStepRows(result: result)
        return HeistPlaybackReport(
            heistName: heistName,
            app: handoff.serverInfo?.bundleIdentifier ?? "unknown",
            totalStepCount: stepRows.count,
            totalTimeSeconds: totalTimeSeconds,
            steps: stepRows
        )
    }

    // MARK: - Playback Report Rows

    /// Output-only step rows for the JUnit/legacy playback report, flattened
    /// from the execution tree in execution order.
    func playbackStepRows(result: HeistExecutionResult) -> [HeistPlaybackReport.StepResult] {
        playbackOutcomes(result: result).map(\.row)
    }

    // MARK: - Private Helpers

    private func playbackOutcomes(
        result: HeistExecutionResult
    ) -> [(row: HeistPlaybackReport.StepResult, failure: PlaybackFailure?)] {
        result.reportRows.enumerated().map { index, step in
            let failure = playbackFailure(for: step)
            let outcome: HeistPlaybackReport.Outcome = failure.map {
                .failed(message: $0.errorMessage, errorKind: Self.playbackErrorKind($0))
            } ?? .passed
            let row = HeistPlaybackReport.StepResult(
                index: index,
                command: step.reportCommandName ?? step.reportStepName,
                target: step.reportTarget,
                timeSeconds: Double(step.durationMs) / 1000,
                outcome: outcome
            )
            return (row, failure)
        }
    }

    private func playbackFailure(for step: HeistExecutionStepResult) -> PlaybackFailure? {
        let failedStep: PlaybackFailure.FailedStep
        if let command = step.reportClientWireType.flatMap(TheFence.Command.init(clientWireType:)) {
            failedStep = PlaybackFailure.FailedStep(command: command, target: step.reportTarget)
        } else {
            failedStep = PlaybackFailure.FailedStep(
                commandName: step.reportCommandName ?? step.reportStepName,
                target: step.reportTarget
            )
        }

        let expectationFailed = step.reportExpectation.map { !$0.met } ?? false
        if let result = step.reportActionResult, !result.success || expectationFailed {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: expectationFailed ? step.expectation : nil,
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

    private static func playbackErrorKind(_ failure: PlaybackFailure) -> HeistPlaybackReport.PlaybackErrorKind? {
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

import TheScore

extension TheFence {
    struct PlaybackProjection {
        let stepResults: [HeistPlaybackReport.StepResult]
        let failure: PlaybackFailure?
        let failedIndex: Int?
    }

    func playbackProjection(
        contract: HeistPlaybackContract,
        result: HeistExecutionResult
    ) -> PlaybackProjection {
        PlaybackReportProjection(contract: contract, result: result).project()
    }
}

private struct PlaybackReportProjection {
    let contract: TheFence.HeistPlaybackContract
    let result: HeistExecutionResult

    func project() -> TheFence.PlaybackProjection {
        let projections = result.projectedOutcomes(for: contract.plan)
        var failures: [PlaybackFailure] = []
        let stepResults = projections.enumerated().map { reportIndex, projection in
            let failure = playbackFailure(projection)
            if let failure {
                failures.append(failure)
            }
            return stepResult(
                reportIndex: reportIndex,
                projection: projection,
                failure: failure
            )
        }
        return TheFence.PlaybackProjection(
            stepResults: stepResults,
            failure: failures.first,
            failedIndex: stepResults.first { !$0.passed }?.index
        )
    }

    private func stepResult(
        reportIndex: Int,
        projection: ProjectedHeistStepOutcome,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let reportOutcome: HeistPlaybackReport.Outcome
        if let failure {
            reportOutcome = .failed(
                message: failure.errorMessage,
                errorKind: failureErrorKind(failure)
            )
        } else {
            reportOutcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: reportIndex,
            command: projection.commandName,
            target: projection.target,
            timeSeconds: Double(projection.outcome.durationMs) / 1000,
            outcome: reportOutcome
        )
    }

    private func failureErrorKind(_ failure: PlaybackFailure) -> HeistPlaybackReport.PlaybackErrorKind? {
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

    private func playbackFailure(_ projection: ProjectedHeistStepOutcome) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: projection.fenceCommand ?? .runHeist, target: projection.target)
        if let result = projection.outcome.finalActionResult(),
           result.success == false || projection.outcome.expectationActionResult?.success == false || projection.outcome.expectation?.met == false {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: projection.outcome.expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let response = projection.response,
              case .error(let message, _) = response
        else { return nil }
        return .fenceError(
            step: failedStep,
            message: message,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }
}

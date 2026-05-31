import TheScore

extension TheFence {
    struct PlaybackProjection {
        let stepResults: [HeistPlaybackReport.StepResult]
        let failure: PlaybackFailure?
        let failedIndex: Int?
    }

    func playbackProjection(
        contract: HeistPlaybackContract,
        batchResponse: FenceResponse
    ) throws -> PlaybackProjection {
        guard case .batch(let commands, let steps, let result, _) = batchResponse else {
            throw FenceError.invalidRequest("Expected batch response while playing heist")
        }
        return PlaybackReportProjection(
            contract: contract,
            batch: PlaybackBatchResult(commands: commands, steps: steps, result: result)
        ).project()
    }
}

private struct PlaybackBatchResult {
    let commands: [TheFence.Command]
    let steps: [TheScore.BatchStep]
    let result: BatchExecutionResult
}

private struct PlaybackReportProjection {
    let contract: TheFence.HeistPlaybackContract
    let batch: PlaybackBatchResult

    func project() -> TheFence.PlaybackProjection {
        let stepResults = contract.steps.map(stepResult)
        return TheFence.PlaybackProjection(
            stepResults: stepResults,
            failure: firstFailure(),
            failedIndex: stepResults.first { !$0.passed }?.index
        )
    }

    private func stepResult(_ step: TheFence.HeistPlaybackStepContract) -> HeistPlaybackReport.StepResult {
        let batchOutcome = batch.result.steps.first { $0.index == step.index }
        let failure = batchOutcome.flatMap {
            playbackFailure(
                step: step,
                outcome: $0,
                command: batch.commands[safe: $0.index],
                typedStep: batch.steps[safe: $0.index]
            )
        }

        let reportOutcome: HeistPlaybackReport.Outcome
        if let failure {
            reportOutcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == step.command ? failureErrorKind(failure) : nil
            )
        } else {
            reportOutcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: step.index,
            command: step.command.rawValue,
            target: step.reportTarget,
            timeSeconds: Double(batchOutcome?.durationMs ?? 0) / 1000,
            outcome: reportOutcome
        )
    }

    private func firstFailure() -> PlaybackFailure? {
        for step in contract.steps {
            guard let outcome = batch.result.steps.first(where: { $0.index == step.index }),
                  let failure = playbackFailure(
                    step: step,
                    outcome: outcome,
                    command: batch.commands[safe: outcome.index],
                    typedStep: batch.steps[safe: outcome.index]
                  )
            else { continue }
            return failure
        }
        return nil
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

    private func playbackFailure(
        step: TheFence.HeistPlaybackStepContract,
        outcome: BatchExecutionStepResult,
        command: TheFence.Command?,
        typedStep: TheScore.BatchStep?
    ) -> PlaybackFailure? {
        if let skipped = outcome.skipped {
            return .fenceError(
                step: PlaybackFailure.FailedStep(command: step.command, target: step.reportTarget),
                message: skipped.reason,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let command, let typedStep,
              let response = outcome.actionResponse(command: command, step: typedStep)
        else { return nil }
        return playbackFailure(step: step, response: response)
    }

    private func playbackFailure(step: TheFence.HeistPlaybackStepContract, response: FenceResponse) -> PlaybackFailure? {
        let failedStep = PlaybackFailure.FailedStep(command: step.command, target: step.reportTarget)
        switch response {
        case .error(let message, _):
            return .fenceError(
                step: failedStep,
                message: message,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        case .action(_, let result, let expectation) where !result.success || expectation?.met == false:
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        default:
            return nil
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

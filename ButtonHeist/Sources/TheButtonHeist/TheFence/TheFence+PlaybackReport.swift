import TheScore

extension TheFence {
    struct PlaybackBatchResult {
        let commands: [TheFence.Command]
        let steps: [TheScore.BatchStep]
        let result: BatchExecutionResult
    }

    func playbackBatchResult(_ response: FenceResponse) throws -> PlaybackBatchResult {
        guard case .batch(let commands, let steps, let result, _) = response else {
            throw FenceError.invalidRequest("Expected batch response while playing heist")
        }
        return PlaybackBatchResult(commands: commands, steps: steps, result: result)
    }

    func stepResults(
        contract: HeistPlaybackContract,
        batch: PlaybackBatchResult
    ) -> [HeistPlaybackReport.StepResult] {
        contract.steps.map { step in
            let outcome = batch.result.steps.first { $0.index == step.index }
            return stepResult(
                step: step,
                timeSeconds: Double(outcome?.durationMs ?? 0) / 1000,
                failure: outcome.flatMap {
                    playbackFailure(
                        step: step,
                        outcome: $0,
                        command: batch.commands[safe: $0.index],
                        typedStep: batch.steps[safe: $0.index]
                    )
                }
            )
        }
    }

    func playbackFailure(contract: HeistPlaybackContract, batch: PlaybackBatchResult) -> PlaybackFailure? {
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

    func firstPlaybackFailureIndex(
        contract: HeistPlaybackContract,
        batch: PlaybackBatchResult
    ) -> Int? {
        for step in contract.steps {
            guard let outcome = batch.result.steps.first(where: { $0.index == step.index }),
                  playbackFailure(
                    step: step,
                    outcome: outcome,
                    command: batch.commands[safe: outcome.index],
                    typedStep: batch.steps[safe: outcome.index]
                  ) != nil
            else { continue }
            return step.index
        }
        return nil
    }

    private func stepResult(
        step: HeistPlaybackStepContract,
        timeSeconds: Double,
        failure: PlaybackFailure?
    ) -> HeistPlaybackReport.StepResult {
        let outcome: HeistPlaybackReport.Outcome
        if let failure {
            outcome = .failed(
                message: failure.errorMessage,
                errorKind: failure.step.command == step.command ? failureErrorKind(failure) : nil
            )
        } else {
            outcome = .passed
        }
        return HeistPlaybackReport.StepResult(
            index: step.index,
            command: step.command.rawValue,
            target: step.reportTarget,
            timeSeconds: timeSeconds,
            outcome: outcome
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

    private func playbackFailure(
        step: HeistPlaybackStepContract,
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

    private func playbackFailure(step: HeistPlaybackStepContract, response: FenceResponse) -> PlaybackFailure? {
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

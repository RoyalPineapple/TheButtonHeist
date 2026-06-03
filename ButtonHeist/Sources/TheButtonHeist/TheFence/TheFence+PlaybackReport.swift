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
        let projection = HeistReportProjection(plan: contract.plan, result: result)
        var failures: [PlaybackFailure] = []
        let stepResults = projection.legacyFlatRows.map { row in
            let failure = row.playbackFailure
            if let failure {
                failures.append(failure)
            }
            return stepResult(
                row: row,
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
        row: HeistReportFlatRow,
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
            index: row.index,
            command: row.commandName,
            target: row.target,
            timeSeconds: Double(row.node.durationMs) / 1000,
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
}

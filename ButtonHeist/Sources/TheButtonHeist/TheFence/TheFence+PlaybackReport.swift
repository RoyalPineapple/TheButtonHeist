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
        let stepResults = HeistReportAdapterRow.rows(from: projection.nodes).map { row in
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
        row: HeistReportAdapterRow,
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

// Playback reports are an external linear format. Keep flattening private here;
// public report surfaces consume HeistReportProjection.nodes or compactLines.
private struct HeistReportAdapterRow {
    let index: Int
    let node: HeistReportNode

    var commandName: String {
        node.action?.commandName ?? node.kind.reportName
    }

    var fenceCommand: TheFence.Command? {
        node.action?.fenceCommand
    }

    var target: ElementTarget? {
        node.action?.target
    }

    var finalActionResult: ActionResult? {
        node.action?.finalActionResult
    }

    var failureMessage: String? {
        node.publicFailureMessage
    }

    static func rows(from nodes: [HeistReportNode]) -> [Self] {
        nodes.flatMap(Self.flatten(node:))
            .enumerated()
            .map { index, row in Self(index: index, node: row.node) }
    }

    private static func flatten(node: HeistReportNode) -> [Self] {
        let row = Self(index: 0, node: node)
        switch node.kind {
        case .forEachElement, .forEachString:
            return [row]
        case .action, .wait, .conditional, .waitForCases, .forEachIteration, .warn, .fail, .heist, .invoke:
            return [row] + node.children.flatMap(Self.flatten(node:))
        }
    }
}

private extension HeistReportAdapterRow {
    var playbackFailure: PlaybackFailure? {
        let failedStep: PlaybackFailure.FailedStep
        if let fenceCommand {
            failedStep = PlaybackFailure.FailedStep(command: fenceCommand, target: target)
        } else {
            failedStep = PlaybackFailure.FailedStep(commandName: commandName, target: target)
        }
        if let result = finalActionResult,
           result.success == false || node.expectationProjection?.status == .failed {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: node.expectationProjection?.status == .failed ? node.expectation : nil,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let failureMessage else { return nil }
        return .fenceError(
            step: failedStep,
            message: failureMessage,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }
}

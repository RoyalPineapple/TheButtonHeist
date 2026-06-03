import TheScore

// Legacy flat rows are derived from structured report nodes for old playback/report surfaces.
// New report surfaces should consume HeistReportProjection.nodes directly.
extension HeistReportProjection {
    var legacyFlatRows: [HeistReportFlatRow] {
        nodes.flatMap(\.legacyFlatRows)
            .enumerated()
            .map { index, row in row.indexed(index) }
    }

    var legacyPublicResponses: [FenceResponse] {
        legacyFlatRows.compactMap(\.response)
    }
}

struct HeistReportFlatRow {
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

    var response: FenceResponse? {
        if let action = node.action,
           let result = action.finalActionResult {
            return .action(command: action.fenceCommand, result: result, expectation: node.expectation)
        }
        if let failureMessage {
            return .error(failureMessage)
        }
        return nil
    }

    var failureMessage: String? {
        switch node.status {
        case .passed, .warned:
            return nil
        case .skipped, .failed:
            break
        }
        if let message = node.message {
            return message
        }
        if let result = finalActionResult, !result.success {
            return result.message ?? "action failed"
        }
        if node.expectation?.met == false {
            return node.expectation?.actual ?? "expectation not met"
        }
        if node.kind == .waitForCases,
           node.caseSelection?.timedOut == true,
           node.caseSelection?.elseRan != true {
            return "wait_for_cases timed out"
        }
        if let reason = node.forEachResult?.failureReason {
            return reason
        }
        return "heist step failed"
    }

    var playbackFailure: PlaybackFailure? {
        let failedStep: PlaybackFailure.FailedStep
        if let fenceCommand {
            failedStep = PlaybackFailure.FailedStep(command: fenceCommand, target: target)
        } else {
            failedStep = PlaybackFailure.FailedStep(commandName: commandName, target: target)
        }
        if let result = finalActionResult,
           result.success == false || node.expectation?.met == false {
            return .actionFailed(
                step: failedStep,
                result: result,
                expectation: node.expectation,
                interface: nil,
                diagnosticCaptureFailure: nil
            )
        }
        guard let response,
              case .error(let message, _) = response
        else { return nil }
        return .fenceError(
            step: failedStep,
            message: message,
            interface: nil,
            diagnosticCaptureFailure: nil
        )
    }

    func indexed(_ index: Int) -> Self {
        HeistReportFlatRow(index: index, node: node)
    }
}

extension HeistReportNode {
    var legacyFlatRows: [HeistReportFlatRow] {
        let row = HeistReportFlatRow(index: 0, node: self)
        switch kind {
        case .forEachElement, .forEachString:
            return [row]
        case .action, .wait, .conditional, .waitForCases, .forEachIteration, .warn, .fail, .heist, .invoke:
            return [row] + children.flatMap(\.legacyFlatRows)
        }
    }
}

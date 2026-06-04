import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(
        plan: HeistPlan,
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        let projection = HeistReportProjection(plan: plan, result: result)
        let checked = projection.summary.expectationsChecked
        let met = projection.summary.expectationsMet
        var text = "heist: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        let failedIndex = result.stoppedFailedIndex
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(Self.compactDeltaKind(netDelta))]" }
        if let lastScreenId = projection.finalActionResultsInExecutionOrder.compactMap({
            $0.accessibilityTrace?.endpointScreenIdProjection
        }).last {
            text = "\(lastScreenId) | \(text)"
        }
        for row in HeistReportAdapterRow.rows(from: projection.nodes) {
            var line = "  [\(row.index)] \(row.commandName)"
            if let actionResult = row.finalActionResult {
                if !actionResult.success, let error = actionResult.message {
                    line += " -> error: \(error)"
                } else if let delta = actionResult.accessibilityTrace?.endpointDeltaProjection {
                    let kind = Self.compactDeltaKind(delta)
                    line += " -> \(kind)"
                }
            } else if let failureMessage = row.failureMessage {
                line += " -> error: \(failureMessage)"
            }
            if let met = row.node.expectationMet {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

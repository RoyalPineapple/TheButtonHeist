import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(
        plan: HeistPlan,
        result: HeistExecutionResult,
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        let checked = result.projectedExpectationsChecked(for: plan)
        let met = result.projectedExpectationsMet(for: plan)
        var text = "heist: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        let failedIndex = result.stoppedFailedIndex
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(Self.compactDeltaKind(netDelta))]" }
        if let lastScreenId = result.flattenedOutcomes.compactMap({
            $0.finalActionResult()?.accessibilityTrace?.endpointScreenIdProjection
        }).last {
            text = "\(lastScreenId) | \(text)"
        }
        for (projectedIndex, projection) in result.projectedOutcomes(for: plan).enumerated() {
            var line = "  [\(projectedIndex)] \(projection.commandName)"
            if let actionResult = projection.outcome.finalActionResult() {
                if !actionResult.success, let error = actionResult.message {
                    line += " -> error: \(error)"
                } else if let delta = actionResult.accessibilityTrace?.endpointDeltaProjection {
                    let kind = Self.compactDeltaKind(delta)
                    line += " -> \(kind)"
                }
            } else if let response = projection.response,
                      case .error(let message, let details) = response {
                if let details {
                    line += " -> error[\(details.errorCode) \(details.phase.rawValue)]: \(message)"
                } else {
                    line += " -> error: \(message)"
                }
            } else if let failureMessage = projection.failureMessage {
                line += " -> error: \(failureMessage)"
            }
            if let met = projection.outcome.expectationMet(for: projection.step) {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

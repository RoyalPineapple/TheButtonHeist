import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(_ result: HeistExecutionResult, netDelta: AccessibilityTrace.Delta?) -> String {
        var text = "heist: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        if let failedIndex = result.stoppedFailedIndex {
            text += " (failed at \(failedIndex))"
        }
        let checked = result.expectationsChecked
        if checked > 0 {
            text += " [expectations: \(result.expectationsMet)/\(checked)]"
        }
        if let netDelta {
            text += " [net: \(Self.compactDeltaKind(netDelta))]"
        }
        if let lastScreenId = Self.finalScreenId(result) {
            text = "\(lastScreenId) | \(text)"
        }
        for (index, step) in result.reportRows.enumerated() {
            var line = "  [\(index)] \(step.reportCommandName ?? step.reportStepName)"
            if let failureMessage = step.reportFailureMessage {
                line += " -> error: \(failureMessage)"
            } else if let delta = step.reportActionResult?.accessibilityTrace?.endpointDelta {
                line += " -> \(Self.compactDeltaKind(delta))"
            }
            if let expectation = step.reportExpectation {
                line += expectation.met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

    /// Screen id of the last action that ran, if recorded.
    private static func finalScreenId(_ result: HeistExecutionResult) -> String? {
        result.finalActionResultsInExecutionOrder
            .compactMap { $0.accessibilityTrace?.endpointScreenId }
            .last
    }

}

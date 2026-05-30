import Foundation

import TheScore

extension FenceResponse {

    func compactBatchFormatted(
        commands: [TheFence.Command],
        steps: [TheScore.BatchStep],
        result: BatchExecutionResult,
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        let checked = result.expectationsChecked(steps: steps)
        let met = result.expectationsMet(steps: steps)
        var text = "batch: \(result.completedStepCount) steps in \(result.totalTimingMs)ms"
        let failedIndex = result.stoppedFailedIndex
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(netDelta.kindRawValue)]" }
        if let lastScreenId = result.steps.compactMap({ $0.finalActionResult()?.accessibilityTrace?.endpointScreenIdProjection }).last {
            text = "\(lastScreenId) | \(text)"
        }
        for step in result.steps {
            let commandName = commands.indices.contains(step.index)
                ? commands[step.index].rawValue
                : "step \(step.index)"
            var line = "  [\(step.index)] \(commandName)"
            if let skipped = step.skipped {
                line += " → error: \(skipped.reason)"
            } else if let actionResult = step.finalActionResult() {
                if !actionResult.success, let error = actionResult.message {
                    line += " → error: \(error)"
                } else if let kind = actionResult.accessibilityTrace?.endpointDeltaProjection?.kindRawValue {
                    line += " → \(kind)"
                }
            } else if let typedStep = steps[safe: step.index],
                      let response = step.actionResponse(
                        command: commands[safe: step.index] ?? .runBatch,
                        step: typedStep
                      ),
                      case .error(let message, let details) = response {
                if let details {
                    line += " → error[\(details.errorCode) \(details.phase.rawValue)]: \(message)"
                } else {
                    line += " → error: \(message)"
                }
            }
            if let typedStep = steps[safe: step.index],
               let met = step.expectationMet(for: typedStep) {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

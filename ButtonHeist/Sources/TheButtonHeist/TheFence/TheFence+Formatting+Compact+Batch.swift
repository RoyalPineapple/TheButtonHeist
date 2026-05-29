import Foundation

import TheScore

extension FenceResponse {

    func compactBatchFormatted(
        completedSteps: Int, failedIndex: Int?, totalTimingMs: Int,
        checked: Int, met: Int, stepSummaries: [BatchStepSummary],
        netDelta: AccessibilityTrace.Delta?
    ) -> String {
        var text = "batch: \(completedSteps) steps in \(totalTimingMs)ms"
        if let failedIndex { text += " (failed at \(failedIndex))" }
        if checked > 0 { text += " [expectations: \(met)/\(checked)]" }
        if let netDelta { text += " [net: \(netDelta.kindRawValue)]" }
        if let lastScreenId = stepSummaries.last(where: { $0.screenId != nil })?.screenId {
            text = "\(lastScreenId) | \(text)"
        }
        for (index, step) in stepSummaries.enumerated() {
            var line = "  [\(index)] \(step.command.rawValue)"
            if let error = step.error {
                if let errorCode = step.errorCode {
                    let phase = step.phase.map { " \($0)" } ?? ""
                    line += " → error[\(errorCode)\(phase)]: \(error)"
                } else {
                    line += " → error: \(error)"
                }
                if let nextCommand = step.nextCommand {
                    line += " Next: \(nextCommand)"
                }
            } else if let kind = step.deltaKind {
                line += " → \(kind)"
            } else if let count = step.elementCount {
                line += " → \(count) elements"
            }
            if let met = step.expectationMet {
                line += met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(_ result: HeistExecutionResult, netDelta: AccessibilityTrace.Delta?) -> String {
        var text = "heist: \(result.executedTopLevelStepCount) top-level steps in \(result.durationMs)ms"
        if let abortedAtPath = result.abortedAtPath {
            text += " (stopped at \(abortedAtPath))"
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
        for (index, step) in result.outputReceiptNodes.enumerated() {
            var line = "  [\(index)] \(step.reportDisplayName)"
            var detailLines: [String] = []
            let delta = step.traceEvidenceResult?.accessibilityTrace?.endpointDelta
            if let failureMessage = step.reportFailureMessage {
                line += " -> error: \(failureMessage)"
                detailLines = Self.compactHeistFailureDeltaLines(delta, step: step)
            } else if step.status == .skipped {
                line += " -> skipped"
            } else if let delta {
                if let summary = Self.compactHeistDeltaSummary(delta, step: step) {
                    line += " -> \(summary)"
                }
            }
            if let expectation = step.reportExpectation {
                line += expectation.met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
            if !detailLines.isEmpty {
                text += "\n" + detailLines.joined(separator: "\n")
            }
        }
        return text
    }

    private static func compactHeistDeltaSummary(
        _ delta: AccessibilityTrace.Delta,
        step: HeistExecutionStepResult
    ) -> String? {
        let renderedDelta = Self.compactDelta(
            delta,
            method: step.reportCommandName ?? step.reportDisplayName
        )
        return renderedDelta
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init)
            .map { Self.compactHeistStepDeltaSummary($0, step: step) }
    }

    private static func compactHeistFailureDeltaLines(
        _ delta: AccessibilityTrace.Delta?,
        step: HeistExecutionStepResult
    ) -> [String] {
        guard let delta else { return [] }
        let renderedDelta = Self.compactDelta(
            delta,
            method: step.reportCommandName ?? step.reportDisplayName
        )
        var deltaLines = renderedDelta
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let summary = deltaLines.first else { return [] }
        deltaLines.removeFirst()
        return ["    evidence: \(Self.compactHeistStepDeltaSummary(summary, step: step))"]
            + deltaLines.map { "    \($0)" }
    }

    private static func compactHeistStepDeltaSummary(
        _ summary: String,
        step: HeistExecutionStepResult
    ) -> String {
        let method = step.reportCommandName ?? step.reportDisplayName
        let prefix = "\(method): "
        guard summary.hasPrefix(prefix) else { return summary }
        return String(summary.dropFirst(prefix.count))
    }

    /// Screen id of the last step that ran with trace evidence (action or wait).
    private static func finalScreenId(_ result: HeistExecutionResult) -> String? {
        result.traceResultsInExecutionOrder
            .compactMap { $0.accessibilityTrace?.endpointScreenId }
            .last
    }

}

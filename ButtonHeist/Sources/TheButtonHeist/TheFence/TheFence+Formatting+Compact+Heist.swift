import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(_ projection: HeistReportProjection) -> String {
        var text = "heist: \(projection.summary.executedTopLevelStepCount) top-level steps in \(projection.summary.durationMs)ms"
        if let abortedAtPath = projection.summary.abortedAtPath {
            text += " (stopped at \(abortedAtPath))"
        }
        if let expectations = projection.summary.expectations {
            text += " [expectations: \(expectations.met)/\(expectations.checked)]"
        }
        if let netDelta = projection.netDelta {
            text += " [net: \(netDelta.kind.rawValue)]"
        }
        if let lastScreenId = projection.summary.finalScreenId {
            text = "\(lastScreenId) | \(text)"
        }
        for (index, step) in projection.outputNodes.enumerated() {
            var line = "  [\(index)] \(Self.compactHeistStepName(step))"
            var detailLines: [String] = []
            let delta = step.traceDelta
            if let failureMessage = step.failureMessage {
                line += " -> error: \(failureMessage)"
                detailLines = Self.compactHeistFailureDeltaLines(delta, step: step)
                if let activationTrace = step.failure?.detail.activationTrace {
                    detailLines.append("    activation: \(Self.compactActivationTrace(activationTrace))")
                }
            } else if step.status == .skipped {
                line += " -> skipped"
            } else if let warning = step.evidence?.warning {
                line += " -> warning: \(warning.message)"
            } else if let delta {
                if let summary = Self.compactHeistDeltaSummary(delta, step: step) {
                    line += " -> \(summary)"
                }
            }
            if let expectation = step.expectation {
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
        _ delta: DeltaProjection,
        step: HeistReportNodeProjection
    ) -> String? {
        let renderedDelta = Self.compactDelta(
            delta,
            method: Self.compactHeistStepName(step)
        )
        return renderedDelta
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init)
            .map { Self.compactHeistStepDeltaSummary($0, step: step) }
    }

    private static func compactHeistFailureDeltaLines(
        _ delta: DeltaProjection?,
        step: HeistReportNodeProjection
    ) -> [String] {
        guard let delta else { return [] }
        let renderedDelta = Self.compactDelta(
            delta,
            method: Self.compactHeistStepName(step)
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
        step: HeistReportNodeProjection
    ) -> String {
        let method = Self.compactHeistStepName(step)
        let prefix = "\(method): "
        guard summary.hasPrefix(prefix) else { return summary }
        return String(summary.dropFirst(prefix.count))
    }

    private static func compactHeistStepName(_ step: HeistReportNodeProjection) -> String {
        step.invocationDisplayName ?? step.command?.rawValue ?? step.kind.rawValue
    }

}

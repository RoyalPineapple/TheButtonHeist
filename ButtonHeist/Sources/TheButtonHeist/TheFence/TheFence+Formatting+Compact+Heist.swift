import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(
        _ report: HeistReport,
        profile: ProjectionProfile
    ) -> String {
        let profile = profile.heistReport
        var text = "heist: \(report.summary.executedTopLevelStepCount) top-level steps in \(report.summary.durationMs)ms"
        if let abortedAtPath = report.summary.abortedAtPath {
            text += " (stopped at \(abortedAtPath))"
        }
        if let expectations = report.summary.expectations {
            text += " [expectations: \(expectations.met)/\(expectations.checked)]"
        }
        if case .changed(let trace) = report.accessibilityChange,
           let netDelta = DeltaProjection(
                trace: trace,
                isComplete: true,
                profile: profile,
                includeScreenInterface: true
           ) {
            text += " [net: \(netDelta.kind.rawValue)]"
        }
        if let lastScreenId = report.summary.finalScreenId {
            text = "\(lastScreenId) | \(text)"
        }
        for (index, step) in report.outputNodes.enumerated() {
            var line = "  [\(index)] \(Self.compactHeistStepName(step))"
            var detailLines: [String] = []
            let delta = step.evidence?.traceDelta(profile: profile)
            if let failureMessage = step.failure?.message {
                line += " -> error: \(failureMessage)"
                detailLines = Self.compactHeistFailureDeltaLines(delta, step: step)
                if let activationTrace = step.activationTrace {
                    detailLines.append("    activation: \(Self.compactActivationTrace(activationTrace))")
                }
            } else if step.status == .skipped {
                line += " -> skipped"
            } else if let warning = step.warning {
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
        step: HeistReport.Node
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
        step: HeistReport.Node
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
        step: HeistReport.Node
    ) -> String {
        let method = Self.compactHeistStepName(step)
        let prefix = "\(method): "
        guard summary.hasPrefix(prefix) else { return summary }
        return String(summary.dropFirst(prefix.count))
    }

    private static func compactHeistStepName(_ step: HeistReport.Node) -> String {
        step.invocationDisplayName ?? step.command?.rawValue ?? step.kind.rawValue
    }

}

private extension HeistReport.Evidence {
    func traceDelta(profile: ProjectionProfile) -> DeltaProjection? {
        let result: ActionResult?
        switch self {
        case .action(_, let evidence):
            result = evidence.reportedResult
        case .wait(let evidence):
            result = evidence.actionResult
        case .repeatUntil(_, let evidence):
            result = evidence.actionResult
        case .invocation(_, let evidence):
            result = evidence.expectationActionResult
        case .caseSelection, .forEachString, .forEachElement, .warning:
            result = nil
        }
        return result?.traceEvidence.flatMap {
            DeltaProjection(
                trace: $0.trace,
                isComplete: $0.isComplete,
                profile: profile,
                includeScreenInterface: true
            )
        }
    }
}

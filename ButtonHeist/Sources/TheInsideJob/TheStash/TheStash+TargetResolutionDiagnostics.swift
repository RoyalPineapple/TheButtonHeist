#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum TargetResolutionDiagnostics {
    static func message(for resolution: TheStash.TargetResolution) -> String {
        switch resolution {
        case .resolved:
            return ""
        case .notFound(let facts):
            return notFoundMessage(facts)
        case .ambiguous(let facts):
            return ambiguousMessage(facts)
        }
    }

    static func candidateSummary(_ candidate: TheStash.TargetCandidateFacts) -> String {
        var parts: [String] = []
        if let label = candidate.label, !label.isEmpty { parts.append("\"\(label)\"") }
        if let identifier = candidate.identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
        if let value = candidate.value, !value.isEmpty { parts.append("value=\(value)") }
        parts.append(availabilityDescription(candidate))
        return parts.joined(separator: " ")
    }

    private static func notFoundMessage(_ facts: TheStash.TargetNotFoundFacts) -> String {
        switch facts.reason {
        case .ordinalNegative(let ordinal):
            return """
                ordinal must be non-negative, got \(ordinal)
                Next: remove ordinal, or use ordinal 0 after the target query resolves candidates.
                """
        case .ordinalOutOfRange(let requested, let matchCount):
            let nextMove: String
            if matchCount == 0 {
                nextMove = "Next: retry with an exact label, identifier, or value."
            } else {
                nextMove = "Next: use ordinal 0...\(matchCount - 1), omit ordinal to inspect ambiguity, "
                    + "or target a listed element by exact label, identifier, or value."
            }
            return """
                ordinal \(requested) requested but only \(matchCount) match\(matchCount == 1 ? "" : "es") found
                \(nextMove)
                """
        case .noMatches:
            return TheStash.Diagnostics.matcherNotFound(
                facts.predicate,
                screenElements: facts.screenElements,
                visibleHeistIds: facts.visibleHeistIds,
                resolutionScope: facts.resolutionScope
            )
        }
    }

    private static func ambiguousMessage(_ facts: TheStash.TargetAmbiguityFacts) -> String {
        let countLabel = facts.matchedCount > 10 ? "10+" : "\(facts.matchedCount)"
        let rangeLabel = facts.matchedCount > 10 ? "0, 1, 2, ..." : "0–\(facts.matchedCount - 1)"
        let query = TheStash.Diagnostics.formatMatcher(facts.predicate)
        let candidates = facts.candidates.map(candidateSummary)
        var lines = [
            "\(countLabel) elements match: \(query) (scope: \(facts.resolutionScope.rawValue)) — use ordinal \(rangeLabel) to select one"
        ]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if facts.matchedCount > 10 {
            lines.append("  ... and more")
        }
        return lines.joined(separator: "\n")
    }

    private static func availabilityDescription(_ candidate: TheStash.TargetCandidateFacts) -> String {
        if candidate.isVisible {
            return "(visible)"
        }
        var details = ["offscreen"]
        if !candidate.isReachable {
            details.append("unreachable")
        }
        return "(\(details.joined(separator: ", ")))"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

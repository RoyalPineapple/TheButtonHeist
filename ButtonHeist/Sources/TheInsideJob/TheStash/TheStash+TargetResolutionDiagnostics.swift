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

    static func message(for resolution: TheStash.ContainerTargetResolution) -> String {
        switch resolution {
        case .resolved:
            return ""
        case .notFound(let facts):
            return containerNotFoundMessage(facts)
        case .ambiguous(let facts):
            return containerAmbiguousMessage(facts)
        }
    }

    static func elementCandidateDescription(_ candidate: TheStash.TargetCandidateFacts) -> String {
        ElementDiagnosticSummary(
            label: candidate.label,
            identifier: candidate.identifier,
            value: candidate.value,
            availability: availability(candidate)
        ).rendered(using: .targetCandidate)
    }

    static func containerCandidateDescription(_ candidate: InterfaceTree.Container) -> String {
        let facts = candidate.container.containerPredicateFacts
        let label: String?
        let value: String?
        if case .semanticGroup(let semanticLabel, let semanticValue) = facts.role {
            label = semanticLabel
            value = semanticValue
        } else {
            label = nil
            value = nil
        }
        return ElementDiagnosticSummary(
            label: label,
            identifier: facts.identifier,
            value: value
        ).rendered(using: .containerCandidate(
            type: facts.role.kind.rawValue,
            isModalBoundary: facts.isModalBoundary
        ))
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
                treeElements: facts.treeElements,
                visibleHeistIds: facts.visibleHeistIds,
                resolutionScope: facts.resolutionScope
            )
        }
    }

    private static func ambiguousMessage(_ facts: TheStash.TargetAmbiguityFacts) -> String {
        let countLabel = facts.matchedCount > 10 ? "10+" : "\(facts.matchedCount)"
        let rangeLabel = facts.matchedCount > 10 ? "0, 1, 2, ..." : "0–\(facts.matchedCount - 1)"
        let query = TheStash.Diagnostics.formatMatcher(facts.predicate)
        let candidates = facts.candidates.map(elementCandidateDescription)
        var lines = [
            "\(countLabel) elements match: \(query) (scope: \(facts.resolutionScope.rawValue)) — use ordinal \(rangeLabel) to select one"
        ]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if facts.matchedCount > 10 {
            lines.append("  ... and more")
        }
        return lines.joined(separator: "\n")
    }

    private static func availability(_ candidate: TheStash.TargetCandidateFacts) -> ElementDiagnosticSummary.Availability {
        if candidate.isVisible {
            return .visible
        }
        return .offscreen(isReachable: candidate.isReachable)
    }

    private static func containerNotFoundMessage(_ facts: TheStash.ContainerNotFoundFacts) -> String {
        switch facts.reason {
        case .emptyPredicate:
            return "container target needs semantic scope: use type, label, value, identifier, or target an element inside the intended region"
        case .ordinalOutOfRange(let requested, let matchCount):
            return "container target ordinal \(requested) is outside \(matchCount) matching container(s); "
                + "narrow the container predicate or target an element inside the intended region"
        case .noMatches:
            return "no semantic container matched \(facts.predicate); target an element inside the intended region or inspect the current interface"
        }
    }

    private static func containerAmbiguousMessage(_ facts: TheStash.ContainerAmbiguityFacts) -> String {
        let candidates = facts.candidates.map(containerCandidateDescription)
        return "container target is ambiguous across \(facts.matchedCount) containers; "
            + "narrow by semantic facts or target an element inside the intended region. Candidates: "
            + candidates.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum TargetResolutionDiagnostics {
    static func message(for resolution: TheVault.TargetResolution) -> String {
        switch resolution {
        case .resolved:
            return ""
        case .notFound(let facts):
            return notFoundMessage(facts)
        case .ambiguous(let facts):
            return ambiguousMessage(facts)
        }
    }

    static func elementCandidateDescription(
        _ candidate: InterfaceTree.Element,
        visibleHeistIds: Set<HeistId>
    ) -> String {
        ElementDiagnosticSummary(
            label: candidate.element.label,
            identifier: candidate.element.identifier,
            value: candidate.element.value,
            availability: availability(candidate, visibleHeistIds: visibleHeistIds)
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

    private static func notFoundMessage(_ facts: TheVault.TargetNotFoundFacts) -> String {
        switch facts.matchSet {
        case .elements(let matches):
            return elementNotFoundMessage(facts.reason, matches: matches, scope: facts.resolutionScope)
        case .containers(let matches):
            return containerNotFoundMessage(facts.reason, matches: matches)
        }
    }

    private static func elementNotFoundMessage(
        _ reason: TheVault.TargetNotFoundReason,
        matches: TheVault.TargetElementMatches,
        scope: TheVault.ResolutionScope
    ) -> String {
        switch reason {
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
            return TheVault.Diagnostics.matcherNotFound(
                matches.predicate,
                treeElements: matches.candidates,
                visibleHeistIds: matches.visibleHeistIds,
                resolutionScope: scope
            )
        }
    }

    private static func ambiguousMessage(_ facts: TheVault.TargetAmbiguityFacts) -> String {
        switch facts.matchSet {
        case .elements(let matches):
            return elementAmbiguousMessage(matches, scope: facts.resolutionScope)
        case .containers(let matches):
            return containerAmbiguousMessage(matches)
        }
    }

    private static func elementAmbiguousMessage(
        _ matches: TheVault.TargetElementMatches,
        scope: TheVault.ResolutionScope
    ) -> String {
        let matchedCount = matches.exactMatches.count
        let countLabel = matchedCount > 10 ? "10+" : "\(matchedCount)"
        let rangeLabel = matchedCount > 10 ? "0, 1, 2, ..." : "0–\(matchedCount - 1)"
        let query = TheVault.Diagnostics.formatMatcher(matches.predicate)
        let candidates = matches.exactMatches.prefix(10).map {
            elementCandidateDescription($0, visibleHeistIds: matches.visibleHeistIds)
        }
        var lines = [
            "\(countLabel) elements match: \(query) (scope: \(scope.rawValue)) — use ordinal \(rangeLabel) to select one"
        ]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if matchedCount > 10 {
            lines.append("  ... and more")
        }
        return lines.joined(separator: "\n")
    }

    private static func availability(
        _ candidate: InterfaceTree.Element,
        visibleHeistIds: Set<HeistId>
    ) -> ElementDiagnosticSummary.Availability {
        if visibleHeistIds.contains(candidate.heistId) {
            return .visible
        }
        return .offscreen(isReachable: candidate.scrollMembership != nil)
    }

    private static func containerNotFoundMessage(
        _ reason: TheVault.TargetNotFoundReason,
        matches: TheVault.TargetContainerMatches
    ) -> String {
        switch reason {
        case .ordinalOutOfRange(let requested, let matchCount):
            return "container target ordinal \(requested) is outside \(matchCount) matching container(s); "
                + "narrow the container predicate or target an element inside the intended region"
        case .noMatches:
            return "no semantic container matched \(matches.predicate); "
                + "target an element inside the intended region or inspect the current interface"
        }
    }

    private static func containerAmbiguousMessage(_ matches: TheVault.TargetContainerMatches) -> String {
        let candidates = matches.exactMatches.map(containerCandidateDescription)
        return "container target is ambiguous across \(matches.exactMatches.count) containers; "
            + "narrow by semantic facts or target an element inside the intended region. Candidates: "
            + candidates.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

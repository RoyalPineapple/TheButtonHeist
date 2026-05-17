#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Resolution Diagnostics
//
// Diagnostic messages for element resolution failures: near-miss suggestions,
// similar heistId hints, and compact element summaries for total misses.
// All methods take the data they need as parameters — no mutable state.

/// One relaxation candidate: the field that was dropped, the relaxed matcher,
/// and a closure that reads the actual value from a matched element so the
/// diagnostic can show what the original predicate diverged from.
private struct Relaxation {
    let field: String
    let relaxed: ElementMatcher
    let actual: (AccessibilityElement) -> String
}

extension TheStash {

    enum Diagnostics {

    /// Diagnostic for an heistId that isn't in the committed semantic screen.
    /// By the time we land here, `ensureOnScreen` has already tried to recover
    /// it, so the id is either stale (the hierarchy changed since the agent's
    /// last `get_interface`) or it never existed.
    static func heistIdNotFound(
        _ heistId: String,
        knownIds: some Collection<String>,
        knownCount: Int
    ) -> String {
        let similar = knownIds.sorted()
            .filter { $0.contains(heistId) || heistId.contains($0) }
        if similar.isEmpty {
            return """
                Element not found: "\(heistId)" — likely stale or the hierarchy \
                changed since your last get_interface (\(knownCount) known \
                elements now); refetch via get_interface, or target by \
                label/identifier with a matcher.
                """
        }
        return """
            Element not found: "\(heistId)" — did you mean: \
            \(similar.joined(separator: ", "))? If not, refetch via get_interface.
            """
    }

    static func matcherNotFound(
        _ matcher: ElementMatcher,
        screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<String>,
        resolutionScope: ResolutionScope
    ) -> String {
        let query = formatMatcher(matcher)
        let formattedQuery = query.isEmpty ? "<empty matcher>" : query

        // Tier 1: Near-miss — relax one predicate at a time to find what diverged.
        if let nearMiss = findNearMiss(for: matcher, in: screenElements, visibleHeistIds: visibleHeistIds) {
            return "No match for: \(formattedQuery) (scope: \(resolutionScope.rawValue))\n\(nearMiss)"
        }

        // Tier 2: Nothing close — dump a compact summary.
        let summary = compactElementSummary(
            screenElements: screenElements,
            visibleHeistIds: visibleHeistIds,
            resolutionScope: resolutionScope.rawValue
        )
        return "No match for: \(formattedQuery) (scope: \(resolutionScope.rawValue))\n\(summary)"
    }

    /// Format a matcher's predicates as a human-readable query string.
    static func formatMatcher(_ matcher: ElementMatcher) -> String {
        var fields: [String] = []
        if let label = matcher.label { fields.append("label=\"\(label)\"") }
        if let identifier = matcher.identifier { fields.append("identifier=\"\(identifier)\"") }
        if let value = matcher.value { fields.append("value=\"\(value)\"") }
        if let traits = matcher.traits { fields.append("traits=[\(traits.map(\.rawValue).joined(separator: ","))]") }
        if let excludeTraits = matcher.excludeTraits { fields.append("excludeTraits=[\(excludeTraits.map(\.rawValue).joined(separator: ","))]") }
        return fields.joined(separator: " ")
    }

    /// Try relaxing one predicate at a time. Value is relaxed first (most likely
    /// to drift — e.g. slider moved), then traits, label, identifier.
    /// Only considers relaxations that still have at least one remaining predicate —
    /// dropping the only predicate matches everything, which isn't a useful near-miss.
    /// Returns a diagnostic line listing up to three near-miss candidates (so an
    /// agent who typed a partial label sees the actual labels they could have
    /// meant), or nil if no near-miss was found.
    ///
    /// The relaxed predicate is matched with `.substring` semantics deliberately —
    /// the suggestion path is the only place where substring matching is allowed.
    /// Resolution itself is exact-or-miss.
    static func findNearMiss(
        for matcher: ElementMatcher,
        in screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<String>
    ) -> String? {
        let relaxations: [Relaxation] = [
            matcher.value.map { _ in
                Relaxation(
                    field: "value",
                    relaxed: ElementMatcher(
                        label: matcher.label, identifier: matcher.identifier,
                        traits: matcher.traits, excludeTraits: matcher.excludeTraits
                    ),
                    actual: { $0.value ?? "(nil)" }
                )
            },
            matcher.traits.map { _ in
                Relaxation(
                    field: "traits",
                    relaxed: ElementMatcher(
                        label: matcher.label, identifier: matcher.identifier,
                        value: matcher.value, excludeTraits: matcher.excludeTraits
                    ),
                    actual: { element in
                        UIAccessibilityTraits.knownTraits
                            .filter { element.traits.contains($0.trait) }
                            .map(\.name).joined(separator: ", ")
                    }
                )
            },
            matcher.label.map { _ in
                Relaxation(
                    field: "label",
                    relaxed: ElementMatcher(
                        identifier: matcher.identifier, value: matcher.value,
                        traits: matcher.traits, excludeTraits: matcher.excludeTraits
                    ),
                    actual: { $0.label ?? "(nil)" }
                )
            },
            matcher.identifier.map { _ in
                Relaxation(
                    field: "identifier",
                    relaxed: ElementMatcher(
                        label: matcher.label, value: matcher.value,
                        traits: matcher.traits, excludeTraits: matcher.excludeTraits
                    ),
                    actual: { $0.identifier ?? "(nil)" }
                )
            },
        ].compactMap { $0 }

        let suggestionCap = 3
        for relaxation in relaxations {
            guard relaxation.relaxed.hasPredicates else { continue }
            let hits = matchCandidates(relaxation.relaxed, in: screenElements, mode: .substring, limit: suggestionCap + 1)
            guard !hits.isEmpty else { continue }
            let deduped = dedupedPreservingOrder(hits.map {
                suggestionValue(
                    field: relaxation.field,
                    actual: relaxation.actual($0.element),
                    candidate: $0,
                    visibleHeistIds: visibleHeistIds
                )
            })
            let candidates = deduped.prefix(suggestionCap)
            let suggestion = candidates.joined(separator: ", ")
            let suffix = deduped.count > suggestionCap ? ", ..." : ""
            return "near miss: matched all fields except \(relaxation.field) — did you mean \(suggestion)\(suffix)?"
        }

        // Fallback: when the matcher only has one predicate (or every relaxation
        // empties out), retry the original matcher with substring semantics
        // against the single remaining field so the agent who typed a partial
        // still gets concrete suggestions. This is the only place where
        // substring search reaches user-visible output; resolution itself
        // remains strictly exact-or-miss.
        for relaxation in relaxations where !relaxation.relaxed.hasPredicates {
            let substringHits = matchCandidates(matcher, in: screenElements, mode: .substring, limit: suggestionCap + 1)
            guard !substringHits.isEmpty else { continue }
            let deduped = dedupedPreservingOrder(substringHits.map {
                suggestionValue(
                    field: relaxation.field,
                    actual: relaxation.actual($0.element),
                    candidate: $0,
                    visibleHeistIds: visibleHeistIds
                )
            })
            let candidates = deduped.prefix(suggestionCap)
            let suggestion = candidates.joined(separator: ", ")
            let suffix = deduped.count > suggestionCap ? ", ..." : ""
            return "near miss: \(relaxation.field) matched as substring only — did you mean \(suggestion)\(suffix)?"
        }
        return nil
    }

    /// Compact summary of known elements for total-miss fallback.
    /// Capped at 20 elements to avoid flooding the response.
    static func compactElementSummary(
        screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<String>,
        resolutionScope: String = "known"
    ) -> String {
        let cap = 20
        if screenElements.isEmpty {
            return """
                \(resolutionScope) hierarchy is empty (0 elements)
                Next: call get_interface(scope: "full") or wait for the target to appear, then retry with an exact label, identifier, heistId, or ordinal.
                """
        }
        let noun = screenElements.count == 1 ? "element" : "elements"
        var lines = ["\(screenElements.count) \(resolutionScope) \(noun):"]
        for entry in screenElements.prefix(cap) {
            let element = entry.element
            var parts: [String] = []
            if let label = element.label, !label.isEmpty { parts.append("label=\"\(label)\"") }
            if let identifier = element.identifier, !identifier.isEmpty { parts.append("id=\"\(identifier)\"") }
            if let value = element.value, !value.isEmpty { parts.append("value=\"\(value)\"") }
            let traitNames = UIAccessibilityTraits.knownTraits
                .filter { element.traits.contains($0.trait) }
                .map(\.name)
            if !traitNames.isEmpty { parts.append("[\(traitNames.joined(separator: ","))]") }
            parts.append(availabilityDescription(for: entry, visibleHeistIds: visibleHeistIds))
            lines.append("  \(parts.joined(separator: " "))")
        }
        if screenElements.count > cap {
            lines.append("  ... and \(screenElements.count - cap) more")
        }
        lines.append(
            "Next: target one listed element by exact label, identifier, heistId, or ordinal; "
                + "call get_interface(scope: \"full\") if the target may be offscreen."
        )
        return lines.joined(separator: "\n")
    }

    private static func matchCandidates(
        _ matcher: ElementMatcher,
        in screenElements: [Screen.ScreenElement],
        mode: MatchMode,
        limit: Int
    ) -> [Screen.ScreenElement] {
        guard limit > 0 else { return [] }
        var hits: [Screen.ScreenElement] = []
        hits.reserveCapacity(limit)
        for entry in screenElements where entry.element.matches(matcher, mode: mode) {
            hits.append(entry)
            if hits.count == limit { break }
        }
        return hits
    }

    private static func suggestionValue(
        field: String,
        actual: String,
        candidate: Screen.ScreenElement,
        visibleHeistIds: Set<String>
    ) -> String {
        "\(field)=\"\(actual)\" \(availabilityDescription(for: candidate, visibleHeistIds: visibleHeistIds))"
    }

    static func availabilityDescription(
        for candidate: Screen.ScreenElement,
        visibleHeistIds: Set<String>
    ) -> String {
        if visibleHeistIds.contains(candidate.heistId) {
            return "(heistId: \(candidate.heistId), visible)"
        }

        var details = ["heistId: \(candidate.heistId)", "offscreen"]
        if candidate.contentSpaceOrigin == nil || candidate.scrollView == nil {
            details.append("unreachable")
        }
        return "(\(details.joined(separator: ", ")))"
    }

    /// Drop duplicate formatted candidates while keeping the first occurrence's
    /// position, so repeated parse entries don't make near-miss output noisy.
    private static func dedupedPreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

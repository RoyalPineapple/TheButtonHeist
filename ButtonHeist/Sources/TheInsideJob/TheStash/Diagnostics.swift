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

    static func heistIdNotFound(
        _ heistId: String,
        knownIds: some Collection<String>,
        viewportCount: Int
    ) -> String {
        let similar = knownIds.sorted()
            .filter { $0.contains(heistId) || heistId.contains($0) }
        if similar.isEmpty {
            return "Element not found: \"\(heistId)\" (\(viewportCount) elements on screen)"
        }
        return "Element not found: \"\(heistId)\"\nsimilar: \(similar.joined(separator: ", "))"
    }

    static func matcherNotFound(
        _ matcher: ElementMatcher,
        hierarchy: [AccessibilityHierarchy],
        screenElements: [Screen.ScreenElement],
        viewportHeistIds: Set<String>,
        traversalOrder: [String: Int]
    ) -> String {
        let query = formatMatcher(matcher)

        // Tier 1: Near-miss — relax one predicate at a time to find what diverged.
        if let nearMiss = findNearMiss(for: matcher, in: hierarchy) {
            return "No match for: \(query)\n\(nearMiss)"
        }

        // Tier 2: Nothing close — dump a compact summary.
        let summary = compactElementSummary(
            screenElements: screenElements,
            viewportHeistIds: viewportHeistIds,
            traversalOrder: traversalOrder
        )
        return "No match for: \(query)\n\(summary)"
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
        in hierarchy: [AccessibilityHierarchy]
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
            let hits = hierarchy.matches(relaxation.relaxed, mode: .substring, limit: suggestionCap + 1)
            guard !hits.isEmpty else { continue }
            let candidates = hits.prefix(suggestionCap).map { relaxation.actual($0.element) }
            let suggestion = candidates
                .map { "\(relaxation.field)=\"\($0)\"" }
                .joined(separator: ", ")
            let suffix = hits.count > suggestionCap ? ", ..." : ""
            return "near miss: matched all fields except \(relaxation.field) — did you mean \(suggestion)\(suffix)?"
        }

        // Fallback: when the matcher only has one predicate (or every relaxation
        // empties out), retry the original matcher with substring semantics
        // against the single remaining field so the agent who typed a partial
        // still gets concrete suggestions. This is the only place where
        // substring search reaches user-visible output; resolution itself
        // remains strictly exact-or-miss.
        for relaxation in relaxations where !relaxation.relaxed.hasPredicates {
            let substringHits = hierarchy.matches(matcher, mode: .substring, limit: suggestionCap + 1)
            guard !substringHits.isEmpty else { continue }
            let candidates = substringHits.prefix(suggestionCap).map { relaxation.actual($0.element) }
            let suggestion = candidates
                .map { "\(relaxation.field)=\"\($0)\"" }
                .joined(separator: ", ")
            let suffix = substringHits.count > suggestionCap ? ", ..." : ""
            return "near miss: \(relaxation.field) matched as substring only — did you mean \(suggestion)\(suffix)?"
        }
        return nil
    }

    /// Compact summary of on-screen elements for total-miss fallback.
    /// Capped at 20 elements to avoid flooding the response.
    static func compactElementSummary(
        screenElements: [Screen.ScreenElement],
        viewportHeistIds: Set<String>,
        traversalOrder: [String: Int]
    ) -> String {
        let cap = 20
        let visibleElements = screenElements
            .filter { viewportHeistIds.contains($0.heistId) }
            .sorted { (traversalOrder[$0.heistId] ?? Int.max) < (traversalOrder[$1.heistId] ?? Int.max) }
        if visibleElements.isEmpty {
            return "screen is empty (0 elements)"
        }
        var lines = ["\(visibleElements.count) elements on screen:"]
        for entry in visibleElements.prefix(cap) {
            let element = entry.element
            var parts: [String] = []
            if let label = element.label, !label.isEmpty { parts.append("label=\"\(label)\"") }
            if let identifier = element.identifier, !identifier.isEmpty { parts.append("id=\"\(identifier)\"") }
            if let value = element.value, !value.isEmpty { parts.append("value=\"\(value)\"") }
            let traitNames = UIAccessibilityTraits.knownTraits
                .filter { element.traits.contains($0.trait) }
                .map(\.name)
            if !traitNames.isEmpty { parts.append("[\(traitNames.joined(separator: ","))]") }
            lines.append("  \(parts.joined(separator: " "))")
        }
        if visibleElements.count > cap {
            lines.append("  ... and \(visibleElements.count - cap) more")
        }
        return lines.joined(separator: "\n")
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

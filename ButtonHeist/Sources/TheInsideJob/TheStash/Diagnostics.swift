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
        screenElements: [String: ScreenElement],
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
        if let l = matcher.label { fields.append("label=\"\(l)\"") }
        if let id = matcher.identifier { fields.append("identifier=\"\(id)\"") }
        if let v = matcher.value { fields.append("value=\"\(v)\"") }
        if let t = matcher.traits { fields.append("traits=[\(t.map(\.rawValue).joined(separator: ","))]") }
        if let e = matcher.excludeTraits { fields.append("excludeTraits=[\(e.map(\.rawValue).joined(separator: ","))]") }
        return fields.joined(separator: " ")
    }

    /// Try relaxing one predicate at a time. Value is relaxed first (most likely
    /// to drift — e.g. slider moved), then traits, label, identifier.
    /// Only considers relaxations that still have at least one remaining predicate —
    /// dropping the only predicate matches everything, which isn't a useful near-miss.
    /// Returns a diagnostic line or nil if no near-miss found.
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

        for relaxation in relaxations {
            guard relaxation.relaxed.hasPredicates,
                  let found = hierarchy.firstMatch(relaxation.relaxed, mode: .substring)?.element else { continue }
            let actualValue = relaxation.actual(found)
            return "near miss: matched all fields except \(relaxation.field) — actual \(relaxation.field)=\(actualValue)"
        }
        return nil
    }

    /// Compact summary of on-screen elements for total-miss fallback.
    /// Capped at 20 elements to avoid flooding the response.
    static func compactElementSummary(
        screenElements: [String: ScreenElement],
        viewportHeistIds: Set<String>,
        traversalOrder: [String: Int]
    ) -> String {
        let cap = 20
        let visibleElements = screenElements.values
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
} // extension TheStash

#endif // DEBUG
#endif // canImport(UIKit)

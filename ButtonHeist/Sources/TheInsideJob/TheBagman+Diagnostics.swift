#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Resolution Diagnostics
//
// Diagnostic messages for element resolution failures: near-miss suggestions,
// similar heistId hints, and compact element summaries for total misses.

extension TheBagman {

    func heistIdNotFoundMessage(_ heistId: String) -> String {
        let similar = screenElements.keys.sorted()
            .filter { $0.contains(heistId) || heistId.contains($0) }
        if similar.isEmpty {
            let count = viewportHeistIds.count
            return "Element not found: \"\(heistId)\" (\(count) elements on screen)"
        }
        return "Element not found: \"\(heistId)\"\nsimilar: \(similar.joined(separator: ", "))"
    }

    /// Diagnostics for a matcher that had zero matches (not ambiguous — that's
    /// handled by `resolveTarget` returning `.ambiguous`).
    func matcherNotFoundMessage(_ matcher: ElementMatcher) -> String {
        let query = formatMatcher(matcher)

        // Tier 1: Near-miss — relax one predicate at a time to find what diverged.
        if let nearMiss = findNearMiss(for: matcher) {
            return "No match for: \(query)\n\(nearMiss)"
        }

        // Tier 2: Nothing close — dump a compact summary and suggest looking for a search field.
        return "No match for: \(query)\n\(compactElementSummary())"
    }

    /// Format a matcher's predicates as a human-readable query string.
    func formatMatcher(_ matcher: ElementMatcher) -> String {
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
    func findNearMiss(for matcher: ElementMatcher) -> String? {
        typealias Relaxation = (field: String, relaxed: ElementMatcher, actual: (AccessibilityElement) -> String)
        var relaxations: [Relaxation] = []

        if matcher.value != nil {
            relaxations.append((
                field: "value",
                relaxed: ElementMatcher(
                    label: matcher.label, identifier: matcher.identifier,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.value ?? "(nil)" }
            ))
        }
        if matcher.traits != nil {
            relaxations.append((
                field: "traits",
                relaxed: ElementMatcher(
                    label: matcher.label, identifier: matcher.identifier,
                    value: matcher.value, excludeTraits: matcher.excludeTraits                ),
                actual: { element in
                    UIAccessibilityTraits.knownTraits
                        .filter { element.traits.contains($0.trait) }
                        .map(\.name).joined(separator: ", ")
                }
            ))
        }
        if matcher.label != nil {
            relaxations.append((
                field: "label",
                relaxed: ElementMatcher(
                    identifier: matcher.identifier, value: matcher.value,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.label ?? "(nil)" }
            ))
        }
        if matcher.identifier != nil {
            relaxations.append((
                field: "identifier",
                relaxed: ElementMatcher(
                    label: matcher.label, value: matcher.value,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.identifier ?? "(nil)" }
            ))
        }

        for relaxation in relaxations {
            guard relaxation.relaxed.hasPredicates,
                  let found = findMatch(relaxation.relaxed) else { continue }
            let actualValue = relaxation.actual(found)
            return "near miss: matched all fields except \(relaxation.field) — actual \(relaxation.field)=\(actualValue)"
        }
        return nil
    }

    /// Compact summary of on-screen elements for total-miss fallback.
    /// Capped at 20 elements to avoid flooding the response.
    func compactElementSummary() -> String {
        let cap = 20
        let orderByHeistId = buildTraversalOrderIndex()
        let visibleElements = screenElements.values
            .filter { viewportHeistIds.contains($0.heistId) }
            .sorted { (orderByHeistId[$0.heistId] ?? Int.max) < (orderByHeistId[$1.heistId] ?? Int.max) }
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

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Resolution Diagnostics
//
// Diagnostic messages for element resolution failures: near-miss suggestions,
// similar heistId hints, and compact element summaries for total misses.
// All methods take the data they need as parameters — no mutable state.

/// One relaxation candidate: the field that was dropped, the relaxed predicate,
/// and a closure that reads the actual value from a matched element so the
/// diagnostic can show what the original predicate diverged from.
private struct Relaxation {
    let field: String
    let relaxed: ElementPredicate
    let actual: (AccessibilityElement) -> String
}

extension TheStash {

    func presenceWaitTimeoutMessage(
        for predicate: AccessibilityPredicate,
        elapsed: String
    ) -> String? {
        let target: ElementTarget
        let absent: Bool
        switch predicate {
        case .state(.present(let elementPredicate)):
            target = .predicate(elementPredicate, ordinal: 0)
            absent = false
        case .state(.absent(let elementPredicate)):
            target = .predicate(elementPredicate, ordinal: 0)
            absent = true
        default:
            return nil
        }

        let resolution = resolveTarget(target)
        let expected = absent ? "element to disappear" : "element to appear"
        let reason = absent ? "element still present" : "element not found"
        let diagnostics = resolution.diagnostics
        var parts = [
            "timed out after \(elapsed)s waiting for \(expected)",
            "expected: \(waitForTargetDescription(target))",
            "known: \(knownElementCount) elements",
        ]
        if let screenId = lastScreenId {
            parts.append("screen: \(screenId)")
        }
        if diagnostics.isEmpty {
            parts.append("last result: \(reason)")
        } else {
            parts.append("last result: \(reason): \(diagnostics)")
        }
        parts.append(
            "Next: get_interface() to inspect current elements, " +
                "then retry wait with an exact predicate."
        )
        return parts.joined(separator: "; ")
    }

    private func waitForTargetDescription(_ target: ElementTarget) -> String {
        switch target {
        case .predicate(let predicate, let ordinal):
            var description = Diagnostics.formatMatcher(predicate)
            if let ordinal {
                description += " ordinal=\(ordinal)"
            }
            return description
        }
    }

    enum Diagnostics {

    static func matcherNotFound(
        _ predicate: ElementPredicate,
        screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<HeistId>,
        resolutionScope: ResolutionScope
    ) -> String {
        let query = formatMatcher(predicate)
        let formattedQuery = query.isEmpty ? "<empty predicate>" : query

        // Tier 1: Near-miss — relax one predicate at a time to find what diverged.
        if let nearMiss = findNearMiss(for: predicate, in: screenElements, visibleHeistIds: visibleHeistIds) {
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

    /// Format a predicate's fields as a human-readable query string.
    static func formatMatcher(_ predicate: ElementPredicate) -> String {
        var fields: [String] = []
        for label in predicate.labelMatches { fields.append("label=\"\(label)\"") }
        for identifier in predicate.identifierMatches { fields.append("identifier=\"\(identifier)\"") }
        for value in predicate.valueMatches { fields.append("value=\"\(value)\"") }
        if !predicate.traits.isEmpty { fields.append("traits=[\(predicate.traits.map(\.rawValue).joined(separator: ","))]") }
        if !predicate.excludeTraits.isEmpty {
            fields.append("excludeTraits=[\(predicate.excludeTraits.map(\.rawValue).joined(separator: ","))]")
        }
        return fields.joined(separator: " ")
    }

    /// Try relaxing one predicate at a time. Value is relaxed first (most likely
    /// to drift — e.g. slider moved), then traits, label, identifier.
    /// Only considers relaxations that still have at least one remaining predicate —
    /// dropping the only predicate matches everything, which isn't a useful near-miss.
    /// Returns a diagnostic line listing up to three near-miss candidates, or
    /// nil if no near-miss was found. This path preserves the authored
    /// predicate exactly for remaining fields; derived substring searches live
    /// in the separate failure-capture diagnostic pipeline.
    static func findNearMiss(
        for predicate: ElementPredicate,
        in screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<HeistId>
    ) -> String? {
        var relaxations: [Relaxation] = []
        if !predicate.valueMatches.isEmpty {
            relaxations.append(Relaxation(
                field: "value",
                relaxed: ElementPredicate(
                    labelMatches: predicate.labelMatches,
                    identifierMatches: predicate.identifierMatches,
                    traits: predicate.traits, excludeTraits: predicate.excludeTraits
                ),
                actual: { $0.value ?? "(nil)" }
            ))
        }
        if !predicate.traits.isEmpty {
            relaxations.append(Relaxation(
                field: "traits",
                relaxed: ElementPredicate(
                    labelMatches: predicate.labelMatches,
                    identifierMatches: predicate.identifierMatches,
                    valueMatches: predicate.valueMatches,
                    excludeTraits: predicate.excludeTraits
                ),
                actual: { element in
                    AccessibilityTraits.knownTraits
                        .filter { element.traits.contains($0.trait) }
                        .map { $0.name }.joined(separator: ", ")
                }
            ))
        }
        if !predicate.labelMatches.isEmpty {
            relaxations.append(Relaxation(
                field: "label",
                relaxed: ElementPredicate(
                    identifierMatches: predicate.identifierMatches,
                    valueMatches: predicate.valueMatches,
                    traits: predicate.traits, excludeTraits: predicate.excludeTraits
                ),
                actual: { $0.label ?? "(nil)" }
            ))
        }
        if !predicate.identifierMatches.isEmpty {
            relaxations.append(Relaxation(
                field: "identifier",
                relaxed: ElementPredicate(
                    labelMatches: predicate.labelMatches,
                    valueMatches: predicate.valueMatches,
                    traits: predicate.traits, excludeTraits: predicate.excludeTraits
                ),
                actual: { $0.identifier ?? "(nil)" }
            ))
        }

        let suggestionCap = 3
        for relaxation in relaxations {
            guard relaxation.relaxed.hasPredicates else { continue }
            let hits = matchCandidates(relaxation.relaxed, in: screenElements, limit: suggestionCap + 1)
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
        return nil
    }

    static func failureInterfaceSuggestion(
        for predicate: ElementPredicate,
        elements: [HeistElement],
        limit: Int = 3
    ) -> String? {
        guard limit > 0, let diagnosticPredicate = diagnosticContainsPredicate(from: predicate) else { return nil }
        let hits = elements.filter { diagnosticPredicate.matches($0) }.prefix(limit + 1)
        guard !hits.isEmpty else { return nil }
        let deduped = dedupedPreservingOrder(hits.map {
            failureInterfaceSuggestionValue(
                failedPredicate: predicate,
                diagnosticPredicate: diagnosticPredicate,
                element: $0
            )
        })
        let suggestions = deduped.prefix(limit).joined(separator: "; ")
        let suffix = deduped.count > limit ? "; ..." : ""
        return "captured interface contains-match suggestion: \(suggestions)\(suffix)"
    }

    private static func diagnosticContainsPredicate(from predicate: ElementPredicate) -> ElementPredicate? {
        let diagnostic = ElementPredicate(
            labelMatches: predicate.labelMatches.map { .contains($0.value) },
            identifierMatches: predicate.identifierMatches.map { .contains($0.value) },
            valueMatches: predicate.valueMatches.map { .contains($0.value) },
            traits: predicate.traits,
            excludeTraits: predicate.excludeTraits
        )
        return diagnostic == predicate ? nil : diagnostic
    }

    private static func failureInterfaceSuggestionValue(
        failedPredicate: ElementPredicate,
        diagnosticPredicate: ElementPredicate,
        element: HeistElement
    ) -> String {
        var observed: [String] = []
        if !failedPredicate.labelMatches.isEmpty, let label = element.label, !label.isEmpty {
            observed.append("label=\"\(label)\"")
        }
        if !failedPredicate.identifierMatches.isEmpty, let identifier = element.identifier, !identifier.isEmpty {
            observed.append("id=\"\(identifier)\"")
        }
        if !failedPredicate.valueMatches.isEmpty, let value = element.value, !value.isEmpty {
            observed.append("value=\"\(value)\"")
        }
        return "\(observed.joined(separator: " ")) — try \(exactPredicateDescription(failedPredicate, element: element)) or \(diagnosticPredicate)"
    }

    private static func exactPredicateDescription(_ failedPredicate: ElementPredicate, element: HeistElement) -> String {
        ElementPredicate(
            labelMatches: !failedPredicate.labelMatches.isEmpty ? element.label.map { [.exact($0)] } ?? [] : [],
            identifierMatches: !failedPredicate.identifierMatches.isEmpty ? element.identifier.map { [.exact($0)] } ?? [] : [],
            valueMatches: !failedPredicate.valueMatches.isEmpty ? element.value.map { [.exact($0)] } ?? [] : [],
            traits: failedPredicate.traits,
            excludeTraits: failedPredicate.excludeTraits
        ).description
    }

    /// Compact summary of known elements for total-miss diagnostics.
    /// Capped at 20 elements to avoid flooding the response.
    static func compactElementSummary(
        screenElements: [Screen.ScreenElement],
        visibleHeistIds: Set<HeistId>,
        resolutionScope: String = "known"
    ) -> String {
        let cap = 20
        if screenElements.isEmpty {
            return """
                \(resolutionScope) hierarchy is empty (0 elements)
                Next: wait for the target to appear, then retry with an exact label, identifier, or value.
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
            let traitNames = AccessibilityTraits.knownTraits
                .filter { element.traits.contains($0.trait) }
                .map { $0.name }
            if !traitNames.isEmpty { parts.append("[\(traitNames.joined(separator: ","))]") }
            parts.append(availabilityDescription(for: entry, visibleHeistIds: visibleHeistIds))
            lines.append("  \(parts.joined(separator: " "))")
        }
        if screenElements.count > cap {
            lines.append("  ... and \(screenElements.count - cap) more")
        }
        lines.append(
            "Next: target one listed element by exact label, identifier, or value; "
                + "if the target is absent, wait for it to appear."
        )
        return lines.joined(separator: "\n")
    }

    private static func matchCandidates(
        _ predicate: ElementPredicate,
        in screenElements: [Screen.ScreenElement],
        limit: Int
    ) -> [Screen.ScreenElement] {
        guard limit > 0 else { return [] }
        var hits: [Screen.ScreenElement] = []
        hits.reserveCapacity(limit)
        for entry in screenElements where predicate.matches(entry.element) {
            hits.append(entry)
            if hits.count == limit { break }
        }
        return hits
    }

    private static func suggestionValue(
        field: String,
        actual: String,
        candidate: Screen.ScreenElement,
        visibleHeistIds: Set<HeistId>
    ) -> String {
        "\(field)=\"\(actual)\" \(availabilityDescription(for: candidate, visibleHeistIds: visibleHeistIds))"
    }

    static func availabilityDescription(
        for candidate: Screen.ScreenElement,
        visibleHeistIds: Set<HeistId>
    ) -> String {
        if visibleHeistIds.contains(candidate.heistId) {
            return "(visible)"
        }

        var details = ["offscreen"]
        if candidate.contentSpaceOrigin == nil {
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

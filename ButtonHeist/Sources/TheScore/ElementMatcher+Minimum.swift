import Foundation

// MARK: - Minimum Matcher

/// The smallest durable predicate that identifies one element within a capture.
///
/// Recording uses this rule to derive a replay target from the full
/// accessibility state, never from viewport accidents. If a later capture
/// introduces a conflict, run a fresh minimum-predicate pass for that capture.
public struct MinimumMatcher: Sendable, Equatable {
    public let element: HeistElement
    public let predicate: ElementPredicate
    public let ordinal: Int?

    public init(element: HeistElement, predicate: ElementPredicate, ordinal: Int? = nil) {
        self.element = element
        self.predicate = predicate
        self.ordinal = ordinal
    }

    /// Build a predicate for an element using its containing capture as the
    /// uniqueness universe.
    ///
    /// A predicate is valid only relative to the full accessibility state that
    /// proves its uniqueness. If the supplied element is no longer present in
    /// the capture, append it to the uniqueness universe so recording still
    /// emits a deterministic target instead of terminating the host app.
    public static func build(
        element: HeistElement,
        in capture: AccessibilityTrace.Capture
    ) -> MinimumMatcher? {
        let elements = capture.interface.projectedElements
        if let captureElement = elements.first(where: { $0 == element }) {
            return build(element: captureElement, allElements: elements)
        }
        return build(element: element, allElements: elements + [element])
    }

    /// Build predicates for every element in a capture, preserving traversal order.
    public static func buildAll(in capture: AccessibilityTrace.Capture) -> [MinimumMatcher] {
        let elements = capture.interface.projectedElements
        return elements.compactMap { build(element: $0, allElements: elements) }
    }

    private static func build(
        element: HeistElement,
        allElements: [HeistElement]
    ) -> MinimumMatcher? {
        let candidates = candidatePredicates(for: element, allElements: allElements)
        for candidate in candidates where uniquelyMatches(candidate, element: element, in: allElements) {
            return MinimumMatcher(element: element, predicate: candidate)
        }

        guard let bestPredicate = candidates.last else { return nil }
        return MinimumMatcher(
            element: element,
            predicate: bestPredicate,
            ordinal: ordinalOf(element, matching: bestPredicate, in: allElements)
        )
    }

    private static func candidatePredicates(for element: HeistElement, allElements: [HeistElement]) -> [ElementPredicate] {
        let label = nonEmpty(element.label)
        let value = nonEmpty(element.value)
        let identifier = element.identifier.flatMap { isStableIdentifier($0) ? nonEmpty($0) : nil }
        let semanticTraits = predicateTraits(
            element.traits.filter { !AccessibilityPolicy.transientTraits.contains($0) }
        )
        let stateTraits = predicateTraits(
            element.traits.filter { AccessibilityPolicy.transientTraits.contains($0) }
        )
        var candidates: [ElementPredicate] = []

        // Product contract: identifier > label > semantic traits > value >
        // stateful traits > ordinal.
        func append(
            label: String? = nil,
            traits: [HeistTrait] = [],
            value: String? = nil,
            identifier: String? = nil,
            excludeTraits: [HeistTrait] = []
        ) {
            let predicate = ElementPredicate(
                label: label,
                identifier: identifier,
                value: value,
                traits: traits,
                excludeTraits: excludeTraits
            )
            guard predicate.hasPredicates, !candidates.contains(predicate) else { return }
            candidates.append(predicate)
        }

        func appendStateVariants(after base: ElementPredicate) {
            guard base.hasPredicates || !stateTraits.isEmpty else { return }
            append(
                label: base.label,
                traits: combine(base.traits, stateTraits),
                value: base.value,
                identifier: base.identifier
            )
            let excludeTraits = excludedStateTraits(for: element, basePredicate: base, in: allElements)
            append(
                label: base.label,
                traits: base.traits,
                value: base.value,
                identifier: base.identifier,
                excludeTraits: excludeTraits
            )
            append(
                label: base.label,
                traits: combine(base.traits, stateTraits),
                value: base.value,
                identifier: base.identifier,
                excludeTraits: excludeTraits
            )
        }

        func appendProgression(identifier: String? = nil) {
            var base = ElementPredicate(identifier: identifier)

            if let identifier {
                append(identifier: identifier)
            }

            if let label {
                base = ElementPredicate(label: label, identifier: identifier)
                append(label: label, identifier: identifier)
            }

            if !semanticTraits.isEmpty {
                base = ElementPredicate(label: base.label, identifier: base.identifier, traits: semanticTraits)
                append(label: base.label, traits: semanticTraits, identifier: base.identifier)
            }

            if let value {
                base = ElementPredicate(
                    label: base.label,
                    identifier: base.identifier,
                    value: value,
                    traits: base.traits
                )
                append(label: base.label, traits: base.traits, value: value, identifier: base.identifier)
            }

            appendStateVariants(after: base)
        }

        if let identifier {
            appendProgression(identifier: identifier)
        } else {
            appendProgression()
        }

        return candidates
    }

    private static func combine(_ left: [HeistTrait], _ right: [HeistTrait]) -> [HeistTrait] {
        predicateTraits(left + right)
    }

    private static func excludedStateTraits(
        for element: HeistElement,
        basePredicate: ElementPredicate,
        in allElements: [HeistElement]
    ) -> [HeistTrait] {
        guard basePredicate.hasPredicates else { return [] }
        let elementTraits = Set(element.traits)
        let excluded = allElements
            .filter { $0 != element && $0.matches(basePredicate) }
            .flatMap(\.traits)
            .filter { AccessibilityPolicy.transientTraits.contains($0) && !elementTraits.contains($0) }
        return predicateTraits(Array(Set(excluded)))
    }

    private static func predicateTraits(_ traits: [HeistTrait]) -> [HeistTrait] {
        traits.sorted { left, right in
            traitSortKey(left) < traitSortKey(right)
        }
    }

    private static func traitSortKey(_ trait: HeistTrait) -> (Int, String) {
        if let index = AccessibilityPolicy.synthesisPriority.firstIndex(of: trait) {
            return (index, trait.rawValue)
        }
        return (AccessibilityPolicy.synthesisPriority.count, trait.rawValue)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func uniquelyMatches(
        _ predicate: ElementPredicate,
        element: HeistElement,
        in allElements: [HeistElement]
    ) -> Bool {
        var matchCount = 0
        for candidate in allElements where candidate.matches(predicate) {
            matchCount += 1
            if matchCount > 1 { return false }
        }
        return matchCount == 1
    }

    /// Find the 0-based index of `element` among all elements matching `predicate`.
    /// Returns nil if the element is the only match.
    private static func ordinalOf(
        _ element: HeistElement,
        matching predicate: ElementPredicate,
        in allElements: [HeistElement]
    ) -> Int? {
        var index = 0
        var found: Int?
        var totalMatches = 0
        for candidate in allElements where candidate.matches(predicate) {
            if candidate.heistId == element.heistId {
                found = index
            }
            index += 1
            totalMatches += 1
        }
        guard totalMatches > 1 else { return nil }
        return found
    }
}

extension MinimumMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("minimumMatcher", [
            ScoreDescription.stringField("element", element.heistId),
            predicate.description,
            ScoreDescription.valueField("ordinal", ordinal),
        ].compactMap { $0 })
    }
}

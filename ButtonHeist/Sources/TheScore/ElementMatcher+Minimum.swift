import Foundation

// MARK: - Minimum Matcher

/// The smallest durable matcher that identifies one element within a capture.
///
/// Recording and replay repair both need the same rule: derive a matcher from
/// the full accessibility state, never from viewport accidents, and include an
/// ordinal only when the durable predicates are still ambiguous.
public struct MinimumMatcher: Sendable, Equatable {
    public let element: HeistElement
    public let matcher: ElementMatcher
    public let ordinal: Int?

    public init(element: HeistElement, matcher: ElementMatcher, ordinal: Int? = nil) {
        self.element = element
        self.matcher = matcher
        self.ordinal = ordinal
    }

    /// Build a matcher for an element using its containing capture as the
    /// uniqueness universe.
    ///
    /// A matcher is valid only relative to the full accessibility state that
    /// proves its uniqueness. Passing an element that is not in the capture is
    /// a programming error.
    public static func build(
        element: HeistElement,
        in capture: AccessibilityTrace.Capture
    ) -> MinimumMatcher {
        let elements = capture.interface.elements
        guard let captureElement = elements.first(where: { $0 == element }) else {
            preconditionFailure("MinimumMatcher requires an element from the supplied capture")
        }
        return build(element: captureElement, allElements: elements)
    }

    /// Build matchers for every element in a capture, preserving traversal order.
    public static func buildAll(in capture: AccessibilityTrace.Capture) -> [MinimumMatcher] {
        let elements = capture.interface.elements
        return elements.map { build(element: $0, allElements: elements) }
    }

    private static func build(
        element: HeistElement,
        allElements: [HeistElement]
    ) -> MinimumMatcher {
        let candidates = candidateMatchers(for: element, allElements: allElements)
        for candidate in candidates where uniquelyMatches(candidate, element: element, in: allElements) {
            return MinimumMatcher(element: element, matcher: candidate)
        }

        let bestMatcher = candidates.last ?? ElementMatcher()
        return MinimumMatcher(
            element: element,
            matcher: bestMatcher,
            ordinal: ordinalOf(element, matching: bestMatcher, in: allElements)
        )
    }

    private static func candidateMatchers(for element: HeistElement, allElements: [HeistElement]) -> [ElementMatcher] {
        let label = nonEmpty(element.label)
        let value = nonEmpty(element.value)
        let identifier = element.identifier.flatMap { isStableIdentifier($0) ? nonEmpty($0) : nil }
        let semanticTraits = matcherTraits(
            element.traits.filter { !AccessibilityPolicy.transientTraits.contains($0) }
        )
        let stateTraits = matcherTraits(
            element.traits.filter { AccessibilityPolicy.transientTraits.contains($0) }
        )
        var candidates: [ElementMatcher] = []

        // Product contract: identifier > label > semantic traits > value >
        // stateful traits > ordinal.
        func append(
            label: String? = nil,
            traits: [HeistTrait]? = nil,
            value: String? = nil,
            identifier: String? = nil,
            excludeTraits: [HeistTrait]? = nil
        ) {
            let matcher = ElementMatcher(
                label: label,
                identifier: identifier,
                value: value,
                traits: traits,
                excludeTraits: excludeTraits
            )
            guard matcher.hasPredicates, !candidates.contains(matcher) else { return }
            candidates.append(matcher)
        }

        func appendStateVariants(after base: ElementMatcher) {
            guard base.hasPredicates || stateTraits != nil else { return }
            append(
                label: base.label,
                traits: combine(base.traits, stateTraits),
                value: base.value,
                identifier: base.identifier
            )
            let excludeTraits = excludedStateTraits(for: element, baseMatcher: base, in: allElements)
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
            var base = ElementMatcher(identifier: identifier)

            if let identifier {
                append(identifier: identifier)
            }

            if let label {
                base = ElementMatcher(label: label, identifier: identifier)
                append(label: label, identifier: identifier)
            }

            if let semanticTraits {
                base = ElementMatcher(label: base.label, identifier: base.identifier, traits: semanticTraits)
                append(label: base.label, traits: semanticTraits, identifier: base.identifier)
            }

            if let value {
                base = ElementMatcher(
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

    private static func combine(_ left: [HeistTrait]?, _ right: [HeistTrait]?) -> [HeistTrait]? {
        matcherTraits((left ?? []) + (right ?? []))
    }

    private static func excludedStateTraits(
        for element: HeistElement,
        baseMatcher: ElementMatcher,
        in allElements: [HeistElement]
    ) -> [HeistTrait]? {
        guard baseMatcher.hasPredicates else { return nil }
        let elementTraits = Set(element.traits)
        let excluded = allElements
            .filter { $0 != element && $0.matches(baseMatcher) }
            .flatMap(\.traits)
            .filter { AccessibilityPolicy.transientTraits.contains($0) && !elementTraits.contains($0) }
        return matcherTraits(Array(Set(excluded)))
    }

    private static func matcherTraits(_ traits: [HeistTrait]) -> [HeistTrait]? {
        let traits = traits.sorted { left, right in
            traitSortKey(left) < traitSortKey(right)
        }
        return traits.isEmpty ? nil : traits
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
        _ matcher: ElementMatcher,
        element: HeistElement,
        in allElements: [HeistElement]
    ) -> Bool {
        var matchCount = 0
        for candidate in allElements where candidate.matches(matcher) {
            matchCount += 1
            if matchCount > 1 { return false }
        }
        return matchCount == 1
    }

    /// Find the 0-based index of `element` among all elements matching `matcher`.
    /// Returns nil if the element is the only match.
    private static func ordinalOf(
        _ element: HeistElement,
        matching matcher: ElementMatcher,
        in allElements: [HeistElement]
    ) -> Int? {
        var index = 0
        var found: Int?
        var totalMatches = 0
        for candidate in allElements where candidate.matches(matcher) {
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

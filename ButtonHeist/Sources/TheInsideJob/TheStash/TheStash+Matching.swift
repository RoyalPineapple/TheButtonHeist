#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Stable Identity

extension AccessibilityElement {

    /// Key for tracking unique elements across scroll positions.
    /// Prefers semantic properties (label, identifier, value) which are stable
    /// across scroll offsets. When all semantic properties are empty, falls back
    /// to frame geometry so identical unlabeled elements at different positions
    /// still hash as distinct.
    struct StableKey: Hashable {
        let label: String?
        let identifier: String?
        let value: String?
        let traits: UIAccessibilityTraits
        let fallbackFrame: CGRect?
    }

    private var hasSemanticIdentity: Bool {
        label?.isEmpty == false
            || identifier?.isEmpty == false
            || value?.isEmpty == false
    }

    var stableKey: StableKey {
        let frame: CGRect? = hasSemanticIdentity ? nil : shape.frame
        return StableKey(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            fallbackFrame: frame
        )
    }
}

// MARK: - Hierarchy-Level Element Matching

/// Matching operates on the canonical accessibility tree — AccessibilityElement
/// and AccessibilityHierarchy — not on wire types. Trait name strings from
/// ElementMatcher are resolved to UIAccessibilityTraits bitmasks so comparisons
/// happen at the source data level.

extension AccessibilityHierarchy {

    /// Match result: the leaf element that matched.
    struct MatchResult {
        let element: AccessibilityElement
    }
}

extension AccessibilityHierarchy {
    /// Match a single node against a matcher. For leaf elements, returns the match
    /// if the element satisfies the predicate. For containers, returns the first
    /// matching leaf descendant.
    func matches(_ matcher: ElementMatcher) -> MatchResult? {
        [self].firstMatch(matcher)
    }
}

extension Array where Element == AccessibilityHierarchy {

    /// First leaf element in the tree that satisfies all property predicates.
    func firstMatch(_ matcher: ElementMatcher) -> AccessibilityHierarchy.MatchResult? {
        matches(matcher, limit: 1).first
    }

    /// Leaf elements matching the predicate, stopping after `limit` results.
    /// Results are in tree traversal order. Use this for early-exit resolution:
    /// limit 1 for first-match, limit 2 for unique-match, limit N+1 for ordinal N.
    func matches(
        _ matcher: ElementMatcher,
        limit: Int
    ) -> [AccessibilityHierarchy.MatchResult] {
        guard limit > 0 else { return [] }
        return compactMap(first: limit, context: (), container: { _, _ in () }, element: { element, _, _ in
            element.matches(matcher) ? AccessibilityHierarchy.MatchResult(element: element) : nil
        })
    }

    /// Whether any leaf element in the tree satisfies the property predicates.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        !matches(matcher, limit: 1).isEmpty
    }
}

// MARK: - AccessibilityElement Matching

extension AccessibilityElement {

    /// Known trait name strings — references the parser's authoritative set directly.
    private static let knownTraitNames = UIAccessibilityTraits.knownTraitNames

    /// Does this element satisfy all property predicates in the matcher?
    /// String fields (label, identifier, value) use case-insensitive substring matching.
    /// Trait name strings are resolved to bitmasks via the parser's `fromNames`.
    func matches(_ matcher: ElementMatcher) -> Bool {
        if let matchLabel = matcher.label {
            if matchLabel.isEmpty { return false }
            guard let label, label.localizedCaseInsensitiveContains(matchLabel) else { return false }
        }
        if let matchIdentifier = matcher.identifier {
            if matchIdentifier.isEmpty { return false }
            guard let identifier, identifier.localizedCaseInsensitiveContains(matchIdentifier) else { return false }
        }
        if let matchValue = matcher.value {
            if matchValue.isEmpty { return false }
            guard let value, value.localizedCaseInsensitiveContains(matchValue) else { return false }
        }
        if let requiredTraits = matcher.traits, !requiredTraits.isEmpty {
            // Unknown trait names must cause a miss — fromNames drops them silently
            // and .contains(.none) is always true, so validate every name resolved.
            let requiredNames = requiredTraits.map(\.rawValue)
            for name in requiredNames where !Self.knownTraitNames.contains(name) { return false }
            let mask = UIAccessibilityTraits.fromNames(requiredNames)
            if !traits.contains(mask) { return false }
        }
        if let excludedTraits = matcher.excludeTraits, !excludedTraits.isEmpty {
            let excludedNames = excludedTraits.map(\.rawValue)
            for name in excludedNames where !Self.knownTraitNames.contains(name) { return false }
            let mask = UIAccessibilityTraits.fromNames(excludedNames)
            if !traits.isDisjoint(with: mask) { return false }
        }
        return true
    }
}

// MARK: - TheStash Match Pipeline

extension TheStash {

    /// Single entry point for matcher-based element lookup. Returns up to `limit`
    /// matching ScreenElements. Checks the hierarchy first (preserves traversal
    /// order for on-screen elements), falls back to the full registry (explored
    /// off-screen elements) when the hierarchy has zero matches.
    ///
    /// Registry fallback is sorted by heistId for deterministic ordinal selection.
    func matchScreenElements(_ matcher: ElementMatcher, limit: Int) -> [ScreenElement] {
        guard limit > 0 else { return [] }
        let hierarchyHits = currentHierarchy.matches(matcher, limit: limit)
        if !hierarchyHits.isEmpty {
            return hierarchyHits.compactMap { match in
                guard let heistId = registry.reverseIndex[match.element] else { return nil }
                return registry.elements[heistId]
            }
        }
        let sorted = registry.elements.values.sorted { $0.heistId < $1.heistId }
        return Array(sorted.lazy.filter { $0.element.matches(matcher) }.prefix(limit))
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

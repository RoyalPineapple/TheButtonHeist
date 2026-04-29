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
    /// matching ScreenElements. Visible matches keep hierarchy traversal order,
    /// then explored off-screen registry matches are appended in content order.
    func matchScreenElements(_ matcher: ElementMatcher, limit: Int) -> [ScreenElement] {
        guard limit > 0 else { return [] }
        let hierarchyHits = currentHierarchy.matches(matcher, limit: limit)
        var seenIds = Set<String>()
        var matches = hierarchyHits.compactMap { match -> ScreenElement? in
            guard let heistId = registry.reverseIndex[match.element],
                  let element = registry.elements[heistId],
                  seenIds.insert(heistId).inserted else { return nil }
            return element
        }
        if matches.count >= limit { return Array(matches.prefix(limit)) }

        let offscreen = registry.elements.values
            .filter { !seenIds.contains($0.heistId) && $0.element.matches(matcher) }
            .sorted(by: registryOrder)
        matches.append(contentsOf: offscreen.prefix(limit - matches.count))
        return matches
    }

    private func registryOrder(_ lhs: ScreenElement, _ rhs: ScreenElement) -> Bool {
        switch (lhs.contentSpaceOrigin, rhs.contentSpaceOrigin) {
        case let (left?, right?):
            if abs(left.y - right.y) >= 0.5 { return left.y < right.y }
            if abs(left.x - right.x) >= 0.5 { return left.x < right.x }
            return lhs.heistId < rhs.heistId
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.heistId < rhs.heistId
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

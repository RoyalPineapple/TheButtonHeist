#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

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
        (label != nil && label?.isEmpty == false)
            || (identifier != nil && identifier?.isEmpty == false)
            || (value != nil && value?.isEmpty == false)
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

    /// All leaf elements in the tree that satisfy the property predicates.
    func allMatches(_ matcher: ElementMatcher) -> [AccessibilityHierarchy.MatchResult] {
        compactMap { element, _ in
            element.matches(matcher) ? .init(element: element) : nil
        }
    }

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
        var results: [AccessibilityHierarchy.MatchResult] = []
        for root in self {
            let limitReached = root.collectMatches(matcher, limit: limit, into: &results)
            if limitReached { break }
        }
        return results
    }

    /// Whether any leaf element in the tree satisfies the property predicates.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        !matches(matcher, limit: 1).isEmpty
    }

    /// Returns the match only if exactly one leaf element satisfies the predicate.
    /// Returns nil on zero matches or ambiguity (2+).
    func uniqueMatch(_ matcher: ElementMatcher) -> AccessibilityHierarchy.MatchResult? {
        let hits = matches(matcher, limit: 2)
        guard hits.count == 1 else { return nil }
        return hits[0]
    }
}

// MARK: - Early-Exit Collection

extension AccessibilityHierarchy {
    /// Collects matching leaf elements into `results`, stopping when `limit` is reached.
    /// Returns true when the limit has been hit (early exit signal for callers).
    func collectMatches(
        _ matcher: ElementMatcher,
        limit: Int,
        into results: inout [MatchResult]
    ) -> Bool {
        switch self {
        case .element(let element, _):
            if element.matches(matcher) {
                results.append(MatchResult(element: element))
                if results.count >= limit { return true }
            }
            return false
        case .container(_, let children):
            for child in children {
                let limitReached = child.collectMatches(matcher, limit: limit, into: &results)
                if limitReached { return true }
            }
            return false
        }
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
            guard let label, label.localizedCaseInsensitiveContains(matchLabel) else { return false }
        }
        if let matchIdentifier = matcher.identifier {
            guard let identifier, identifier.localizedCaseInsensitiveContains(matchIdentifier) else { return false }
        }
        if let matchValue = matcher.value {
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

// MARK: - TheStash Convenience

extension TheStash {

    /// Search the hierarchy tree for the first match.
    func findMatch(_ matcher: ElementMatcher) -> AccessibilityElement? {
        currentHierarchy.firstMatch(matcher)?.element
    }

    /// Whether any element in the current hierarchy matches the predicate.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        currentHierarchy.hasMatch(matcher)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

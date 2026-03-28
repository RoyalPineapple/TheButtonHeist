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

    /// Match result: the leaf element that matched, plus its traversal index.
    struct MatchResult {
        let element: AccessibilityElement
        let traversalIndex: Int

        var label: String? { element.label }
    }

    /// Check if a leaf element at this position satisfies the matcher.
    /// Containers are walked recursively to find leaf elements inside them.
    func matches(_ matcher: ElementMatcher) -> MatchResult? {
        switch self {
        case .element(let element, let traversalIndex):
            if element.matches(matcher) {
                return MatchResult(element: element, traversalIndex: traversalIndex)
            }
            return nil
        case .container(_, let children):
            for child in children {
                if let result = child.matches(matcher) {
                    return result
                }
            }
            return nil
        }
    }
}

extension Array where Element == AccessibilityHierarchy {

    /// First leaf element in the tree that satisfies all property predicates.
    func firstMatch(_ matcher: ElementMatcher) -> AccessibilityHierarchy.MatchResult? {
        for node in self {
            if let result = node.matches(matcher) {
                return result
            }
        }
        return nil
    }

    /// All leaf elements in the tree that satisfy the property predicates.
    func allMatches(_ matcher: ElementMatcher) -> [AccessibilityHierarchy.MatchResult] {
        var results: [AccessibilityHierarchy.MatchResult] = []
        collectMatches(matcher, into: &results)
        return results
    }

    /// Whether any leaf element in the tree satisfies the property predicates.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        firstMatch(matcher) != nil
    }

    private func collectMatches(
        _ matcher: ElementMatcher,
        into results: inout [AccessibilityHierarchy.MatchResult]
    ) {
        for node in self {
            switch node {
            case .element(let element, let traversalIndex):
                if element.matches(matcher) {
                    results.append(.init(element: element, traversalIndex: traversalIndex))
                }
            case .container(_, let children):
                children.collectMatches(matcher, into: &results)
            }
        }
    }
}

// MARK: - AccessibilityElement Matching

extension AccessibilityElement {

    /// Cached set of known trait name strings — avoids rebuilding per-element during search.
    private static let knownTraitNames = Set(UIAccessibilityTraits.knownTraits.map(\.name))

    /// Does this element satisfy all property predicates in the matcher?
    /// Trait name strings are resolved to bitmasks via the parser's `fromNames`.
    func matches(_ matcher: ElementMatcher) -> Bool {
        if let matchLabel = matcher.label, label != matchLabel { return false }
        if let matchIdentifier = matcher.identifier, identifier != matchIdentifier { return false }
        if let matchValue = matcher.value, value != matchValue { return false }
        if let requiredTraits = matcher.traits, !requiredTraits.isEmpty {
            // Unknown trait names must cause a miss — fromNames drops them silently
            // and .contains(.none) is always true, so validate every name resolved.
            for name in requiredTraits where !Self.knownTraitNames.contains(name) { return false }
            let mask = UIAccessibilityTraits.fromNames(requiredTraits)
            if !traits.contains(mask) { return false }
        }
        if let excludedTraits = matcher.excludeTraits, !excludedTraits.isEmpty {
            for name in excludedTraits where !Self.knownTraitNames.contains(name) { return false }
            let mask = UIAccessibilityTraits.fromNames(excludedTraits)
            if !traits.isDisjoint(with: mask) { return false }
        }
        return true
    }
}

// MARK: - Flat Element Array Matching

extension Array where Element == AccessibilityElement {

    /// First element in the flat array that satisfies the matcher.
    func firstMatch(_ matcher: ElementMatcher) -> (element: AccessibilityElement, index: Int)? {
        for (index, element) in enumerated() where element.matches(matcher) {
            return (element, index)
        }
        return nil
    }

    /// Whether any element in the flat array satisfies the matcher.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        contains { $0.matches(matcher) }
    }
}

// MARK: - TheBagman Convenience

enum MatchingError: Error, LocalizedError {
    case heistIdNotSupported

    var errorDescription: String? {
        switch self {
        case .heistIdNotSupported:
            return "findMatch does not resolve heistId — use ActionTarget for heistId-based targeting"
        }
    }
}

extension TheBagman {

    /// Search the hierarchy tree for the first match.
    func findMatch(_ matcher: ElementMatcher) -> (element: AccessibilityElement, index: Int)? {
        guard let found = cachedHierarchy.firstMatch(matcher) else {
            // Fallback to flat array when hierarchy is empty
            return cachedElements.firstMatch(matcher)
        }
        return (found.element, found.traversalIndex)
    }

    /// Whether any cached element matches the predicate.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        if cachedHierarchy.isEmpty {
            return cachedElements.hasMatch(matcher)
        }
        return cachedHierarchy.hasMatch(matcher)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

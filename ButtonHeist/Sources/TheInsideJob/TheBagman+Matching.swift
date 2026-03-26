#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Hierarchy-Level Element Matching

/// Matching operates on the canonical accessibility tree — AccessibilityElement
/// and AccessibilityHierarchy — not on wire types. Trait name strings from
/// ElementMatcher are resolved to UIAccessibilityTraits bitmasks so comparisons
/// happen at the source data level.

extension AccessibilityHierarchy {

    /// Match result: the element, its traversal index in the tree, and the
    /// NSObject it was built from (if the caller has the object mapping).
    struct MatchResult {
        let element: AccessibilityElement
        let traversalIndex: Int
    }

    /// Check if the element at this node satisfies the matcher's property predicates.
    /// Container nodes never match — only leaf elements.
    func matches(
        _ matcher: ElementMatcher,
        traitNames: (UIAccessibilityTraits) -> [String]
    ) -> MatchResult? {
        switch self {
        case .element(let element, let traversalIndex):
            if element.matches(matcher, traitNames: traitNames) {
                return MatchResult(element: element, traversalIndex: traversalIndex)
            }
            return nil
        case .container(_, let children):
            for child in children {
                if let result = child.matches(matcher, traitNames: traitNames) {
                    return result
                }
            }
            return nil
        }
    }
}

extension Array where Element == AccessibilityHierarchy {

    /// First element in the tree that satisfies all property predicates.
    func firstMatch(
        _ matcher: ElementMatcher,
        traitNames: @escaping (UIAccessibilityTraits) -> [String]
    ) -> AccessibilityHierarchy.MatchResult? {
        for node in self {
            if let result = node.matches(matcher, traitNames: traitNames) {
                return result
            }
        }
        return nil
    }

    /// All elements in the tree that satisfy the property predicates.
    func allMatches(
        _ matcher: ElementMatcher,
        traitNames: @escaping (UIAccessibilityTraits) -> [String]
    ) -> [AccessibilityHierarchy.MatchResult] {
        var results: [AccessibilityHierarchy.MatchResult] = []
        collectMatches(matcher, traitNames: traitNames, into: &results)
        return results
    }

    /// Whether any element in the tree satisfies the property predicates.
    func hasMatch(
        _ matcher: ElementMatcher,
        traitNames: @escaping (UIAccessibilityTraits) -> [String]
    ) -> Bool {
        firstMatch(matcher, traitNames: traitNames) != nil
    }

    private func collectMatches(
        _ matcher: ElementMatcher,
        traitNames: (UIAccessibilityTraits) -> [String],
        into results: inout [AccessibilityHierarchy.MatchResult]
    ) {
        for node in self {
            switch node {
            case .element(let element, let traversalIndex):
                if element.matches(matcher, traitNames: traitNames) {
                    results.append(.init(element: element, traversalIndex: traversalIndex))
                }
            case .container(_, let children):
                children.collectMatches(matcher, traitNames: traitNames, into: &results)
            }
        }
    }
}

// MARK: - AccessibilityElement Matching

extension AccessibilityElement {

    /// Does this element satisfy all property predicates in the matcher?
    /// Trait name strings are resolved via the provided mapping function.
    /// The `heistId` field is ignored — it's a wire-level concept.
    func matches(
        _ matcher: ElementMatcher,
        traitNames: (UIAccessibilityTraits) -> [String]
    ) -> Bool {
        if let matchLabel = matcher.label, label != matchLabel { return false }
        if let matchIdentifier = matcher.identifier, identifier != matchIdentifier { return false }
        if let matchValue = matcher.value, value != matchValue { return false }
        if let requiredTraits = matcher.traits {
            let names = Set(traitNames(traits))
            for trait in requiredTraits where !names.contains(trait) { return false }
        }
        if let excludedTraits = matcher.excludeTraits {
            let names = Set(traitNames(traits))
            for trait in excludedTraits where names.contains(trait) { return false }
        }
        return true
    }
}

// MARK: - Flat Element Array Matching

extension Array where Element == AccessibilityElement {

    /// First element in the flat array that satisfies the matcher.
    func firstMatch(
        _ matcher: ElementMatcher,
        traitNames: @escaping (UIAccessibilityTraits) -> [String]
    ) -> (element: AccessibilityElement, index: Int)? {
        for (index, element) in enumerated() where element.matches(matcher, traitNames: traitNames) {
            return (element, index)
        }
        return nil
    }

    /// Whether any element in the flat array satisfies the matcher.
    func hasMatch(
        _ matcher: ElementMatcher,
        traitNames: @escaping (UIAccessibilityTraits) -> [String]
    ) -> Bool {
        contains { $0.matches(matcher, traitNames: traitNames) }
    }
}

// MARK: - TheBagman Convenience

extension TheBagman {

    /// Search cachedElements for the first match. Returns the element and its
    /// traversal index, or nil if no match.
    func findMatch(_ matcher: ElementMatcher) -> (element: AccessibilityElement, index: Int)? {
        cachedElements.firstMatch(matcher, traitNames: traitNames)
    }

    /// Whether any cached element matches the predicate.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        cachedElements.hasMatch(matcher, traitNames: traitNames)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

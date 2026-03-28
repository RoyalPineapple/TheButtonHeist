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

extension AccessibilityContainer {

    /// Does this container satisfy the non-trait property predicates in the matcher?
    /// Containers only carry label/value/identifier (via `semanticGroup`), so
    /// trait predicates always fail — a container has no UIAccessibilityTraits.
    func matches(_ matcher: ElementMatcher) -> Bool {
        let (label, value, identifier): (String?, String?, String?) = {
            if case .semanticGroup(let l, let v, let id) = type {
                return (l, v, id)
            }
            return (nil, nil, nil)
        }()
        if let matchLabel = matcher.label, label != matchLabel { return false }
        if let matchIdentifier = matcher.identifier, identifier != matchIdentifier { return false }
        if let matchValue = matcher.value, value != matchValue { return false }
        // Containers have no traits — any trait requirement is an automatic miss.
        if matcher.traits != nil, matcher.traits?.isEmpty == false { return false }
        return true
    }
}

extension AccessibilityHierarchy {

    /// Match result: the element or container that matched, plus its traversal index.
    /// Container matches use `traversalIndex: -1` since containers don't have
    /// a position in VoiceOver traversal order.
    struct MatchResult {
        let element: AccessibilityElement?
        let container: AccessibilityContainer?
        let traversalIndex: Int

        /// The label of whatever matched (element or container).
        var label: String? {
            if let element { return element.label }
            if let container, case .semanticGroup(let l, _, _) = container.type { return l }
            return nil
        }
    }

    /// Check if the node at this position satisfies the matcher's property predicates.
    /// Which node types are evaluated depends on `matcher.resolvedScope`.
    func matches(
        _ matcher: ElementMatcher,
        traitNames: (UIAccessibilityTraits) -> [String]
    ) -> MatchResult? {
        let scope = matcher.resolvedScope
        switch self {
        case .element(let element, let traversalIndex):
            guard scope == .elements || scope == .both else { return nil }
            if element.matches(matcher, traitNames: traitNames) {
                return MatchResult(element: element, container: nil, traversalIndex: traversalIndex)
            }
            return nil
        case .container(let container, let children):
            if scope == .containers || scope == .both,
               container.matches(matcher) {
                return MatchResult(element: nil, container: container, traversalIndex: -1)
            }
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
        let scope = matcher.resolvedScope
        for node in self {
            switch node {
            case .element(let element, let traversalIndex):
                if scope == .elements || scope == .both,
                   element.matches(matcher, traitNames: traitNames) {
                    results.append(.init(element: element, container: nil, traversalIndex: traversalIndex))
                }
            case .container(let container, let children):
                if scope == .containers || scope == .both,
                   container.matches(matcher) {
                    results.append(.init(element: nil, container: container, traversalIndex: -1))
                }
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

    /// Search cachedElements for the first match. Returns the element and its
    /// traversal index, or nil if no match. Throws if the matcher contains a heistId
    /// (heistId resolution requires ActionTarget, not ElementMatcher).
    func findMatch(_ matcher: ElementMatcher) throws -> (element: AccessibilityElement, index: Int)? {
        guard matcher.heistId == nil else { throw MatchingError.heistIdNotSupported }
        return cachedElements.firstMatch(matcher, traitNames: traitNames)
    }

    /// Whether any cached element matches the predicate.
    func hasMatch(_ matcher: ElementMatcher) -> Bool {
        cachedElements.hasMatch(matcher, traitNames: traitNames)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

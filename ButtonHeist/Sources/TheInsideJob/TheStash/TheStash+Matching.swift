#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
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
        let traits: AccessibilityTraits
        let geometryDisambiguationFrame: CGRect?
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
            geometryDisambiguationFrame: frame
        )
    }
}

// MARK: - Hierarchy-Level Element Matching

/// Matching operates on the canonical accessibility tree — AccessibilityElement
/// and AccessibilityHierarchy — not on wire types. Trait name strings from
/// ElementPredicate are resolved to parser trait bitmasks so comparisons
/// happen at the source data level.
///
/// The product contract is "exact or miss": all predicate resolution paths
/// (`matchScreenElements`, `hasTarget`, `HeistElement.matches`) use `.exact`.
/// `.substring` is reserved for the diagnostic / near-miss / suggestion path
/// — `Diagnostics.findNearMiss` uses it to surface "did you mean X?" hints
/// when an exact match fails. It must not leak back into the resolution path.

extension AccessibilityHierarchy {
    /// Match a single node against a predicate. For leaf elements, returns the match
    /// if the element satisfies the predicate. For containers, returns the first
    /// matching leaf descendant.
    func matches(_ predicate: ElementPredicate, mode: ElementPredicate.StringMatchMode) -> AccessibilityElement? {
        [self].firstMatch(predicate, mode: mode)
    }
}

extension Array where Element == AccessibilityHierarchy {

    /// First leaf element in the tree that satisfies all property predicates.
    func firstMatch(_ predicate: ElementPredicate, mode: ElementPredicate.StringMatchMode) -> AccessibilityElement? {
        matches(predicate, mode: mode, limit: 1).first
    }

    /// Leaf elements matching the predicate, stopping after `limit` results.
    /// Results are in tree traversal order. Use this for early-exit resolution:
    /// limit 1 for first-match, limit 2 for unique-match, limit N+1 for ordinal N.
    func matches(
        _ predicate: ElementPredicate,
        mode: ElementPredicate.StringMatchMode,
        limit: Int
    ) -> [AccessibilityElement] {
        guard limit > 0, predicate.hasPredicates else { return [] }
        return compactMap(first: limit, context: (), container: { _, _ in () }, element: { element, _, _ in
            predicate.matches(element, mode: mode) ? element : nil
        })
    }

    /// Whether any leaf element in the tree satisfies the property predicates.
    func hasMatch(_ predicate: ElementPredicate, mode: ElementPredicate.StringMatchMode) -> Bool {
        !matches(predicate, mode: mode, limit: 1).isEmpty
    }
}

// MARK: - AccessibilityElement Predicate Conformance

extension AccessibilityElement: ThePlans.ElementPredicateSubject {

    /// Known trait name strings — references the parser's authoritative set directly.
    private static let knownTraitNames = AccessibilityTraits.knownTraitNames

    public var predicateLabel: String? { label }
    public var predicateIdentifier: String? { identifier }
    public var predicateValue: String? { value }

    /// True when every required trait resolves to a known parser bitmask and is
    /// present on this element. Unknown trait names must cause a miss —
    /// `fromNames` drops them silently and `.contains(.none)` is always true, so
    /// each name is validated against the known set first.
    public func satisfiesRequiredTraits(_ required: [HeistTrait]) -> Bool {
        let requiredNames = required.map(\.rawValue)
        for name in requiredNames where !Self.knownTraitNames.contains(name) { return false }
        let mask = AccessibilityTraits.fromNames(requiredNames)
        return traits.contains(mask)
    }

    /// True when any excluded trait is present (or names an unknown trait — an
    /// unknown exclusion can never be proven absent, so it rejects the subject).
    public func violatesExcludedTraits(_ excluded: [HeistTrait]) -> Bool {
        let excludedNames = excluded.map(\.rawValue)
        for name in excludedNames where !Self.knownTraitNames.contains(name) { return true }
        let mask = AccessibilityTraits.fromNames(excludedNames)
        return !traits.isDisjoint(with: mask)
    }
}

// MARK: - TheStash Match Pipeline

extension TheStash {

    /// Single entry point for predicate-based element lookup. Returns up to `limit`
    /// matching ScreenElements using exact-or-miss semantics: case-insensitive
    /// equality with typography folding on string fields, exact bitmask comparison
    /// on traits. There is no substring matching path; a miss is a miss, and the agent
    /// gets structured suggestions through the `.notFound` diagnostic path. Matches
    /// are returned in the committed screen's semantic order: live hierarchy
    /// entries first, then known entries retained from exploration. Viewport
    /// reachability is handled by action execution, not by target resolution.
    func matchScreenElements(_ predicate: ElementPredicate, limit: Int) -> [ScreenElement] {
        matchScreenElements(predicate, limit: limit, in: settledScreen)
    }

    func matchScreenElements(
        _ predicate: ElementPredicate,
        limit: Int,
        in screen: Screen
    ) -> [ScreenElement] {
        guard limit > 0, predicate.hasPredicates else { return [] }
        var matches: [ScreenElement] = []
        matches.reserveCapacity(limit)
        for entry in selectElements(in: screen) where entry.matches(predicate, mode: .exact) {
            matches.append(entry)
            if matches.count == limit { break }
        }
        return matches
    }

}

private extension Screen.ScreenElement {
    func matches(_ predicate: ElementPredicate, mode: ElementPredicate.StringMatchMode) -> Bool {
        predicate.matches(element, mode: mode)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

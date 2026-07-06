#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

import AccessibilitySnapshotParser

// MARK: - Hierarchy-Level Element Matching

/// Matching operates on the canonical accessibility tree — AccessibilityElement
/// and AccessibilityHierarchy — not on wire types. Trait name strings from
/// ElementPredicate are resolved to parser trait bitmasks so comparisons
/// happen at the source data level.
///
/// The product contract is exact by default: plain string predicates such as
/// `.label("Pay")` are exact-or-miss, while authored `StringMatch` modes such
/// as `.label(.contains("Pay"))` are explicit broad matches. There is no hidden
/// automatic substring fallback.

extension AccessibilityHierarchy {
    /// Match a single node against a predicate. For leaf elements, returns the match
    /// if the element satisfies the predicate. For containers, returns the first
    /// matching leaf descendant.
    func matches(_ predicate: ElementPredicate) -> AccessibilityElement? {
        [self].firstMatch(predicate)
    }
}

extension Array where Element == AccessibilityHierarchy {

    /// First leaf element in the tree that satisfies all property predicates.
    func firstMatch(_ predicate: ElementPredicate) -> AccessibilityElement? {
        matches(predicate, limit: 1).first
    }

    /// Leaf elements matching the predicate, stopping after `limit` results.
    /// Results are in tree traversal order. Use this for early-exit resolution:
    /// limit 1 for first-match, limit 2 for unique-match, limit N+1 for ordinal N.
    func matches(
        _ predicate: ElementPredicate,
        limit: Int
    ) -> [AccessibilityElement] {
        guard limit > 0, predicate.hasPredicates else { return [] }
        return compactMap(first: limit, context: (), container: { _, _ in () }, element: { element, _, _ in
            predicate.matches(element) ? element : nil
        })
    }

    /// Whether any leaf element in the tree satisfies the property predicates.
    func hasMatch(_ predicate: ElementPredicate) -> Bool {
        !matches(predicate, limit: 1).isEmpty
    }
}

// MARK: - AccessibilityElement Predicate Conformance

extension AccessibilityElement: PredicateSelectionSubject {

    /// Known trait name strings — references the parser's authoritative set directly.
    private static let knownTraitNames = AccessibilityTraits.knownTraitNames

    package var predicateLabel: String? { label }
    package var predicateIdentifier: String? { identifier }
    package var predicateValue: String? { value }
    package var predicateHint: String? { hint }

    /// True when every required trait resolves to a known parser bitmask and is
    /// present on this element. Unknown trait names must cause a miss —
    /// `fromNames` drops them silently and `.contains(.none)` is always true, so
    /// each name is validated against the known set first.
    package func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool {
        let requiredNames = required.map(\.rawValue)
        for name in requiredNames where !Self.knownTraitNames.contains(name) { return false }
        let mask = AccessibilityTraits.fromNames(requiredNames)
        return traits.contains(mask)
    }

    package func satisfiesRequiredActions(_ required: Set<ElementAction>) -> Bool {
        required.isSubset(of: predicateActions)
    }

    package func containsCustomContent(matching match: CustomContentMatch<String>) -> Bool {
        customContent.contains { match.matches($0) }
    }

    package func satisfiesRequiredRotors(_ required: [StringMatch<String>]) -> Bool {
        let names = customRotors.map(\.name).filter { !$0.isEmpty }
        return required.allSatisfy { match in
            names.contains { match.matches($0) }
        }
    }

    package var predicateActions: Set<ElementAction> {
        let isInteractive = respondsToUserInteraction
            || !traits.isDisjoint(with: AccessibilityPolicy.interactiveTraitsBitmask)
            || !customActions.isEmpty
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let adjustable: [ElementAction] = (isInteractive && traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = customActions
            .map(\.name)
            .filter { !$0.isEmpty }
            .map(ElementAction.custom)
        return Set(activate + adjustable + custom)
    }

    package var predicateMatcherFacts: [AccessibilityMatcherFact] {
        AccessibilityPolicy.matcherFacts(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits.heistTraits
        )
    }
}

// MARK: - TheStash Match Pipeline

extension TheStash {

    /// Single entry point for predicate-based element lookup. Returns up to `limit`
    /// matching ScreenElements using authored predicate semantics: exact
    /// matching for plain strings, opt-in `contains`/`prefix`/`suffix` matching
    /// for broad `StringMatch` fields, and exact bitmask comparison on traits.
    /// There is no automatic substring fallback; a miss gets structured
    /// suggestions through the `.notFound` diagnostic path. Matches are
    /// returned in the committed screen's semantic order: live hierarchy
    /// entries first, then known entries retained from exploration. Viewport
    /// reachability is handled by action execution, not by target resolution.
    func matchScreenElements(_ predicate: ElementPredicate, limit: Int) -> [ScreenElement] {
        matchScreenElements(predicate, limit: limit, in: settledSemanticScreen)
    }

    func matchScreenElements(
        _ predicate: ElementPredicate,
        limit: Int,
        in screen: Screen
    ) -> [ScreenElement] {
        guard limit > 0, predicate.hasPredicates else { return [] }
        var matches: [ScreenElement] = []
        matches.reserveCapacity(limit)
        for entry in selectElements(in: screen) where entry.matches(predicate) {
            matches.append(entry)
            if matches.count == limit { break }
        }
        return matches
    }

    /// All matching screen elements in traversal order. Use when diagnostics
    /// need the exact match-set size rather than an early-exit prefix.
    func matchScreenElements(_ predicate: ElementPredicate, in screen: Screen) -> [ScreenElement] {
        guard predicate.hasPredicates else { return [] }
        return selectElements(in: screen).filter { $0.matches(predicate) }
    }

}

private extension Screen.ScreenElement {
    func matches(_ predicate: ElementPredicate) -> Bool {
        predicate.matches(element)
    }
}

struct AccessibilityElementPairingKey: Hashable {
    let text: String
    let identityTraits: Set<HeistTrait>

    init(_ element: AccessibilityElement) {
        text = [element.identifier, element.label]
            .compactMap { value in
                (value?.isEmpty == false) ? value : nil
            }
            .first ?? element.description
        identityTraits = Set(element.traits.heistTraits.filter {
            !AccessibilityPolicy.transientTraits.contains($0)
        })
    }
}

extension Sequence where Element == AccessibilityElement {
    func sharesElementPairing<Other: Sequence>(with other: Other) -> Bool where Other.Element == AccessibilityElement {
        let keys = Set(map(AccessibilityElementPairingKey.init))
        guard !keys.isEmpty else { return false }
        return other.contains { keys.contains(AccessibilityElementPairingKey($0)) }
    }
}

private extension CustomContentMatch where Value == String {
    func matches(_ content: AccessibilityElement.CustomContent) -> Bool {
        label.matches(content.label)
            && value.matches(content.value)
            && (isImportant.map { $0 == content.isImportant } ?? true)
    }
}

private extension Optional where Wrapped == StringMatch<String> {
    func matches(_ text: String) -> Bool {
        map { $0.matches(text) } ?? true
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

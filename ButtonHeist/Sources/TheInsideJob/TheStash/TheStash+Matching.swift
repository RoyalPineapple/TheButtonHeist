#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

import AccessibilitySnapshotParser

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

    package func containsCustomContent(matching match: CustomContentMatchCore<String>) -> Bool {
        customContent.contains {
            HeistCustomContent(projecting: $0) != nil && match.matches($0)
        }
    }

    package func satisfiesRequiredRotors(_ required: [StringMatchCore<String>]) -> Bool {
        let names = customRotors.map(\.name).filter { !$0.isEmpty }
        return required.allSatisfy { match in
            names.contains { ResolvedStringMatch(core: match).matches($0) }
        }
    }

    package var predicateActions: Set<ElementAction> {
        let isInteractive = respondsToUserInteraction
            || !traits.isDisjoint(with: AccessibilityPolicy.interactiveTraitsBitmask)
            || !customActions.isEmpty
        let activate: [ElementAction] = isInteractive ? [.activate] : []
        let textEntry: [ElementAction] = AccessibilityPolicy.supportsTextEntry(traits.heistTraits)
            ? [.typeText]
            : []
        let adjustable: [ElementAction] = (isInteractive && traits.contains(.adjustable))
            ? [.increment, .decrement]
            : []
        let custom = customActions
            .compactMap { try? CustomActionName(validating: $0.name) }
            .map(ElementAction.custom)
        return Set(activate + textEntry + adjustable + custom)
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

extension InterfaceTree.Element: ElementPredicateSubjectBacked {
    package var predicateSubject: AccessibilityElement { element }
}

private extension CustomContentMatchCore where Text == String {
    func matches(_ content: AccessibilityElement.CustomContent) -> Bool {
        label.matches(content.label)
            && value.matches(content.value)
            && (isImportant.map { $0 == content.isImportant } ?? true)
    }
}

private extension Optional where Wrapped == StringMatchCore<String> {
    func matches(_ text: String) -> Bool {
        map { ResolvedStringMatch(core: $0).matches(text) } ?? true
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

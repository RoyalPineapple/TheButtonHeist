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
        customContent.contains { match.matches($0) }
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

extension LiveCapture.LiveElementEntry: ElementPredicateSubjectBacked {
    package var predicateSubject: AccessibilityElement { element }
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
    func matchScreenElements(_ predicate: ElementPredicate, limit: Int) -> [InterfaceTree.Element] {
        matchScreenElements(predicate, limit: limit, in: interfaceTree)
    }

    func matchScreenElements(
        _ predicate: ElementPredicate,
        limit: Int,
        in tree: InterfaceTree
    ) -> [InterfaceTree.Element] {
        guard limit > 0, predicate.hasPredicates else { return [] }
        return Array(tree.orderedElements.lazy.filter { predicate.matches($0) }.prefix(limit))
    }

    /// All matching screen elements in traversal order. Use when diagnostics
    /// need the exact match-set size rather than an early-exit prefix.
    func matchScreenElements(_ predicate: ElementPredicate, in tree: InterfaceTree) -> [InterfaceTree.Element] {
        guard predicate.hasPredicates else { return [] }
        return tree.orderedElements.filter { predicate.matches($0) }
    }

    /// Match a resolved target without applying its terminal ordinal. Resolution
    /// owns ordinal selection so an out-of-range diagnostic retains the full
    /// ordered match set.
    func matchingTreeElements(
        for target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> [InterfaceTree.Element] {
        matchingTreeElements(
            for: target,
            among: tree.orderedElements,
            containers: tree.orderedContainers,
            containersByPath: tree.containers
        )
    }

    func elementCandidates(
        for target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> [InterfaceTree.Element] {
        elementCandidates(
            for: target,
            among: tree.orderedElements,
            containers: tree.orderedContainers,
            containersByPath: tree.containers
        )
    }

    /// Match containers in the tree's canonical path order without applying
    /// the terminal ordinal.
    func matchingTreeContainers(
        for target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> [InterfaceTree.Container] {
        matchingTreeContainers(
            for: target,
            among: tree.orderedContainers,
            containersByPath: tree.containers
        )
    }

    private func matchingTreeElements(
        for target: ResolvedAccessibilityTarget,
        among elements: [InterfaceTree.Element],
        containers: [InterfaceTree.Container],
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> [InterfaceTree.Element] {
        switch target {
        case .predicate(let predicate, _):
            return elements.filter { predicate.matches($0) }
        case .container:
            return []
        case .within(let containerPredicate, let nestedTarget):
            let matchingPaths = matchingContainerPaths(containerPredicate, among: containers)
            return matchingTreeElements(
                for: nestedTarget,
                among: elements.filter {
                    isContained($0, inAnyOf: matchingPaths, containersByPath: containersByPath)
                },
                containers: containers.filter {
                    isContained($0, inAnyOf: matchingPaths, containersByPath: containersByPath)
                },
                containersByPath: containersByPath
            )
        }
    }

    private func elementCandidates(
        for target: ResolvedAccessibilityTarget,
        among elements: [InterfaceTree.Element],
        containers: [InterfaceTree.Container],
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> [InterfaceTree.Element] {
        switch target {
        case .predicate:
            return elements
        case .container:
            return []
        case .within(let containerPredicate, let nestedTarget):
            let matchingPaths = matchingContainerPaths(containerPredicate, among: containers)
            return elementCandidates(
                for: nestedTarget,
                among: elements.filter {
                    isContained($0, inAnyOf: matchingPaths, containersByPath: containersByPath)
                },
                containers: containers.filter {
                    isContained($0, inAnyOf: matchingPaths, containersByPath: containersByPath)
                },
                containersByPath: containersByPath
            )
        }
    }

    private func matchingTreeContainers(
        for target: ResolvedAccessibilityTarget,
        among containers: [InterfaceTree.Container],
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> [InterfaceTree.Container] {
        switch target {
        case .predicate:
            return []
        case .container(let predicate, _):
            return containers.filter { predicate.matches($0.container.containerPredicateFacts) }
        case .within(let containerPredicate, let nestedTarget):
            let matchingPaths = matchingContainerPaths(containerPredicate, among: containers)
            return matchingTreeContainers(
                for: nestedTarget,
                among: containers.filter {
                    isContained($0, inAnyOf: matchingPaths, containersByPath: containersByPath)
                },
                containersByPath: containersByPath
            )
        }
    }

    private func matchingContainerPaths(
        _ predicate: ResolvedContainerPredicate,
        among containers: [InterfaceTree.Container]
    ) -> Set<TreePath> {
        Set(containers.lazy.filter {
            predicate.matches($0.container.containerPredicateFacts)
        }.map(\.path))
    }

    private func isContained(
        _ element: InterfaceTree.Element,
        inAnyOf containerPaths: Set<TreePath>,
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> Bool {
        isContained(
            parentPath: semanticParentPath(
                path: element.path,
                scrollMembership: element.scrollMembership,
                containersByPath: containersByPath
            ),
            inAnyOf: containerPaths,
            containersByPath: containersByPath
        )
    }

    private func isContained(
        _ container: InterfaceTree.Container,
        inAnyOf containerPaths: Set<TreePath>,
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> Bool {
        if containerPaths.contains(container.path) { return true }
        return isContained(
            parentPath: semanticParentPath(
                path: container.path,
                scrollMembership: container.scrollMembership,
                containersByPath: containersByPath
            ),
            inAnyOf: containerPaths,
            containersByPath: containersByPath
        )
    }

    private func isContained(
        parentPath: TreePath?,
        inAnyOf containerPaths: Set<TreePath>,
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> Bool {
        var path = parentPath
        var visited = Set<TreePath>()
        while let candidate = path, visited.insert(candidate).inserted {
            if containerPaths.contains(candidate) { return true }
            guard let container = containersByPath[candidate] else { return false }
            path = semanticParentPath(
                path: container.path,
                scrollMembership: container.scrollMembership,
                containersByPath: containersByPath
            )
        }
        return false
    }

    private func semanticParentPath(
        path: TreePath,
        scrollMembership: InterfaceTree.ScrollMembership?,
        containersByPath: [TreePath: InterfaceTree.Container]
    ) -> TreePath? {
        if let containerPath = scrollMembership?.containerPath,
           containersByPath[containerPath] != nil {
            return containerPath
        }

        var parent = path.parent
        while let candidate = parent {
            if candidate == .root { return nil }
            if containersByPath[candidate] != nil { return candidate }
            parent = candidate.parent
        }
        return nil
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

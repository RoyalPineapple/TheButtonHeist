#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import AccessibilitySnapshotParser

import TheScore

// MARK: - Target Resolution

extension TheVault {

    /// Which part of the interface state a lookup should read.
    enum InterfaceElementScope {
        case viewport
        case interface
    }

    enum ResolutionScope: String {
        case interface
        case provided
        case viewport
    }

    struct TargetCandidateFacts {
        let label: String?
        let identifier: String?
        let value: String?
        let isVisible: Bool
        let isReachable: Bool

        init(treeElement: InterfaceTree.Element, visibleHeistIds: Set<HeistId>) {
            let element = treeElement.element
            label = element.label
            identifier = element.identifier
            value = element.value
            isVisible = visibleHeistIds.contains(treeElement.heistId)
            isReachable = treeElement.scrollMembership != nil
        }
    }

    enum TargetNotFoundReason: Equatable {
        case ordinalOutOfRange(requested: Int, matchCount: Int)
        case noMatches
    }

    struct TargetNotFoundFacts {
        let predicate: ElementPredicate
        let ordinal: Int?
        let reason: TargetNotFoundReason
        let resolutionScope: ResolutionScope
        let treeElements: [InterfaceTree.Element]
        let visibleHeistIds: Set<HeistId>
        let exactMatches: [InterfaceTree.Element]
    }

    struct TargetAmbiguityFacts {
        let predicate: ElementPredicate
        let candidates: [TargetCandidateFacts]
        let matchedCount: Int
        let resolutionScope: ResolutionScope
        let exactMatches: [InterfaceTree.Element]
    }

    struct ContainerNotFoundFacts {
        let predicate: ResolvedContainerPredicate
        let ordinal: Int?
        let reason: TargetNotFoundReason
        let resolutionScope: ResolutionScope
        let exactMatches: [InterfaceTree.Container]
    }

    struct ContainerAmbiguityFacts {
        let predicate: ResolvedContainerPredicate
        let candidates: [InterfaceTree.Container]
        let matchedCount: Int
        let resolutionScope: ResolutionScope
    }

    /// Three-case result from `resolveTarget`. Resolution returns facts;
    /// diagnostic wording is projected separately.
    enum TargetResolution {
        case resolved(InterfaceTree.Element)
        case notFound(TargetNotFoundFacts)
        case ambiguous(TargetAmbiguityFacts)

        var resolved: InterfaceTree.Element? {
            if case .resolved(let resolved) = self { return resolved }
            return nil
        }

        var diagnostics: String {
            TargetResolutionDiagnostics.message(for: self)
        }

        var candidates: [String] {
            guard case .ambiguous(let facts) = self else { return [] }
            return facts.candidates.map(TargetResolutionDiagnostics.elementCandidateDescription)
        }
    }

    enum ContainerTargetResolution {
        case resolved(InterfaceTree.Container)
        case notFound(ContainerNotFoundFacts)
        case ambiguous(ContainerAmbiguityFacts)

        var diagnostics: String {
            TargetResolutionDiagnostics.message(for: self)
        }

        var candidates: [String] {
            guard case .ambiguous(let facts) = self else { return [] }
            return facts.candidates.map(TargetResolutionDiagnostics.containerCandidateDescription)
        }
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    ///
    /// Resolution reads the interface tree. If an element is absent,
    /// resolution fails with a near-miss suggestion. Live coordinate
    /// revalidation happens later in action execution.
    func resolveTarget(_ target: ResolvedAccessibilityTarget) -> TargetResolution {
        resolveTarget(target, in: interfaceTree, resolutionScope: .interface)
    }

    /// Resolve a target against a caller-provided tree during exploration.
    func resolveTarget(_ target: ResolvedAccessibilityTarget, in tree: InterfaceTree) -> TargetResolution {
        resolveTarget(target, in: tree, resolutionScope: .provided)
    }

    /// Resolve a target only against the committed interface viewport.
    ///
    /// A fresh parser read may supply UIKit evidence for an already-settled
    /// identity, but it cannot make new semantic state actionable before the
    /// observation stream commits it.
    func resolveVisibleTarget(_ target: ResolvedAccessibilityTarget) -> TargetResolution {
        resolveTarget(target, in: interfaceTree.viewportOnly, resolutionScope: .viewport)
    }

    func resolveContainerTarget(_ target: ResolvedAccessibilityTarget) -> ContainerTargetResolution {
        resolveContainerTarget(target, in: interfaceTree, resolutionScope: .interface)
    }

    func resolveContainerTarget(
        _ target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> ContainerTargetResolution {
        resolveContainerTarget(target, in: tree, resolutionScope: .provided)
    }

    func hasVisibleTerminalResolution(
        _ target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> Bool {
        let viewport = tree.viewportOnly
        if target.isElementTarget {
            switch resolveTarget(target, in: viewport) {
            case .resolved, .ambiguous:
                return true
            case .notFound:
                return false
            }
        }
        switch resolveContainerTarget(target, in: viewport) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    private func resolveContainerTarget(
        _ target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree,
        resolutionScope: ResolutionScope
    ) -> ContainerTargetResolution {
        guard case .container(let predicate, let ordinal) = target.terminalSelection else {
            preconditionFailure("container resolution requires a resolved container target")
        }
        let matches = AccessibilityTargetMatchGraph(targetMatchInput(for: tree))
            .matches(for: target)
            .containerPaths
            .compactMap { tree.containers[$0] }
        if let ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(ContainerNotFoundFacts(
                    predicate: predicate,
                    ordinal: ordinal,
                    reason: .ordinalOutOfRange(requested: ordinal, matchCount: matches.count),
                    resolutionScope: resolutionScope,
                    exactMatches: matches
                ))
            }
            return .resolved(matches[ordinal])
        }
        switch matches.count {
        case 1:
            return .resolved(matches[0])
        case 0:
            return .notFound(ContainerNotFoundFacts(
                predicate: predicate,
                ordinal: nil,
                reason: .noMatches,
                resolutionScope: resolutionScope,
                exactMatches: []
            ))
        default:
            return .ambiguous(ContainerAmbiguityFacts(
                predicate: predicate,
                candidates: matches,
                matchedCount: matches.count,
                resolutionScope: resolutionScope
            ))
        }
    }

    /// HeistIds for either the viewport or the full interface tree.
    func ids(in scope: InterfaceElementScope) -> Set<HeistId> {
        switch scope {
        case .viewport:
            return latestObservation.tree.viewportElementIDs
        case .interface:
            return interfaceTree.elementIDs
        }
    }

    /// Looks up an element by heistId in the selected scope.
    ///
    /// `.interface` reads the full interface tree, including any exploration union.
    /// `.visible` reads the latest observed parser output and only returns ids
    /// backed by the latest live hierarchy parse.
    func treeElement(heistId: HeistId, in scope: InterfaceElementScope) -> InterfaceTree.Element? {
        switch scope {
        case .viewport:
            return liveInterfaceElement(heistId: heistId)
        case .interface:
            return interfaceElement(heistId: heistId)
        }
    }

    /// Resolve a target using first-match semantics against the committed viewport.
    func resolveFirstVisibleMatch(_ target: ResolvedAccessibilityTarget) -> InterfaceTree.Element? {
        resolveVisibleTarget(target.firstMatchTarget).resolved
    }

    /// All elements in the supplied tree, or in the current interface tree when omitted.
    ///
    /// Live elements appear first in hierarchy (depth-first) traversal order;
    /// any interface heistIds not present in the viewport
    /// hierarchy (post-exploration union) appear after, sorted by heistId so
    /// the snapshot order is stable across runs.
    func selectElements(in tree: InterfaceTree? = nil) -> [InterfaceTree.Element] {
        if let tree {
            return tree.orderedElements
        }
        return orderedInterfaceElements
    }
}

private extension TheVault {

    func targetMatchInput(for tree: InterfaceTree) -> AccessibilityTargetMatchInput<InterfaceTree.Element> {
        let elements = tree.orderedElements
        let containers = tree.orderedContainers
        let containerPaths = Set(tree.containers.keys)
        return AccessibilityTargetMatchInput(
            elements: elements.enumerated().map { offset, entry in
                AccessibilityTargetElementMatch(
                    path: entry.path,
                    traversalOrder: offset,
                    parentContainerPath: AccessibilityTargetMatchInput<InterfaceTree.Element>.parentContainerPath(
                        for: entry.path,
                        preferred: entry.scrollMembership?.containerPath,
                        among: containerPaths
                    ),
                    element: entry
                )
            },
            containers: containers.map { entry in
                AccessibilityTargetContainerMatch(
                    path: entry.path,
                    parentContainerPath: AccessibilityTargetMatchInput<InterfaceTree.Element>.parentContainerPath(
                        for: entry.path,
                        preferred: entry.scrollMembership?.containerPath,
                        among: containerPaths
                    ),
                    facts: entry.container.containerPredicateFacts
                )
            }
        )
    }

    func resolveTarget(
        _ target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        guard case .element(let predicate, let ordinal) = target.terminalSelection else {
            preconditionFailure("element resolution requires a resolved element target")
        }
        let matchGraph = AccessibilityTargetMatchGraph(targetMatchInput(for: tree))
        let candidates = matchGraph.elementCandidates(in: target).elements
        let matches = matchGraph.matches(for: target).elements.elements
        if let ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(TargetNotFoundFacts(
                    predicate: predicate,
                    ordinal: ordinal,
                    reason: .ordinalOutOfRange(requested: ordinal, matchCount: matches.count),
                    resolutionScope: resolutionScope,
                    treeElements: candidates,
                    visibleHeistIds: tree.viewportElementIDs,
                    exactMatches: matches
                ))
            }
            return .resolved(matches[ordinal])
        }
        switch matches.count {
        case 0:
            return .notFound(TargetNotFoundFacts(
                predicate: predicate,
                ordinal: nil,
                reason: .noMatches,
                resolutionScope: resolutionScope,
                treeElements: candidates,
                visibleHeistIds: tree.viewportElementIDs,
                exactMatches: []
            ))
        case 1:
            return .resolved(matches[0])
        default:
            return .ambiguous(TargetAmbiguityFacts(
                predicate: predicate,
                candidates: matches.prefix(10).map {
                    TargetCandidateFacts(treeElement: $0, visibleHeistIds: tree.viewportElementIDs)
                },
                matchedCount: matches.count,
                resolutionScope: resolutionScope,
                exactMatches: matches
            ))
        }
    }
}

private extension ResolvedAccessibilityTarget {
    var firstMatchTarget: ResolvedAccessibilityTarget {
        switch self {
        case .predicate(let predicate, _):
            return .predicate(predicate, ordinal: 0)
        case .within(let container, let target):
            return .within(container: container, target: target.firstMatchTarget)
        case .container:
            return self
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

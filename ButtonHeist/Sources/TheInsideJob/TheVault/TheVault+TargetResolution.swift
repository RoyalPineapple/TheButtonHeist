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

    enum TargetMatch: Equatable {
        case element(InterfaceTree.Element)
        case container(InterfaceTree.Container)
    }

    struct TargetElementMatches: Equatable {
        let predicate: ResolvedElementPredicate
        let ordinal: Int?
        let candidates: [InterfaceTree.Element]
        let exactMatches: [InterfaceTree.Element]
        let visibleHeistIds: Set<HeistId>
    }

    struct TargetContainerMatches: Equatable {
        let predicate: ResolvedContainerPredicate
        let ordinal: Int?
        let exactMatches: [InterfaceTree.Container]
    }

    enum TargetMatchSet: Equatable {
        case elements(TargetElementMatches)
        case containers(TargetContainerMatches)

        var count: Int {
            switch self {
            case .elements(let matches): matches.exactMatches.count
            case .containers(let matches): matches.exactMatches.count
            }
        }

        var ordinal: Int? {
            switch self {
            case .elements(let matches): matches.ordinal
            case .containers(let matches): matches.ordinal
            }
        }

        func match(at index: Int) -> TargetMatch? {
            switch self {
            case .elements(let matches):
                guard matches.exactMatches.indices.contains(index) else { return nil }
                return .element(matches.exactMatches[index])
            case .containers(let matches):
                guard matches.exactMatches.indices.contains(index) else { return nil }
                return .container(matches.exactMatches[index])
            }
        }

        func resolve(in resolutionScope: ResolutionScope) -> TargetResolution {
            if let ordinal {
                guard let match = match(at: ordinal) else {
                    return .notFound(TargetNotFoundFacts(
                        reason: .ordinalOutOfRange(requested: ordinal, matchCount: count),
                        resolutionScope: resolutionScope,
                        matchSet: self
                    ))
                }
                return .resolved(match)
            }
            switch count {
            case 0:
                return .notFound(TargetNotFoundFacts(
                    reason: .noMatches,
                    resolutionScope: resolutionScope,
                    matchSet: self
                ))
            case 1:
                guard let match = match(at: 0) else {
                    preconditionFailure("one target match must resolve at index zero")
                }
                return .resolved(match)
            default:
                return .ambiguous(TargetAmbiguityFacts(
                    resolutionScope: resolutionScope,
                    matchSet: self
                ))
            }
        }
    }

    enum TargetNotFoundReason: Equatable {
        case ordinalOutOfRange(requested: Int, matchCount: Int)
        case noMatches
    }

    struct TargetNotFoundFacts: Equatable {
        let reason: TargetNotFoundReason
        let resolutionScope: ResolutionScope
        let matchSet: TargetMatchSet

        fileprivate init(
            reason: TargetNotFoundReason,
            resolutionScope: ResolutionScope,
            matchSet: TargetMatchSet
        ) {
            self.reason = reason
            self.resolutionScope = resolutionScope
            self.matchSet = matchSet
        }
    }

    struct TargetAmbiguityFacts: Equatable {
        let resolutionScope: ResolutionScope
        let matchSet: TargetMatchSet

        var matchedCount: Int { matchSet.count }

        fileprivate init(resolutionScope: ResolutionScope, matchSet: TargetMatchSet) {
            self.resolutionScope = resolutionScope
            self.matchSet = matchSet
        }
    }

    /// Cardinality classification for either an element or container match set.
    enum TargetResolution: Equatable {
        case resolved(TargetMatch)
        case notFound(TargetNotFoundFacts)
        case ambiguous(TargetAmbiguityFacts)

        var diagnostics: String {
            TargetResolutionDiagnostics.message(for: self)
        }
    }

    /// Resolve a target against the complete committed interface.
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

    func hasVisibleTerminalResolution(
        _ target: ResolvedAccessibilityTarget,
        in tree: InterfaceTree
    ) -> Bool {
        switch resolveTarget(target, in: tree.viewportOnly, resolutionScope: .viewport) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
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
    /// `.viewport` reads the latest observed parser output and only returns ids
    /// backed by the latest live hierarchy parse.
    func treeElement(heistId: HeistId, in scope: InterfaceElementScope) -> InterfaceTree.Element? {
        switch scope {
        case .viewport:
            return liveInterfaceElement(heistId: heistId)
        case .interface:
            return interfaceElement(heistId: heistId)
        }
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
        let graph = AccessibilityTargetMatchGraph(targetMatchInput(for: tree))
        let graphMatches = graph.matches(for: target)
        let matchSet: TargetMatchSet
        switch target.terminalSelection {
        case .element(let predicate, let ordinal):
            matchSet = .elements(TargetElementMatches(
                predicate: predicate,
                ordinal: ordinal,
                candidates: graph.elementCandidates(in: target).elements,
                exactMatches: graphMatches.elements.elements,
                visibleHeistIds: tree.viewportElementIDs
            ))
        case .container(let predicate, let ordinal):
            matchSet = .containers(TargetContainerMatches(
                predicate: predicate,
                ordinal: ordinal,
                exactMatches: graphMatches.containerPaths.compactMap { tree.containers[$0] }
            ))
        }
        return matchSet.resolve(in: resolutionScope)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import AccessibilitySnapshotParser

import TheScore

// MARK: - Target Resolution

extension TheStash {

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
        case ordinalNegative(Int)
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
    }

    struct TargetAmbiguityFacts {
        let predicate: ElementPredicate
        let candidates: [TargetCandidateFacts]
        let matchedCount: Int
        let resolutionScope: ResolutionScope
    }

    enum ContainerNotFoundReason: Equatable {
        case emptyPredicate
        case ordinalOutOfRange(requested: Int, matchCount: Int)
        case noMatches
    }

    struct ContainerNotFoundFacts {
        let predicate: ContainerPredicate
        let ordinal: Int?
        let reason: ContainerNotFoundReason
        let resolutionScope: ResolutionScope
    }

    struct ContainerAmbiguityFacts {
        let predicate: ContainerPredicate
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
    func resolveTarget(_ target: AccessibilityTarget) -> TargetResolution {
        resolveTarget(target, in: interfaceTree, resolutionScope: .interface)
    }

    /// Resolve a target against a caller-provided tree during exploration.
    func resolveTarget(_ target: AccessibilityTarget, in tree: InterfaceTree) -> TargetResolution {
        resolveTarget(target, in: tree, resolutionScope: .provided)
    }

    /// Resolve a target only against the committed interface viewport.
    ///
    /// A fresh parser read may supply UIKit evidence for an already-settled
    /// identity, but it cannot make new semantic state actionable before the
    /// observation stream commits it.
    func resolveVisibleTarget(_ target: AccessibilityTarget) -> TargetResolution {
        resolveTarget(target, in: interfaceTree.viewportOnly, resolutionScope: .viewport)
    }

    func resolveContainerTarget(_ predicate: ContainerPredicate, ordinal: Int?) -> ContainerTargetResolution {
        resolveContainerTarget(
            predicate,
            ordinal: ordinal,
            in: WireConversion.semanticInterfaceProjection(from: interfaceTree),
            resolutionScope: .interface
        )
    }

    private func resolveContainerTarget(
        _ predicate: ContainerPredicate,
        ordinal: Int?,
        in projection: SemanticInterfaceProjection,
        resolutionScope: ResolutionScope
    ) -> ContainerTargetResolution {
        guard predicate.hasPredicates else {
            return .notFound(ContainerNotFoundFacts(
                predicate: predicate,
                ordinal: ordinal,
                reason: .emptyPredicate,
                resolutionScope: resolutionScope
            ))
        }
        let matches = projection.containers(matching: predicate)
        if let ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(ContainerNotFoundFacts(
                    predicate: predicate,
                    ordinal: ordinal,
                    reason: .ordinalOutOfRange(requested: ordinal, matchCount: matches.count),
                    resolutionScope: resolutionScope
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
                resolutionScope: resolutionScope
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
            return latestObservation.viewportElementIDs
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
    func resolveFirstVisibleMatch(_ target: AccessibilityTarget) -> InterfaceTree.Element? {
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

private extension TheStash {

    func resolveTarget(
        _ target: AccessibilityTarget,
        in tree: InterfaceTree,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let projection = WireConversion.semanticInterfaceProjection(from: tree)
        return resolveTarget(target, in: projection, tree: tree, resolutionScope: resolutionScope)
    }

    func resolveTarget(
        _ target: AccessibilityTarget,
        in projection: SemanticInterfaceProjection,
        tree: InterfaceTree,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let treeElements = projection.treeElements(scopedBy: target)
        guard let selection = target.terminalSelection else {
            return .notFound(TargetNotFoundFacts(
                predicate: ElementPredicate(),
                ordinal: nil,
                reason: .noMatches,
                resolutionScope: resolutionScope,
                treeElements: treeElements,
                visibleHeistIds: tree.viewportElementIDs
            ))
        }
        if let ordinal = selection.ordinal, ordinal < 0 {
            return .notFound(TargetNotFoundFacts(
                predicate: selection.predicate,
                ordinal: ordinal,
                reason: .ordinalNegative(ordinal),
                resolutionScope: resolutionScope,
                treeElements: treeElements,
                visibleHeistIds: tree.viewportElementIDs
            ))
        }

        let matches = treeElements.filter { selection.predicate.matches($0.element) }
        if let ordinal = selection.ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(TargetNotFoundFacts(
                    predicate: selection.predicate,
                    ordinal: ordinal,
                    reason: .ordinalOutOfRange(requested: ordinal, matchCount: matches.count),
                    resolutionScope: resolutionScope,
                    treeElements: matches,
                    visibleHeistIds: tree.viewportElementIDs
                ))
            }
            return .resolved(matches[ordinal])
        }
        switch matches.count {
        case 0:
            return .notFound(TargetNotFoundFacts(
                predicate: selection.predicate,
                ordinal: nil,
                reason: .noMatches,
                resolutionScope: resolutionScope,
                treeElements: treeElements,
                visibleHeistIds: tree.viewportElementIDs
            ))
        case 1:
            return .resolved(matches[0])
        default:
            return .ambiguous(TargetAmbiguityFacts(
                predicate: selection.predicate,
                candidates: matches.prefix(10).map {
                    TargetCandidateFacts(treeElement: $0, visibleHeistIds: tree.viewportElementIDs)
                },
                matchedCount: matches.count,
                resolutionScope: resolutionScope
            ))
        }
    }
}

private struct TargetTerminalSelection {
    let predicate: ElementPredicate
    let ordinal: Int?
}

private extension AccessibilityTarget {
    var terminalSelection: TargetTerminalSelection? {
        switch self {
        case .predicate(let template, let ordinal):
            guard let predicate = try? template.resolve(in: .empty) else { return nil }
            return TargetTerminalSelection(
                predicate: predicate,
                ordinal: ordinal
            )
        case .within(_, let nestedTarget):
            guard let nestedSelection = nestedTarget.terminalSelection else { return nil }
            return TargetTerminalSelection(
                predicate: nestedSelection.predicate,
                ordinal: nestedSelection.ordinal
            )
        case .container, .ref:
            return nil
        }
    }

    var firstMatchTarget: AccessibilityTarget {
        switch self {
        case .predicate(let predicate, _):
            return .predicate(predicate, ordinal: 0)
        case .within(let container, let target):
            return .within(container: container, target: target.firstMatchTarget)
        case .container, .ref:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

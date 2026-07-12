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
        /// Elements in the observed live accessibility hierarchy from the most recent parse.
        case visible
        /// Elements retained in settled semantic truth, including an exploration union.
        case known
    }

    enum ResolutionScope: String {
        case known
        case provided
        case visible
    }

    struct TargetCandidateFacts {
        let label: String?
        let identifier: String?
        let value: String?
        let isVisible: Bool
        let isReachable: Bool

        init(screenElement: ScreenElement, visibleHeistIds: Set<HeistId>) {
            let element = screenElement.element
            label = element.label
            identifier = element.identifier
            value = element.value
            isVisible = visibleHeistIds.contains(screenElement.heistId)
            isReachable = screenElement.scrollMembership != nil
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
        let screenElements: [ScreenElement]
        let visibleHeistIds: Set<HeistId>
    }

    struct TargetAmbiguityFacts {
        let predicate: ElementPredicate
        let candidates: [TargetCandidateFacts]
        let matchedCount: Int
        let resolutionScope: ResolutionScope
    }

    struct ContainerCandidateFacts {
        let containerName: ContainerName?
        let type: AccessibilityContainerKind
        let label: String?
        let value: String?
        let identifier: String?
        let isModalBoundary: Bool

        init(container: SemanticScreen.Container) {
            let accessibilityContainer = container.container
            containerName = container.containerName
            let facts = accessibilityContainer.containerPredicateFacts
            type = facts.type
            label = facts.label
            value = facts.value
            identifier = facts.identifier
            isModalBoundary = accessibilityContainer.isModalBoundary
        }
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
        let candidates: [ContainerCandidateFacts]
        let matchedCount: Int
        let resolutionScope: ResolutionScope
    }

    /// Three-case result from `resolveTarget`. Resolution returns facts;
    /// diagnostic wording is projected separately.
    enum TargetResolution {
        case resolved(ScreenElement)
        case notFound(TargetNotFoundFacts)
        case ambiguous(TargetAmbiguityFacts)

        var resolved: ScreenElement? {
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
        case resolved(SemanticScreen.Container)
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
    /// Resolution reads settled semantic memory. If an element is not known,
    /// resolution fails with a near-miss suggestion. Live coordinate
    /// revalidation happens later in action execution.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: settledSemanticScreen, resolutionScope: .known)
    }

    /// Resolve a target against a caller-provided observation value. Used by
    /// exploration before its local semantic union has been committed.
    func resolveTarget(_ target: ElementTarget, in screen: Screen) -> TargetResolution {
        resolveTarget(target, in: screen, resolutionScope: .provided)
    }

    /// Resolve a target only against the latest live hierarchy. This preserves
    /// full target semantics (ambiguity and explicit ordinal) while excluding
    /// known-only entries retained from exploration.
    func resolveVisibleTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: liveVisibleScreen.visibleOnly, resolutionScope: .visible)
    }

    func resolveContainerTarget(_ predicate: ContainerPredicate, ordinal: Int?) -> ContainerTargetResolution {
        resolveContainerTarget(
            predicate,
            ordinal: ordinal,
            in: WireConversion.semanticInterfaceProjection(from: settledSemanticScreen),
            resolutionScope: .known
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
                candidates: matches.map(ContainerCandidateFacts.init),
                matchedCount: matches.count,
                resolutionScope: resolutionScope
            ))
        }
    }

    /// HeistIds for either the live hierarchy or the committed known screen.
    func ids(in scope: InterfaceElementScope) -> Set<HeistId> {
        switch scope {
        case .visible:
            return visibleElementIds
        case .known:
            return knownElementIds
        }
    }

    /// Looks up an element by heistId in the selected scope.
    ///
    /// `.known` reads settled semantic truth, including any exploration union.
    /// `.visible` reads the latest observed parser output and only returns ids
    /// backed by the latest live hierarchy parse.
    func screenElement(heistId: HeistId, in scope: InterfaceElementScope) -> ScreenElement? {
        switch scope {
        case .visible:
            return liveContains(heistId: heistId) ? liveScreenElement(heistId: heistId) : nil
        case .known:
            return knownElement(heistId: heistId)
        }
    }

    /// Resolve a target using first-match semantics against only the live hierarchy.
    func resolveFirstVisibleMatch(_ target: ElementTarget) -> ScreenElement? {
        resolveVisibleTarget(target.firstMatchTarget).resolved
    }

    /// All elements in the supplied screen, or in settled world when omitted.
    ///
    /// Live elements appear first in hierarchy (depth-first) traversal order;
    /// any known heistIds not present in the live
    /// hierarchy (post-exploration union) appear after, sorted by heistId so
    /// the snapshot order is stable across runs.
    func selectElements(in screen: Screen? = nil) -> [ScreenElement] {
        if let screen {
            return screen.orderedElements
        }
        return orderedSemanticElements
    }
}

private extension TheStash {

    func resolveTarget(
        _ target: ElementTarget,
        in screen: Screen,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let projection = WireConversion.semanticInterfaceProjection(from: screen)
        return resolveTarget(target, in: projection, screen: screen, resolutionScope: resolutionScope)
    }

    func resolveTarget(
        _ target: ElementTarget,
        in projection: SemanticInterfaceProjection,
        screen: Screen,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let selection = target.terminalSelection
        let screenElements = projection.screenElements(scopedBy: target)
        if let ordinal = selection.ordinal, ordinal < 0 {
            return .notFound(TargetNotFoundFacts(
                predicate: selection.predicate,
                ordinal: ordinal,
                reason: .ordinalNegative(ordinal),
                resolutionScope: resolutionScope,
                screenElements: screenElements,
                visibleHeistIds: screen.visibleIds
            ))
        }

        let matchGraph = ElementMatchGraph(interface: projection.interface)
        let matches = projection.screenElements(matching: matchGraph.resolve(selection.targetWithoutOrdinal))
        if let ordinal = selection.ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(TargetNotFoundFacts(
                    predicate: selection.predicate,
                    ordinal: ordinal,
                    reason: .ordinalOutOfRange(requested: ordinal, matchCount: matches.count),
                    resolutionScope: resolutionScope,
                    screenElements: matches,
                    visibleHeistIds: screen.visibleIds
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
                screenElements: screenElements,
                visibleHeistIds: screen.visibleIds
            ))
        case 1:
            return .resolved(matches[0])
        default:
            return .ambiguous(TargetAmbiguityFacts(
                predicate: selection.predicate,
                candidates: matches.prefix(10).map {
                    TargetCandidateFacts(screenElement: $0, visibleHeistIds: screen.visibleIds)
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
    let targetWithoutOrdinal: ElementTarget
}

private extension ElementTarget {
    var terminalSelection: TargetTerminalSelection {
        switch self {
        case .predicate(let predicate, let ordinal):
            return TargetTerminalSelection(
                predicate: predicate,
                ordinal: ordinal,
                targetWithoutOrdinal: .predicate(predicate)
            )
        case .within(let container, let nestedTarget):
            let nestedSelection = nestedTarget.terminalSelection
            return TargetTerminalSelection(
                predicate: nestedSelection.predicate,
                ordinal: nestedSelection.ordinal,
                targetWithoutOrdinal: .within(container, nestedSelection.targetWithoutOrdinal)
            )
        }
    }

    var firstMatchTarget: ElementTarget {
        switch self {
        case .predicate(let predicate, _):
            return .predicate(predicate, ordinal: 0)
        case .within(let container, let target):
            return .within(container, target.firstMatchTarget)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

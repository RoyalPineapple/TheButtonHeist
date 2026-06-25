#if canImport(UIKit)
#if DEBUG
import TheScore

/// Settled semantic world storage and commit adaptation.
///
/// `WorldStore` owns the durable semantic truth, the value-only settled
/// projection used for reads/traces, and the viewport metadata needed to apply
/// visible refresh semantics. Live capture remains owned by `TheStash`.
struct WorldStore {
    private var semanticWorld: SemanticScreen = .empty
    private var settledVisibleCapture: LiveCapture = .empty
    private var settledVisibleIds: Set<HeistId> = []

    var screen: Screen {
        Screen(semantic: semanticWorld, liveCapture: settledVisibleCapture)
    }

    var heistIds: Set<HeistId> {
        semanticWorld.heistIds
    }

    var elementCount: Int {
        semanticWorld.elements.count
    }

    var orderedElements: [SemanticScreen.Element] {
        screen.orderedElements
    }

    var containersInTraversalOrder: [SemanticScreen.Container] {
        semanticWorld.containers.values
            .sorted { $0.path.indices.lexicographicallyPrecedes($1.path.indices) }
    }

    var semanticHash: String {
        semanticWorld.semanticHash
    }

    var screenName: String? {
        screen.name
    }

    var screenId: String? {
        screen.id
    }

    func element(heistId: HeistId) -> SemanticScreen.Element? {
        semanticWorld.findElement(heistId: heistId)
    }

    mutating func reset() {
        semanticWorld = .empty
        settledVisibleCapture = .empty
        settledVisibleIds = []
    }

    @discardableResult
    @MainActor
    mutating func commitVisible(_ screen: Screen) -> CommitResult {
        commit(screenByRefreshingVisibleWorld(with: screen))
    }

    @discardableResult
    mutating func commitDiscovery(_ screen: Screen) -> CommitResult {
        commit(screen)
    }

    /// Apply visible settled refresh semantics without retaining UIKit handles.
    ///
    /// The previous settled visible ids are viewport metadata, not actionability
    /// state; they let a visible commit drop entries that vanished from the
    /// settled viewport while preserving discovery-only memory.
    @MainActor
    func screenByRefreshingVisibleWorld(with visibleRefresh: Screen) -> Screen {
        guard !visibleRefresh.visibleIds.isEmpty else {
            return visibleRefresh
        }
        if let settledScreenId = screen.id,
           let refreshScreenId = visibleRefresh.id,
           settledScreenId != refreshScreenId {
            return visibleRefresh
        }
        let knownOnlyIds = semanticWorld.heistIds.subtracting(settledVisibleIds)
        let refreshesKnownViewport = visibleRefreshBelongsToSettledViewport(
            visibleRefresh,
            knownOnlyIds: knownOnlyIds
        )
        guard refreshesKnownViewport else { return visibleRefresh }

        let disappearedVisibleIds = settledVisibleIds.subtracting(visibleRefresh.visibleIds)
        let mergedElements = semanticWorld.elements
            .merging(visibleRefresh.semantic.elements) { _, new in new }
            .filter { !disappearedVisibleIds.contains($0.key) }
        let mergedContainers = semanticWorld.containers
            .merging(visibleRefresh.semantic.containers) { _, new in new }
        return Screen(
            semantic: SemanticScreen(elements: mergedElements, containers: mergedContainers),
            liveCapture: visibleRefresh.liveCapture
        )
    }

    private mutating func commit(_ screen: Screen) -> CommitResult {
        semanticWorld = screen.semantic
        settledVisibleCapture = screen.liveCapture.strippingDispatchReferences()
        settledVisibleIds = screen.visibleIds
        return CommitResult(
            observedEvidence: screen,
            settledScreen: self.screen
        )
    }

    @MainActor
    private func visibleRefreshBelongsToSettledViewport(
        _ visibleRefresh: Screen,
        knownOnlyIds: Set<HeistId>
    ) -> Bool {
        if !settledVisibleIds.isDisjoint(with: visibleRefresh.visibleIds) {
            return true
        }
        if !knownOnlyIds.isEmpty && settledVisibleIds.isEmpty {
            return true
        }
        return visibleRefreshPairsWithSettledVisibleElements(visibleRefresh)
    }

    @MainActor
    private func visibleRefreshPairsWithSettledVisibleElements(_ visibleRefresh: Screen) -> Bool {
        let previous = settledVisibleIds
            .compactMap { semanticWorld.elements[$0]?.element }
            .map(TheStash.WireConversion.convert)
        let current = visibleRefresh.visibleIds
            .compactMap { visibleRefresh.semantic.elements[$0]?.element }
            .map(TheStash.WireConversion.convert)
        guard !previous.isEmpty, !current.isEmpty else { return false }

        let edits = ElementEdits.between(beforeElements: previous, afterElements: current)
        return !edits.updated.isEmpty
            || edits.removed.count < previous.count
            || edits.added.count < current.count
    }

    struct CommitResult {
        let observedEvidence: Screen
        let settledScreen: Screen
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

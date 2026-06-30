#if canImport(UIKit)
#if DEBUG
import TheScore

/// The brains of the operation — plans the play, sequences the crew.
///
/// TheBrains takes a command and works it through to a result by coordinating
/// TheStash (the screen value), TheSafecracker (gestures), and TheTripwire
/// (timing). Command dispatch, scroll/explore, action handlers, and
/// post-action observation are internal components with separate owners.
@MainActor
final class TheBrains {

    // User-facing copy for the typed accessibility-tree-unavailable result.
    nonisolated static let treeUnavailableMessage = "Could not access accessibility tree: no traversable app windows"
    nonisolated static let runtimeInactiveMessage = "ButtonHeist runtime is not active; start TheInsideJob before executing commands"

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let actions: Actions
    let postActionObservation: PostActionObservation
    let interactionObservation: InteractionObservation
    var semanticObservationIsActive = false
    private var changedWaitInProgress = false

    enum InterfaceObservation {
        case success(Interface)
        case failure(InterfaceObservationError)
    }

    enum InterfaceObservationError: Error, Equatable {
        case rootViewUnavailable
        case inactiveRuntime
        case selection(InterfaceSelectionError)

        var message: String {
            switch self {
            case .rootViewUnavailable:
                return "Could not access root view"
            case .inactiveRuntime:
                return TheBrains.runtimeInactiveMessage
            case .selection(let error):
                return error.message
            }
        }
    }

    init(tripwire: TheTripwire, fingerprintsEnabled: Bool = true) {
        self.tripwire = tripwire
        let stash = TheStash(tripwire: tripwire)
        let safecracker = TheSafecracker(fingerprintsEnabled: fingerprintsEnabled)
        self.stash = stash
        self.safecracker = safecracker
        let navigation = Navigation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire
        )
        self.navigation = navigation
        self.actions = Actions(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            navigation: navigation
        )
        let postActionObservation = PostActionObservation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            navigation: navigation
        )
        self.postActionObservation = postActionObservation
        self.interactionObservation = InteractionObservation(
            stash: stash,
            postActionObservation: postActionObservation
        )
    }

    func treeUnavailableResult(method: ActionMethod) -> ActionResult {
        var builder = ActionResultBuilder()
        if let diagnostic = stash.latestSemanticObservationFailureDiagnostic() {
            builder.message = "Could not observe accessibility tree; \(diagnostic)"
        } else {
            builder.message = TheBrains.treeUnavailableMessage
        }
        return builder.failure(method: method, errorKind: .accessibilityTreeUnavailable)
    }

    func runtimeInactiveResult(method: ActionMethod) -> ActionResult {
        var builder = ActionResultBuilder()
        builder.message = TheBrains.runtimeInactiveMessage
        return builder.failure(method: method, errorKind: .actionFailed)
    }

    // MARK: - Clear

    func clearCache() {
        stash.clearCache()
        navigation.clearCache()
    }

    // MARK: - Response State Tracking

    /// Response boundary hook retained for the wire lifecycle. Observation
    /// state now lives in the settled event stream, not in command-local
    /// baselines.
    func recordSentState() async {
        // Settled observation events carry their own previous observation and
        // delta, so the runtime no longer records a command-local baseline.
    }

    func stopSemanticObservation() {
        semanticObservationIsActive = false
        stash.stopPassiveSemanticObservation()
    }

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceObservation {
        guard semanticObservationIsActive else {
            return .failure(.inactiveRuntime)
        }
        guard let visibleEvidence = await stash.observeVisibleSemanticEvidence(timeout: 2.0) else {
            return .failure(.rootViewUnavailable)
        }

        let exploration = await navigation.exploreScreen(
            baseline: stash.visibleExplorationBaseline(from: visibleEvidence.screen),
            maxScrollsPerContainer: query.maxScrollsPerContainer,
            maxScrollsPerDiscovery: query.maxScrollsPerDiscovery
        )
        _ = stash.commitSettledDiscoveryWorld(exploration.screen)

        do {
            let interface = try InterfaceSelector(interface: stash.discoveryInterface()).select(query)
            let diagnostics = exploration.manifest.interfaceDiagnostics(
                for: exploration.screen,
                includedElementCount: interface.projectedElements.count
            )
            return .success(interface.withDiagnostics(diagnostics))
        } catch {
            return .failure(.selection(error))
        }
    }

    func beginChangedWait() -> Bool {
        guard !changedWaitInProgress else { return false }
        changedWaitInProgress = true
        return true
    }

    func finishChangedWait() {
        changedWaitInProgress = false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
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
    private var observationDriver = StateDriver(
        initial: ObservationRuntimePhase.inactive,
        machine: ObservationRuntimeMachine()
    )

    var semanticObservationIsActive: Bool {
        get { observationDriver.state.isObservationActive }
        set {
            _ = observationDriver.send(newValue ? .startObservation : .stopObservation)
        }
    }

    func capturedAnnouncements() -> AnnouncementListPayload {
        AnnouncementListPayload(announcements: stash.accessibilityNotifications.announcements())
    }

    private enum ObservationRuntimePhase: Equatable, Sendable {
        case inactive
        case observing
        case waitingForChange

        var isObservationActive: Bool {
            switch self {
            case .inactive:
                return false
            case .observing, .waitingForChange:
                return true
            }
        }
    }

    private enum ObservationRuntimeEvent: Equatable, Sendable {
        case startObservation
        case stopObservation
        case beginChangedWait
        case finishChangedWait
    }

    private enum ObservationRuntimeEffect: Equatable, Sendable {}
    private enum ObservationRuntimeRejection: Equatable, Sendable {
        case inactive
        case changedWaitAlreadyRunning
    }

    private struct ObservationRuntimeMachine: SimpleStateMachine {
        func advance(
            _ state: ObservationRuntimePhase,
            with event: ObservationRuntimeEvent
        ) -> StateChange<ObservationRuntimePhase, ObservationRuntimeEffect, ObservationRuntimeRejection> {
            switch (state, event) {
            case (.inactive, .startObservation):
                return .changed(to: .observing)
            case (.observing, .startObservation),
                 (.waitingForChange, .startObservation):
                return .changed(to: state)

            case (.inactive, .stopObservation):
                return .changed(to: .inactive)
            case (.observing, .stopObservation),
                 (.waitingForChange, .stopObservation):
                return .changed(to: .inactive)

            case (.observing, .beginChangedWait):
                return .changed(to: .waitingForChange)
            case (.waitingForChange, .beginChangedWait):
                return .rejected(.changedWaitAlreadyRunning, stayingIn: state)
            case (.inactive, .beginChangedWait):
                return .rejected(.inactive, stayingIn: state)

            case (.waitingForChange, .finishChangedWait):
                return .changed(to: .observing)
            case (.inactive, .finishChangedWait),
                 (.observing, .finishChangedWait):
                return .changed(to: state)
            }
        }
    }

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
        switch observationDriver.send(.beginChangedWait) {
        case .changed:
            return true
        case .rejected:
            return false
        }
    }

    func finishChangedWait() {
        observationDriver.send(.finishChangedWait)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

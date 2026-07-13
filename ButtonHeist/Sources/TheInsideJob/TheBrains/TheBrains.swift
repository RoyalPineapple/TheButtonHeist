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
    let failureEvidencePolicy: FailureEvidencePolicy
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

    enum InterfaceQueryResult {
        case success(Interface)
        case failure(InterfaceQueryFailure)
    }

    enum InterfaceQueryFailure: Error, Equatable {
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

        var errorKind: ErrorKind {
            switch self {
            case .rootViewUnavailable, .inactiveRuntime:
                return .accessibilityTreeUnavailable
            case .selection:
                return .validationError
            }
        }
    }

    init(
        tripwire: TheTripwire,
        fingerprintsEnabled: Bool = true,
        failureEvidencePolicy: FailureEvidencePolicy = .screenshot
    ) {
        self.tripwire = tripwire
        self.failureEvidencePolicy = failureEvidencePolicy
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
        let postActionObservation = PostActionObservation(stash: stash, safecracker: safecracker)
        self.postActionObservation = postActionObservation
        self.interactionObservation = InteractionObservation(
            stash: stash,
            postActionObservation: postActionObservation
        )
    }

    func treeUnavailableResult(method: ActionMethod) -> ActionResult {
        let message = stash.latestSemanticObservationFailureDiagnostic()
            .map { "Could not observe accessibility tree; \($0)" }
            ?? TheBrains.treeUnavailableMessage
        return .failure(
            method: method,
            errorKind: .accessibilityTreeUnavailable,
            message: message,
            evidence: .none
        )
    }

    func runtimeInactiveResult(method: ActionMethod) -> ActionResult {
        .failure(
            method: method,
            errorKind: .actionFailed,
            message: TheBrains.runtimeInactiveMessage,
            evidence: .none
        )
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

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceQueryResult {
        guard semanticObservationIsActive else {
            return .failure(.inactiveRuntime)
        }
        for _ in 0..<2 {
            guard let visibleEvidence = await stash.observeVisibleSemanticEvidence(timeout: 2.0),
                  let exploration = await navigation.exploreScreen(
                    baseline: stash.visibleExplorationBaseline(from: visibleEvidence.screen),
                    maxScrollsPerContainer: query.maxScrollsPerContainer,
                    maxScrollsPerDiscovery: query.maxScrollsPerDiscovery
                  ) else {
                return .failure(.rootViewUnavailable)
            }
            guard stash.semanticObservationStream.commitExploredDiscoveryObservation(exploration) != nil else {
                continue
            }

            do {
                let interface = try InterfaceSelector(interface: stash.discoveryInterface()).select(query)
                let diagnostics = exploration.manifest.interfaceDiagnostics(
                    for: exploration.screen,
                    includedElementCount: interface.projectedElements.count
                )
                return .success(interface
                    .withDiagnostics(diagnostics)
                    .withScreenActions(actions.availableScreenActions()))
            } catch {
                return .failure(.selection(error))
            }
        }
        return .failure(.rootViewUnavailable)
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

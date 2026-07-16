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
    private let requestExecutor = InteractionRequestExecutor()
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
            navigation: navigation,
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
        guard let visibleEvidence = await stash.observeVisibleSemanticEvidence(timeout: 2.0),
              let exploration = await navigation.exploreScreen(
                baseline: .currentViewport(
                    stash.visibleExplorationBaseline(from: visibleEvidence.screen)
                ),
                maxScrollsPerContainer: query.maxScrollsPerContainer,
                maxScrollsPerDiscovery: query.maxScrollsPerDiscovery,
              ) else {
            return .failure(.rootViewUnavailable)
        }

        do {
            let interface = try stash.selectInterface(query)
            let diagnostics = exploration.manifest.interfaceDiagnostics(
                for: exploration.event.observation.screen,
                includedElementCount: interface.projectedElements.count
            )
            return .success(interface
                .withDiagnostics(diagnostics)
                .withScreenActions(actions.availableScreenActions()))
        } catch {
            return .failure(.selection(error))
        }
    }

    func executeInAppRequest<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async -> Value
    ) async -> Value {
        switch await requestExecutor.execute(owner: .inApp, operation: operation) {
        case .completed(let value):
            return value
        case .cancelled:
            preconditionFailure("In-app requests cannot be cancelled by a transport owner")
        }
    }

    func submitTransportRequest(
        clientId: Int,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) async {
        _ = await requestExecutor.execute(owner: .transportClient(clientId), operation: operation)
    }

    func cancelTransportRequests(clientId: Int) {
        requestExecutor.cancel(owner: .transportClient(clientId))
    }

    func cancelAllTransportRequests() {
        requestExecutor.cancelTransportRequests()
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

@MainActor
private final class InteractionRequestExecutor {
    enum Owner: Equatable, Sendable {
        case inApp
        case transportClient(Int)

        var isTransport: Bool {
            if case .transportClient = self { return true }
            return false
        }
    }

    enum Outcome<Value: Sendable>: Sendable {
        case completed(Value)
        case cancelled
    }

    private struct PendingRequest {
        let id: UInt64
        let owner: Owner
        let operation: @MainActor @Sendable () async -> Void
        let cancelBeforeExecution: @MainActor @Sendable () -> Void
    }

    private struct ActiveRequest {
        let request: PendingRequest
        let task: Task<Void, Never>
    }

    private enum Phase {
        case idle
        case running(active: ActiveRequest, pending: [PendingRequest])
    }

    private var phase = Phase.idle
    private var nextRequestID: UInt64 = 1

    func execute<Value: Sendable>(
        owner: Owner,
        operation: @escaping @MainActor @Sendable () async -> Value
    ) async -> Outcome<Value> {
        guard !owner.isTransport || !Task.isCancelled else { return .cancelled }
        return await withCheckedContinuation { continuation in
            let requestID = nextRequestID
            precondition(requestID < UInt64.max, "Interaction request ID space exhausted")
            nextRequestID += 1
            enqueue(PendingRequest(
                id: requestID,
                owner: owner,
                operation: {
                    guard !Task.isCancelled else {
                        continuation.resume(returning: .cancelled)
                        return
                    }
                    continuation.resume(returning: .completed(await operation()))
                },
                cancelBeforeExecution: {
                    continuation.resume(returning: .cancelled)
                }
            ))
        }
    }

    func cancel(owner: Owner) {
        guard case .running(let active, let pending) = phase else { return }
        let cancelled = pending.filter { $0.owner == owner }
        let retained = pending.filter { $0.owner != owner }
        cancelled.forEach { $0.cancelBeforeExecution() }
        if active.request.owner == owner {
            active.task.cancel()
        }
        phase = .running(active: active, pending: retained)
    }

    func cancelTransportRequests() {
        guard case .running(let active, let pending) = phase else { return }
        let cancelled = pending.filter { $0.owner.isTransport }
        let retained = pending.filter { !$0.owner.isTransport }
        cancelled.forEach { $0.cancelBeforeExecution() }
        if active.request.owner.isTransport {
            active.task.cancel()
        }
        phase = .running(active: active, pending: retained)
    }

    private func enqueue(_ request: PendingRequest) {
        switch phase {
        case .idle:
            start(request, pending: [])
        case .running(let active, var pending):
            pending.append(request)
            phase = .running(active: active, pending: pending)
        }
    }

    private func start(_ request: PendingRequest, pending: [PendingRequest]) {
        let task = Task { @MainActor [weak self] in
            await request.operation()
            self?.complete(requestID: request.id)
        }
        phase = .running(
            active: ActiveRequest(request: request, task: task),
            pending: pending
        )
    }

    private func complete(requestID: UInt64) {
        guard case .running(let active, var pending) = phase,
              active.request.id == requestID else { return }
        guard !pending.isEmpty else {
            phase = .idle
            return
        }
        start(pending.removeFirst(), pending: pending)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

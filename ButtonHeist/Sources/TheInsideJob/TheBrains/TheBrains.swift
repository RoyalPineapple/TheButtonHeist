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
    private let requestExecutor: InteractionRequestExecutor
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
        failureEvidencePolicy: FailureEvidencePolicy = .screenshot,
        requestExecutor: InteractionRequestExecutor? = nil
    ) {
        self.tripwire = tripwire
        self.failureEvidencePolicy = failureEvidencePolicy
        self.requestExecutor = requestExecutor ?? InteractionRequestExecutor()
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
            message: message
        )
    }

    func runtimeInactiveResult(method: ActionMethod) -> ActionResult {
        .failure(
            method: method,
            errorKind: .actionFailed,
            message: TheBrains.runtimeInactiveMessage
        )
    }

    // MARK: - Clear

    func clearCache() {
        stash.clearCache()
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
                maxScrollsPerContainer: query.maxScrollsPerContainer?.value,
                maxScrollsPerDiscovery: query.maxScrollsPerDiscovery?.value,
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
    ) async -> InteractionRequestExecutor.Outcome<Value> {
        await withCheckedContinuation { continuation in
            requestExecutor.submit(
                owner: .inApp,
                operation: operation,
                completion: { continuation.resume(returning: $0) }
            )
        }
    }

    @discardableResult
    func submitTransportRequest(
        clientId: Int,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> InteractionRequestExecutor.Admission {
        requestExecutor.submit(
            owner: .transportClient(clientId),
            operation: operation,
            completion: { _ in }
        )
    }

    func cancelTransportRequests(clientId: Int) {
        requestExecutor.cancel(owner: .transportClient(clientId))
    }

    func stopInteractionRequests() async {
        await requestExecutor.drain()
    }

    var interactionRequestSnapshot: InteractionRequestExecutor.Snapshot {
        requestExecutor.snapshot
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

enum InteractionRequestExecutorPhase: Equatable, Sendable {
    case idle
    case running
    case cancelling
    case cleanupTimedOut
    case stopping
}

@MainActor
final class InteractionRequestExecutor {
    nonisolated static let maximumPendingRequests = 64
    nonisolated static let cleanupTimeout: Duration = .seconds(5)

    typealias CleanupDeadlineScheduler = @MainActor @Sendable (
        _ deadlineReached: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never>

    enum Owner: Equatable, Sendable {
        case inApp
        case transportClient(Int)

        var isTransport: Bool {
            if case .transportClient = self { return true }
            return false
        }
    }

    enum Rejection: Equatable, Sendable {
        case busy(capacity: Int)
        case cleanupTimedOut
        case stopping
    }

    enum Admission: Equatable, Sendable {
        case accepted
        case rejected(Rejection)
    }

    enum Outcome<Value: Sendable>: Sendable {
        case completed(Value)
        case cancelled
        case rejected(Rejection)
    }

    struct Snapshot: Equatable, Sendable {
        let phase: InteractionRequestExecutorPhase
        let pendingDepth: Int
        let capacity: Int
    }

    private struct PendingRequest {
        let id: UInt64
        let owner: Owner
        let operation: @MainActor @Sendable () async -> Void
        let cancel: @MainActor @Sendable () -> Void
    }

    private struct ActiveRequest {
        let request: PendingRequest
        let task: Task<Void, Never>
    }

    private struct CancellationState {
        let active: ActiveRequest
        var pending: [PendingRequest]
        var deadlineTask: Task<Void, Never>?
        var drainWaiters: [CheckedContinuation<Void, Never>]
        var deadlineExpired: Bool
    }

    private enum Phase {
        case idle
        case running(active: ActiveRequest, pending: [PendingRequest])
        case cancelling(CancellationState)
    }

    private let scheduleCleanupDeadline: CleanupDeadlineScheduler
    private var phase = Phase.idle
    private var nextRequestID: UInt64 = 1

    fileprivate convenience init() {
        self.init { deadlineReached in
            Task { @MainActor in await InteractionRequestExecutor.waitForCleanupDeadline(deadlineReached) }
        }
    }

    init(cleanupDeadlineScheduler: @escaping CleanupDeadlineScheduler) {
        scheduleCleanupDeadline = cleanupDeadlineScheduler
    }

    var snapshot: Snapshot {
        switch phase {
        case .idle:
            return Snapshot(phase: .idle, pendingDepth: 0, capacity: Self.maximumPendingRequests)
        case .running(_, let pending):
            return Snapshot(
                phase: .running,
                pendingDepth: pending.count,
                capacity: Self.maximumPendingRequests
            )
        case .cancelling(let state):
            let phase: InteractionRequestExecutorPhase
            if !state.drainWaiters.isEmpty {
                phase = .stopping
            } else if state.deadlineExpired {
                phase = .cleanupTimedOut
            } else {
                phase = .cancelling
            }
            return Snapshot(
                phase: phase,
                pendingDepth: state.pending.count,
                capacity: Self.maximumPendingRequests
            )
        }
    }

    private static func waitForCleanupDeadline(
        _ deadlineReached: @escaping @MainActor @Sendable () -> Void
    ) async {
        try? await Task.sleep(for: cleanupTimeout)
        guard !Task.isCancelled else { return }
        deadlineReached()
    }

    @discardableResult
    func submit<Value: Sendable>(
        owner: Owner,
        operation: @escaping @MainActor @Sendable () async -> Value,
        completion: @escaping @MainActor @Sendable (Outcome<Value>) -> Void
    ) -> Admission {
        let resolver = RequestResolver(completion)
        guard !owner.isTransport || !Task.isCancelled else {
            resolver.resolve(.cancelled)
            return .accepted
        }

        let requestID = nextRequestID
        nextRequestID &+= 1
        let request = PendingRequest(
            id: requestID,
            owner: owner,
            operation: {
                guard !Task.isCancelled else {
                    resolver.resolve(.cancelled)
                    return
                }
                resolver.resolve(.completed(await operation()))
            },
            cancel: { resolver.resolve(.cancelled) }
        )
        let admission = enqueue(request)
        if case .rejected(let rejection) = admission {
            resolver.resolve(.rejected(rejection))
        }
        return admission
    }

    func cancel(owner: Owner) {
        let pendingToCancel: [PendingRequest]
        let activeToCancel: ActiveRequest?
        switch phase {
        case .idle:
            return
        case .running(let active, let pending):
            let cancelled = pending.filter { $0.owner == owner }
            let retained = pending.filter { $0.owner != owner }
            pendingToCancel = cancelled
            if active.request.owner == owner {
                beginCancellation(active: active, pending: retained)
                activeToCancel = active
            } else {
                phase = .running(active: active, pending: retained)
                activeToCancel = nil
            }
        case .cancelling(var state):
            let cancelled = state.pending.filter { $0.owner == owner }
            state.pending.removeAll { $0.owner == owner }
            phase = .cancelling(state)
            pendingToCancel = cancelled
            activeToCancel = nil
        }
        resolveCancellation(for: pendingToCancel)
        if let activeToCancel {
            resolveCancellation(for: activeToCancel)
        }
    }

    func drain() async {
        guard case .idle = phase else {
            await withCheckedContinuation { continuation in
                beginDrain(continuation: continuation)
            }
            return
        }
    }

    private func enqueue(_ request: PendingRequest) -> Admission {
        switch phase {
        case .idle:
            start(request, pending: [])
            return .accepted
        case .running(let active, var pending):
            guard pending.count < Self.maximumPendingRequests else {
                return .rejected(.busy(capacity: Self.maximumPendingRequests))
            }
            pending.append(request)
            phase = .running(active: active, pending: pending)
            return .accepted
        case .cancelling(var state):
            guard state.drainWaiters.isEmpty else {
                return .rejected(.stopping)
            }
            guard !state.deadlineExpired else {
                return .rejected(.cleanupTimedOut)
            }
            guard state.pending.count < Self.maximumPendingRequests else {
                return .rejected(.busy(capacity: Self.maximumPendingRequests))
            }
            state.pending.append(request)
            phase = .cancelling(state)
            return .accepted
        }
    }

    private func start(_ request: PendingRequest, pending: [PendingRequest]) {
        let task = Task { @MainActor [weak self] in
            await request.operation()
            self?.complete(expected: request.id)
        }
        phase = .running(
            active: ActiveRequest(request: request, task: task),
            pending: pending
        )
    }

    private func complete(expected requestID: UInt64) {
        switch phase {
        case .idle:
            return
        case .running(let active, var pending):
            guard active.request.id == requestID else { return }
            guard !pending.isEmpty else {
                phase = .idle
                return
            }
            start(pending.removeFirst(), pending: pending)
        case .cancelling(let state):
            guard state.active.request.id == requestID else { return }
            state.deadlineTask?.cancel()
            if !state.drainWaiters.isEmpty {
                finishDrain(state.drainWaiters)
            } else if state.deadlineExpired || state.pending.isEmpty {
                phase = .idle
            } else {
                var pending = state.pending
                start(pending.removeFirst(), pending: pending)
            }
        }
    }

    private func beginDrain(
        continuation: CheckedContinuation<Void, Never>
    ) {
        switch phase {
        case .idle:
            continuation.resume()
        case .running(let active, let pending):
            resolveCancellation(for: pending)
            beginCancellation(active: active, pending: [], drainWaiters: [continuation])
            resolveCancellation(for: active)
        case .cancelling(var state):
            resolveCancellation(for: state.pending)
            state.pending.removeAll()
            state.drainWaiters.append(continuation)
            phase = .cancelling(state)
        }
    }

    private func beginCancellation(
        active: ActiveRequest,
        pending: [PendingRequest],
        drainWaiters: [CheckedContinuation<Void, Never>] = []
    ) {
        phase = .cancelling(CancellationState(
            active: active,
            pending: pending,
            deadlineTask: nil,
            drainWaiters: drainWaiters,
            deadlineExpired: false
        ))
        let requestID = active.request.id
        let deadlineTask = scheduleCleanupDeadline { [weak self] in
            self?.cleanupDeadlineReached(expected: requestID)
        }
        guard case .cancelling(var state) = phase,
              state.active.request.id == requestID else {
            deadlineTask.cancel()
            return
        }
        state.deadlineTask = deadlineTask
        phase = .cancelling(state)
    }

    private func cleanupDeadlineReached(expected requestID: UInt64) {
        guard case .cancelling(var state) = phase,
              state.active.request.id == requestID,
              !state.deadlineExpired else { return }
        let pending = state.pending
        state.pending.removeAll()
        state.deadlineTask = nil
        state.deadlineExpired = true
        phase = .cancelling(state)
        resolveCancellation(for: pending)
    }

    private func finishDrain(_ waiters: [CheckedContinuation<Void, Never>]) {
        phase = .idle
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func resolveCancellation(for active: ActiveRequest) {
        active.request.cancel()
        active.task.cancel()
    }

    private func resolveCancellation(for pending: [PendingRequest]) {
        pending.forEach { $0.cancel() }
    }

    @MainActor
    private final class RequestResolver<Value: Sendable> {
        private var completion: (@MainActor @Sendable (Outcome<Value>) -> Void)?

        init(_ completion: @escaping @MainActor @Sendable (Outcome<Value>) -> Void) {
            self.completion = completion
        }

        func resolve(_ outcome: Outcome<Value>) {
            guard let completion else { return }
            self.completion = nil
            completion(outcome)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

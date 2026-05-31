#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import os

import TheScore

/// Orchestrates client registration, admission, delivery, and disconnects.
private let muscleLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

actor TheMuscle {

    private static let disconnectGracePeriod: Duration = .milliseconds(100)
    private static let authDeadlineSeconds: UInt64 = 10
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 30

    private let sessionTokenSource: SessionTokenSource
    private var admission: TheMuscleAdmission
    private var session: TheMuscleSession
    private let alerts: AlertPresenter
    private var delivery: ClientDelivery = .unwired

    /// Outstanding "wait then disconnect" tasks.
    private let delayedDisconnectTasks = TaskTracker()

    /// Per-client pre-auth deadlines.
    private var authDeadlineTasks: [Int: Task<Void, Never>] = [:]

    /// Tasks spawned by `showApprovalAlert` across actor/MainActor isolation.
    private let pendingAlertTasks = TaskTracker()

    // MARK: - Init

    /// Caller must be on `@MainActor` because `AlertPresenter` is MainActor-isolated.
    @MainActor
    init(
        explicitToken: String?,
        sessionReleaseTimeout: TimeInterval? = nil,
        alerts: AlertPresenter? = nil
    ) {
        let tokenSource = SessionTokenSource(explicitToken: explicitToken)
        self.sessionTokenSource = tokenSource
        self.admission = TheMuscleAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: TheMuscle.maxFailedAttempts,
            lockoutDuration: TheMuscle.lockoutDuration
        )
        self.session = TheMuscleSession(
            releaseTimeout: sessionReleaseTimeout ?? StartupConfiguration.defaultSessionTimeout
        )
        self.alerts = alerts ?? AlertPresenter()
    }

    // MARK: - Test Seams

    /// Test seam: how many delayed-disconnect Tasks are currently tracked.
    var pendingLockoutTaskCount: Int { delayedDisconnectTasks.taskCountForTesting }

    /// Test seam: drop transport wiring to simulate a targeted-send race.
    func clearSendToClientForTest() {
        delivery.clearForTesting()
    }

    // MARK: - Session Accessors

    var sessionToken: String { sessionTokenSource.token }

    /// Driver identity that currently holds the session (nil = no active session).
    var activeSessionDriverId: String? {
        session.activeSessionDriverId
    }

    var exposedDriverId: String? {
        session.exposedDriverId
    }

    /// Client IDs belonging to the active session.
    var activeSessionConnections: Set<Int> {
        session.activeSessionConnections
    }

    /// Whether a driver session is currently active on this Inside Job instance.
    var isSessionActive: Bool {
        session.isSessionActive
    }

    /// Number of active connections participating in the session.
    var activeSessionConnectionCount: Int {
        session.activeSessionConnectionCount
    }

    // MARK: - Callback Wiring

    /// Install transport-facing callbacks. Called once by `TheGetaway.wireTransport`.
    func installCallbacks(
        sendToClient: @escaping @Sendable (Data, Int) async -> ServerSendOutcome,
        disconnectClient: @escaping @Sendable (Int) async -> Void,
        onClientAuthenticated: @escaping @MainActor @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void
    ) {
        delivery.install(ClientDelivery.Callbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnectClient,
            onClientAuthenticated: onClientAuthenticated
        ))
    }

    // MARK: - Public API

    /// Register the remote address for a client (called when TCP connection is established).
    func registerClientAddress(_ clientId: Int, address: String) {
        admission.registerClientAddress(clientId, address: address)
        replaceAuthenticationDeadline(for: clientId)
    }

    @discardableResult
    func sendServerHello(clientId: Int) async -> ServerSendOutcome {
        guard let data = encodeEnvelope(.serverHello) else {
            return .failed(.transportFailed(clientId: clientId, message: "Failed to encode serverHello"))
        }
        return await delivery.send(data, toClient: clientId)
    }

    /// Called when a ping is received from an authenticated client.
    func noteClientActivity(_ clientId: Int) {
        session.noteClientActivity(clientId, owner: self)
    }

    /// Send an already-encoded envelope to a single client.
    @discardableResult
    func sendData(_ data: Data, toClient clientId: Int) async -> ServerSendOutcome {
        guard admission.contains(clientId) else {
            return .failed(.clientNotFound(clientId))
        }
        return await delivery.send(data, toClient: clientId)
    }

    func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping @Sendable (Data) -> Void
    ) async -> ClientAdmission {
        await resolveAdmissionDecision(admission.admitClientMessage(
            clientId,
            data: data,
            respond: respond,
            uiApprovalUnavailableDiagnostic: session.uiApprovalUnavailableDiagnostic()
        ))
    }

    func handleClientDisconnected(_ clientId: Int) async {
        cancelAuthenticationDeadline(for: clientId)
        await applyAdmissionEffect(admission.removeClient(clientId))
        session.removeConnection(clientId, owner: self)
    }

    func approveClient(_ clientId: Int) async {
        guard let authentication = admission.approvalAuthentication(clientId) else { return }
        await completeAuthentication(authentication)
    }

    func denyClient(_ clientId: Int) async {
        await applyAdmissionEffect(admission.denyClient(clientId))
    }

    func tearDown() async {
        admission.removeAllClients()
        cancelAllAuthenticationDeadlines()
        delayedDisconnectTasks.cancelAll()
        pendingAlertTasks.cancelAll()
        await releaseSession()
        await dismissAlert()
    }

    // MARK: - Admission Orchestration

    private func resolveAdmissionDecision(_ decision: MuscleAdmissionDecision) async -> ClientAdmission {
        switch decision {
        case .admitted(let message):
            return .admitted(message)
        case .handled(let effect):
            await applyAdmissionEffect(effect)
            return .handled
        case .authenticate(let authentication):
            await completeAuthentication(authentication)
            return .handled
        }
    }

    private func completeAuthentication(_ authentication: MuscleAuthentication) async {
        switch session.acquire(
            driverIdentity: authentication.driverIdentity,
            clientId: authentication.clientId
        ) {
        case .accepted:
            let effect = admission.completeAuthentication(authentication)
            cancelAuthenticationDeadline(for: authentication.clientId)
            await applyAdmissionEffect(effect)
            _ = await delivery.clientAuthenticated(authentication.clientId, respond: authentication.respond)

        case .rejected(let diagnostic):
            await applyAdmissionEffect(admission.rejectForSessionLock(
                authentication.clientId,
                diagnostic: diagnostic,
                respond: authentication.respond
            ))
        }
    }

    private func applyAdmissionEffect(_ effect: MuscleAdmissionEffect) async {
        for output in effect.outputs {
            switch output {
            case .response(let message, let requestId, let respond):
                sendMessage(message, requestId: requestId, respond: respond)
            case .client(let message, let requestId, let clientId):
                if let data = encodeEnvelope(message, requestId: requestId) {
                    _ = await delivery.send(data, toClient: clientId)
                }
            }
        }

        if let clientId = effect.approvalPromptClientId {
            showApprovalAlert(clientId: clientId)
        }
        if effect.dismissApprovalPrompt {
            await dismissAlert()
        }
        if let clientId = effect.delayedDisconnectClientId {
            scheduleDelayedDisconnect(clientId)
        }
    }

    // MARK: - Delayed Disconnect

    /// Schedule a delayed disconnect so the recipient can flush the final error payload.
    private func scheduleDelayedDisconnect(_ clientId: Int) {
        cancelAuthenticationDeadline(for: clientId)
        delayedDisconnectTasks.spawn { [weak self] in
            guard await Task.cancellableSleep(for: TheMuscle.disconnectGracePeriod) else { return }
            await self?.fireDisconnect(clientId)
        }
    }

    private func fireDisconnect(_ clientId: Int) async {
        _ = await delivery.disconnect(clientId)
    }

    // MARK: - Authentication Deadline

    private func replaceAuthenticationDeadline(for clientId: Int) {
        cancelAuthenticationDeadline(for: clientId)
        authDeadlineTasks[clientId] = Task { [weak self] in
            guard await Task.cancellableSleep(for: .seconds(TheMuscle.authDeadlineSeconds)) else { return }
            await self?.handleAuthenticationDeadline(clientId)
        }
    }

    private func cancelAuthenticationDeadline(for clientId: Int) {
        authDeadlineTasks.removeValue(forKey: clientId)?.cancel()
    }

    private func cancelAllAuthenticationDeadlines() {
        for task in authDeadlineTasks.values {
            task.cancel()
        }
        authDeadlineTasks.removeAll()
    }

    private func handleAuthenticationDeadline(_ clientId: Int) async {
        cancelAuthenticationDeadline(for: clientId)
        await applyAdmissionEffect(admission.authenticationDeadline(
            clientId,
            deadlineSeconds: Self.authDeadlineSeconds
        ))
    }

    // MARK: - Session Release

    func sessionReleaseTimerFired() async {
        await releaseSession()
    }

    private func releaseSession() async {
        _ = session.release()
    }

    // MARK: - Alert Presentation

    /// Present the connection-approval UI for `clientId`.
    private func showApprovalAlert(clientId: Int) {
        let presenter = alerts
        let presentTask = Task { @MainActor [weak self] in
            presenter.presentApproval(
                clientId: clientId,
                onAllow: { [weak self] in
                    self?.scheduleApprovalCallback { muscle in
                        await muscle.approveClient(clientId)
                    }
                },
                onDeny: { [weak self] in
                    self?.scheduleApprovalCallback { muscle in
                        await muscle.denyClient(clientId)
                    }
                }
            )
        }
        recordAlertTask(presentTask)
    }

    /// Spawn a tracked Task that hops back to actor isolation to run an allow/deny handler.
    nonisolated private func scheduleApprovalCallback(_ body: @escaping @Sendable (TheMuscle) async -> Void) {
        let task = Task { [weak self] in
            guard let self else { return }
            await body(self)
        }
        recordAlertTask(task)
    }

    /// Insert a Task handle into the lock-protected tracking set. Safe to call from any isolation context.
    nonisolated private func recordAlertTask(_ task: Task<Void, Never>) {
        pendingAlertTasks.record(task)
    }

    private func dismissAlert() async {
        await alerts.dismiss()
    }

    // MARK: - Helpers

    func encodeEnvelope(_ message: ServerMessage, requestId: String? = nil) -> Data? {
        do {
            return try ResponseEnvelope(requestId: requestId, message: message).encoded()
        } catch {
            muscleLogger.error("Failed to encode message: \(error)")
            return nil
        }
    }

    private func sendMessage(
        _ message: ServerMessage,
        requestId: String? = nil,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        if let data = encodeEnvelope(message, requestId: requestId) {
            respond(data)
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import os

import TheScore

/// Manages client authentication, session token validation, and UI-based connection approval.
private let logger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

actor TheMuscle {

    private static let disconnectGracePeriod: Duration = .milliseconds(100)
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 30

    // MARK: - Properties

    /// Single source of truth for all per-client auth state. Absent = no such client.
    private var clientRegistry = TheMuscleClientRegistry()

    private let sessionTokenSource: SessionTokenSource
    private var admission: SessionAdmission
    private let alerts: AlertPresenter
    private var delivery: ClientDelivery = .unwired

    /// Outstanding "wait then disconnect" tasks.
    private let delayedDisconnectTasks = TaskTracker()

    /// Tasks spawned by `showApprovalAlert` across actor/MainActor isolation.
    private let pendingAlertTasks = TaskTracker()

    /// Test seam: how many delayed-disconnect Tasks are currently tracked.
    var pendingLockoutTaskCount: Int { delayedDisconnectTasks.taskCountForTesting }

    /// Test seam: install an authenticated client without a real transport handshake.
    func installAuthenticatedClientForTest(_ clientId: Int, address: String = "127.0.0.1", driverIdentity: String = "test-driver") {
        clientRegistry.installAuthenticatedForTest(clientId, address: address, driverIdentity: driverIdentity)
    }

    /// Test seam: drop transport wiring to simulate a targeted-send race.
    func clearSendToClientForTest() {
        self.delivery.clearForTesting()
    }

    // MARK: - Computed Client Accessors

    /// IDs of all authenticated clients.
    var authenticatedClientIDs: Set<Int> {
        clientRegistry.authenticatedClientIDs
    }

    /// Count of authenticated clients.
    var authenticatedClientCount: Int {
        clientRegistry.authenticatedClientCount
    }

    /// IDs of all clients that have completed the hello handshake (any phase past connected).
    var helloValidatedClients: Set<Int> {
        clientRegistry.helloValidatedClients
    }

    // MARK: - Session Lock State

    private var sessionLease: SessionLease
    var sessionToken: String { sessionTokenSource.token }

    // Computed accessors — preserve the external read interface.

    /// Driver identity that currently holds the session (nil = no active session).
    var activeSessionDriverId: String? {
        sessionLease.activeSessionDriverId
    }

    /// Client IDs belonging to the active session.
    var activeSessionConnections: Set<Int> {
        sessionLease.activeSessionConnections
    }

    private var hasPendingApproval: Bool {
        clientRegistry.hasPendingApproval
    }

    private var canRequestUIApproval: Bool {
        guard sessionTokenSource.allowsUIApproval, !hasPendingApproval else { return false }
        return !sessionLease.isSessionActive
    }

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
        self.admission = SessionAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: TheMuscle.maxFailedAttempts,
            lockoutDuration: TheMuscle.lockoutDuration
        )
        self.alerts = alerts ?? AlertPresenter()
        self.sessionLease = SessionLease(
            releaseTimeout: sessionReleaseTimeout ?? StartupConfiguration.defaultSessionTimeout
        )
    }

    // MARK: - Callback Wiring

    /// Install transport-facing callbacks. Called once by `TheGetaway.wireTransport`.
    func installCallbacks(
        sendToClient: @escaping @Sendable (Data, Int) async -> ServerSendOutcome,
        markClientAuthenticated: @escaping @Sendable (Int) async -> Void,
        markClientAwaitingApproval: @escaping @Sendable (Int) async -> Void = { _ in },
        disconnectClient: @escaping @Sendable (Int) async -> Void,
        onClientAuthenticated: @escaping @MainActor @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void,
        onSessionActiveChanged: @escaping @MainActor @Sendable (Bool) async -> Void
    ) {
        delivery.install(ClientDelivery.Callbacks(
            sendToClient: sendToClient,
            markClientAuthenticated: markClientAuthenticated,
            markClientAwaitingApproval: markClientAwaitingApproval,
            disconnectClient: disconnectClient,
            onClientAuthenticated: onClientAuthenticated,
            onSessionActiveChanged: onSessionActiveChanged
        ))
    }

    // MARK: - Public API

    /// Register the remote address for a client (called when TCP connection is established).
    func registerClientAddress(_ clientId: Int, address: String) {
        clientRegistry.registerAddress(clientId, address: address)
    }

    @discardableResult
    func sendServerHello(clientId: Int) async -> ServerSendOutcome {
        guard let data = encodeEnvelope(.serverHello) else {
            return .failed(.transportFailed(clientId: clientId, message: "Failed to encode serverHello"))
        }
        return await delivery.send(data, toClient: clientId)
    }

    /// Called when a ping is received from an authenticated client.
    /// Resets the session inactivity timer if the client belongs to the active session.
    func noteClientActivity(_ clientId: Int) {
        guard activeSessionConnections.contains(clientId) else { return }
        let releaseTimeout = sessionLease.releaseTimeout
        sessionLease.resetInactivityTimer { makeReleaseTimer(releaseTimeout: releaseTimeout) }
    }

    /// Send an already-encoded envelope to a single client.
    @discardableResult
    func sendData(_ data: Data, toClient clientId: Int) async -> ServerSendOutcome {
        guard clientRegistry.contains(clientId) else {
            return .failed(.clientNotFound(clientId))
        }
        return await delivery.send(data, toClient: clientId)
    }

    func handleUnauthenticatedMessage(_ clientId: Int, data: Data, respond: @escaping @Sendable (Data) -> Void) async {
        guard let envelope = decodeRequest(data) else {
            rejectUndecodableUnauthenticatedMessage(clientId, respond: respond)
            return
        }

        guard envelope.buttonHeistVersion == buttonHeistVersion else {
            sendMessage(
                .protocolMismatch(ProtocolMismatchPayload(
                    serverButtonHeistVersion: buttonHeistVersion,
                    clientButtonHeistVersion: envelope.buttonHeistVersion
                )),
                respond: respond
            )
            logger.warning("Client \(clientId) buttonHeistVersion mismatch: server=\(buttonHeistVersion), client=\(envelope.buttonHeistVersion)")
            scheduleDelayedDisconnect(clientId)
            return
        }

        switch envelope.message {
        case .clientHello:
            guard clientRegistry.markHelloValidated(clientId) != nil else {
                rejectUnauthenticatedMessage(
                    clientId,
                    message: "Connection is not registered; reconnect before starting the auth handshake.",
                    requestId: envelope.requestId,
                    respond: respond
                )
                return
            }
            sendMessage(.authRequired, respond: respond)
            return
        case .authenticate(let payload):
            guard clientRegistry.phase(for: clientId)?.hasCompletedHello == true else {
                rejectUnauthenticatedMessage(
                    clientId,
                    message: "Authentication requires client_hello first.",
                    requestId: envelope.requestId,
                    respond: respond
                )
                return
            }
            await processAuthentication(clientId, payload: payload, respond: respond)
            return
        default:
            rejectUnauthenticatedMessage(
                clientId,
                message: "Authentication required before \(envelope.message.canonicalName).",
                requestId: envelope.requestId,
                respond: respond
            )
            return
        }
    }

    private func rejectUndecodableUnauthenticatedMessage(
        _ clientId: Int,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        sendMessage(
            .error(ServerError(
                kind: .validationError,
                message: """
                    Could not decode client message before authentication. \
                    Check that the client and app are built from the same Button Heist version.
                    """
            )),
            respond: respond
        )
        logger.warning("Client \(clientId) sent unparsable message before authenticating")
        scheduleDelayedDisconnect(clientId)
    }

    private func rejectUnauthenticatedMessage(
        _ clientId: Int,
        message: String,
        requestId: String?,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        sendMessage(.error(ServerError(kind: .authFailure, message: message)), requestId: requestId, respond: respond)
        logger.warning("Client \(clientId) rejected before auth: \(message, privacy: .public)")
        scheduleDelayedDisconnect(clientId)
    }

    private func processAuthentication(_ clientId: Int, payload: AuthenticatePayload, respond: @escaping @Sendable (Data) -> Void) async {
        guard let phase = clientRegistry.phase(for: clientId) else {
            logger.warning("Client \(clientId) has no registered address, rejecting auth")
            sendMessage(.error(ServerError(kind: .authFailure, message: "Connection rejected.")), respond: respond)
            scheduleDelayedDisconnect(clientId)
            return
        }
        let address = phase.address

        if payload.token.isEmpty {
            switch admission.decideEmptyToken() {
            case .rejectExplicitTokenRequired(let error):
                sendMessage(.error(error), respond: respond)
                logger.warning("Client \(clientId) requested UI approval while an explicit token is configured")
                scheduleDelayedDisconnect(clientId)
                return
            case .requestUIApproval:
                break
            }

            guard canRequestUIApproval else {
                rejectUnavailableUIApprovalRequest(clientId, respond: respond)
                return
            }

            logger.info("Client \(clientId) requesting UI approval (no token)")
            clientRegistry.beginApproval(clientId, address: address, respond: respond, driverId: payload.driverId)
            _ = await delivery.markAwaitingApproval(clientId)
            sendMessage(.authApprovalPending(AuthApprovalPendingPayload()), respond: respond)
            showApprovalAlert(clientId: clientId)
            return
        }

        switch admission.decideToken(payload.token, driverId: payload.driverId, address: address) {
        case .lockedOut(let error):
            sendMessage(.error(error), respond: respond)
            logger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
            scheduleDelayedDisconnect(clientId)
            return

        case .rejected(let retryMessage, let attempts, let lockedOut):
            if lockedOut {
                logger.warning("Address \(address) locked out after \(attempts) failed attempts")
            }
            sendMessage(.error(ServerError(kind: .authFailure, message: retryMessage)), respond: respond)
            logger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
            scheduleDelayedDisconnect(clientId)
            return

        case .accepted(let driverIdentity):
            if !(await acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond)) {
                return
            }

            clientRegistry.authenticate(clientId, address: address, driverIdentity: driverIdentity)
            _ = await delivery.markAuthenticated(clientId)
            logger.info("Client \(clientId) authenticated with token")
            _ = await delivery.clientAuthenticated(clientId, respond: respond)
        }
    }

    private func rejectUnavailableUIApprovalRequest(
        _ clientId: Int,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        if let diagnostic = sessionLease.uiApprovalUnavailableDiagnostic() {
            rejectClientForSessionLock(
                clientId,
                diagnostic: diagnostic,
                respond: respond
            )
            return
        }

        sendMessage(
            .error(ServerError(
                kind: .authFailure,
                message: "UI approval is available only when no approval request is already active."
            )),
            respond: respond
        )
        logger.warning("Client \(clientId) requested UI approval while approval is already pending")
        scheduleDelayedDisconnect(clientId)
    }

    func handleClientDisconnected(_ clientId: Int) async {
        let removed = clientRegistry.remove(clientId)
        if case .pendingApproval = removed {
            await dismissAlert()
        }
        removeSessionConnection(clientId)
    }

    func approveClient(_ clientId: Int) async {
        guard case .pendingApproval(let address, let respond, let driverId) = clientRegistry.phase(for: clientId) else { return }

        let driverIdentity = sessionTokenSource.effectiveDriverId(driverId: driverId)
        if !(await acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond)) {
            return
        }

        clientRegistry.authenticate(clientId, address: address, driverIdentity: driverIdentity)
        _ = await delivery.markAuthenticated(clientId)
        logger.info("Client \(clientId) approved via UI")
        sendMessage(.authApproved(AuthApprovedPayload(token: sessionTokenSource.uiApprovalPayload)), respond: respond)
        _ = await delivery.clientAuthenticated(clientId, respond: respond)
    }

    func denyClient(_ clientId: Int) {
        guard case .pendingApproval(let address, let respond, _) = clientRegistry.phase(for: clientId) else { return }
        clientRegistry.restoreHelloValidated(clientId, address: address)
        sendMessage(.error(ServerError(kind: .authFailure, message: "Connection denied by user")), respond: respond)
        logger.info("Client \(clientId) denied via UI")
        scheduleDelayedDisconnect(clientId)
    }

    func tearDown() async {
        clientRegistry.removeAll()
        delayedDisconnectTasks.cancelAll()
        pendingAlertTasks.cancelAll()
        sessionLease.cancelTimerIfDraining()
        await releaseSession()
        await dismissAlert()
    }

    // MARK: - Delayed Disconnect

    /// Schedule a delayed disconnect so the recipient can flush the final error payload.
    private func scheduleDelayedDisconnect(_ clientId: Int) {
        delayedDisconnectTasks.spawn { [weak self] in
            guard await Task.cancellableSleep(for: TheMuscle.disconnectGracePeriod) else { return }
            await self?.fireDisconnect(clientId)
        }
    }

    /// Called from the delayed-disconnect Task body to actually fire the
    /// `disconnectClient` callback while inside actor isolation.
    private func fireDisconnect(_ clientId: Int) async {
        _ = await delivery.disconnect(clientId)
    }

    // MARK: - Status Accessors

    /// Whether a driver session is currently active on this Inside Job instance.
    var isSessionActive: Bool {
        sessionLease.isSessionActive
    }

    /// Number of active connections participating in the session.
    var activeSessionConnectionCount: Int {
        sessionLease.activeSessionConnectionCount
    }

    // MARK: - Session Lock

    /// Attempt to acquire the session for a client.
    private func acquireSession(driverIdentity: String, clientId: Int, respond: @escaping @Sendable (Data) -> Void) async -> Bool {
        switch sessionLease.acquire(driverIdentity: driverIdentity, clientId: clientId) {
        case .accepted(let notifyActiveChanged):
            if notifyActiveChanged {
                logger.info("Session claimed by client \(clientId)")
                _ = await delivery.sessionActiveChanged(true)
            } else {
                logger.info("Client \(clientId) rejoined session during grace period")
            }
            return true
        case .rejected(let diagnostic):
            rejectClientForSessionLock(clientId, diagnostic: diagnostic, respond: respond)
            return false
        }
    }

    private func rejectClientForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping @Sendable (Data) -> Void
    ) {
        let payload = diagnostic.payload()
        sendMessage(.sessionLocked(payload), respond: respond)
        logger.warning("Client \(clientId) rejected - \(payload.message, privacy: .public)")
        scheduleDelayedDisconnect(clientId)
    }

    private func releaseSession() async {
        if sessionLease.release() {
            logger.info("Session released")
            _ = await delivery.sessionActiveChanged(false)
        }
    }

    /// Remove a client from the active session. Transitions to draining if no connections remain.
    private func removeSessionConnection(_ clientId: Int) {
        let releaseTimeout = sessionLease.releaseTimeout
        if sessionLease.removeConnection(clientId, makeReleaseTimer: { makeReleaseTimer(releaseTimeout: releaseTimeout) }) {
            logger.info("All session connections gone, starting \(self.sessionLease.releaseTimeout)s release timer")
        }
    }

    /// Create a release timer task that fires after `sessionReleaseTimeout`.
    private func makeReleaseTimer(releaseTimeout: TimeInterval) -> Task<Void, Never> {
        Task { [weak self, releaseTimeout] in
            guard await Task.cancellableSleep(for: .seconds(releaseTimeout)) else { return }
            guard !Task.isCancelled else { return }
            await self?.releaseSession()
        }
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

    /// Insert a Task handle into the lock-protected tracking set. Safe to
    /// call from any isolation context.
    nonisolated private func recordAlertTask(_ task: Task<Void, Never>) {
        pendingAlertTasks.record(task)
    }

    private func dismissAlert() async {
        await alerts.dismiss()
    }

    // MARK: - Helpers

    func clientIDs(for driverIdentity: String) -> [Int] {
        clientRegistry.clientIDs(for: driverIdentity)
    }

    func encodeEnvelope(_ message: ServerMessage, requestId: String? = nil) -> Data? {
        do {
            return try ResponseEnvelope(requestId: requestId, message: message).encoded()
        } catch {
            logger.error("Failed to encode message: \(error)")
            return nil
        }
    }

    func decodeRequest(_ data: Data) -> RequestEnvelope? {
        do {
            return try RequestEnvelope.decoded(from: data)
        } catch {
            logger.error("Failed to decode client message: \(error)")
            return nil
        }
    }

    private func sendMessage(_ message: ServerMessage, requestId: String? = nil, respond: @escaping @Sendable (Data) -> Void) {
        if let data = encodeEnvelope(message, requestId: requestId) {
            respond(data)
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

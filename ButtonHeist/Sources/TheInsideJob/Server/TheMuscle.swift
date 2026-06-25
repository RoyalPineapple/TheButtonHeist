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
    private var delivery: ClientDelivery = .unwired
    private var sessionReleaseTimer: Task<Void, Never>?
    private var sessionReleaseTimerGeneration: UInt64 = 0

    private let delayedDisconnects = MuscleDelayedDisconnects(
        gracePeriod: TheMuscle.disconnectGracePeriod
    )
    private let authenticationDeadlines = MuscleAuthenticationDeadlines(
        deadline: .seconds(TheMuscle.authDeadlineSeconds)
    )

    // MARK: - Init

    /// Caller must be on `@MainActor` because runtime assembly is MainActor-isolated.
    @MainActor
    init(
        explicitToken: String?,
        sessionReleaseTimeout: TimeInterval
    ) {
        let tokenSource = SessionTokenSource(explicitToken: explicitToken)
        self.sessionTokenSource = tokenSource
        self.admission = TheMuscleAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: TheMuscle.maxFailedAttempts,
            lockoutDuration: TheMuscle.lockoutDuration
        )
        self.session = TheMuscleSession(
            releaseTimeout: sessionReleaseTimeout
        )
    }

    // MARK: - Test Seams

    /// Test seam: how many delayed-disconnect Tasks are currently tracked.
    var pendingLockoutTaskCount: Int { delayedDisconnects.taskCountForTesting }

    /// Test seam: drop transport wiring to simulate a targeted-send race.
    func clearSendToClientForTest() {
        delivery.clearForTesting()
    }

    /// Test seam: wait for the currently scheduled session release timer.
    func awaitSessionReleaseTimerForTesting() async {
        let timer = sessionReleaseTimer
        await timer?.value
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
        applySessionReleaseTimerAction(session.noteClientActivity(clientId))
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
            respond: respond
        ))
    }

    func handleClientDisconnected(_ clientId: Int) async {
        cancelAuthenticationDeadline(for: clientId)
        await applyAdmissionEffect(admission.removeClient(clientId))
        applySessionReleaseTimerAction(session.removeConnection(clientId))
    }

    func tearDown() async {
        admission.removeAllClients()
        cancelAllAuthenticationDeadlines()
        delayedDisconnects.cancelAll()
        await releaseSession()
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
        case .accepted(let acceptance):
            applySessionReleaseTimerAction(acceptance.releaseTimerAction)
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

        if let clientId = effect.delayedDisconnectClientId {
            scheduleDelayedDisconnect(clientId)
        }
    }

    // MARK: - Delayed Disconnect

    /// Schedule a delayed disconnect so the recipient can flush the final error payload.
    private func scheduleDelayedDisconnect(_ clientId: Int) {
        cancelAuthenticationDeadline(for: clientId)
        delayedDisconnects.schedule(clientId: clientId) { [weak self] in
            await self?.fireDisconnect(clientId)
        }
    }

    private func fireDisconnect(_ clientId: Int) async {
        _ = await delivery.disconnect(clientId)
    }

    // MARK: - Authentication Deadline

    private func replaceAuthenticationDeadline(for clientId: Int) {
        authenticationDeadlines.replace(for: clientId) { [weak self] in
            await self?.handleAuthenticationDeadline(clientId)
        }
    }

    private func cancelAuthenticationDeadline(for clientId: Int) {
        authenticationDeadlines.cancel(clientId)
    }

    private func cancelAllAuthenticationDeadlines() {
        authenticationDeadlines.cancelAll()
    }

    private func handleAuthenticationDeadline(_ clientId: Int) async {
        cancelAuthenticationDeadline(for: clientId)
        await applyAdmissionEffect(admission.authenticationDeadline(
            clientId,
            deadlineSeconds: Self.authDeadlineSeconds
        ))
    }

    // MARK: - Session Release

    private func sessionReleaseTimerFired(generation: UInt64) async {
        guard generation == sessionReleaseTimerGeneration else { return }
        await releaseSession()
    }

    private func releaseSession() async {
        applySessionReleaseTimerAction(session.release())
    }

    private func applySessionReleaseTimerAction(_ action: TheMuscleSession.ReleaseTimerAction) {
        switch action {
        case .none:
            break
        case .cancel:
            cancelSessionReleaseTimer()
        case .replace(let timeout):
            replaceSessionReleaseTimer(timeout: timeout)
        }
    }

    private func replaceSessionReleaseTimer(timeout: TimeInterval) {
        cancelSessionReleaseTimer()
        let generation = sessionReleaseTimerGeneration
        sessionReleaseTimer = Task { [weak self, timeout, generation] in
            guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
            guard !Task.isCancelled else { return }
            await self?.sessionReleaseTimerFired(generation: generation)
        }
    }

    private func cancelSessionReleaseTimer() {
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = nil
        sessionReleaseTimerGeneration &+= 1
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

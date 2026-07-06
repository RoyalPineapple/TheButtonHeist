#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
import UIKit
import os

import TheScore

/// Orchestrates client registration, admission, delivery, and disconnects.
private let muscleLogger = ButtonHeistLog.logger(.insideJob(.auth))

private struct SessionReleaseTimer {
    private enum State {
        case idle(generation: UInt64)
        case scheduled(task: Task<Void, Never>, generation: UInt64)
    }

    private var state: State = .idle(generation: 0)

    var task: Task<Void, Never>? {
        switch state {
        case .idle:
            return nil
        case .scheduled(let task, _):
            return task
        }
    }

    mutating func replace(
        timeout: TimeInterval,
        onExpired: @escaping @Sendable (UInt64) async -> Void
    ) {
        cancel()
        let scheduledGeneration = generation
        let task = Task { [timeout, scheduledGeneration] in
            guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
            guard !Task.isCancelled else { return }
            await onExpired(scheduledGeneration)
        }
        state = .scheduled(task: task, generation: scheduledGeneration)
    }

    mutating func cancel() {
        task?.cancel()
        state = .idle(generation: generation &+ 1)
    }

    func isCurrentScheduledGeneration(_ generation: UInt64) -> Bool {
        switch state {
        case .idle:
            return false
        case .scheduled(_, let scheduledGeneration):
            return scheduledGeneration == generation
        }
    }

    private var generation: UInt64 {
        switch state {
        case .idle(let generation), .scheduled(_, let generation):
            return generation
        }
    }
}

actor TheMuscle {

    private static let disconnectGracePeriod: Duration = .milliseconds(100)
    private static let authDeadlineSeconds: UInt64 = 10
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 30

    private let sessionTokenSource: SessionTokenSource
    private var admission: TheMuscleAdmission
    private var session: TheMuscleSession
    private var delivery: ClientDelivery = .unwired
    private var sessionReleaseTimer = SessionReleaseTimer()

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
        let timer = sessionReleaseTimer.task
        await timer?.value
    }

    /// Test seam: whether a session release timer is currently scheduled.
    var hasSessionReleaseTimerForTesting: Bool {
        sessionReleaseTimer.task != nil
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
    func sendServerHello(clientId: Int) async -> ResponseDeliveryResult {
        await sendResponse(.serverHello, to: .client(clientId))
    }

    /// Pings do not affect session ownership; release timers are tied to disconnect/rejoin transitions.
    func noteClientActivity(_: Int) {}

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
        await applyAdmissionEffects(admission.removeClient(clientId))
        applySessionEffects(session.removeConnection(clientId, at: Date()))
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
            await applyAdmissionEffects(effect)
            return .handled
        case .authenticate(let authentication):
            await completeAuthentication(authentication)
            return .handled
        }
    }

    private func completeAuthentication(_ authentication: MuscleAuthentication) async {
        switch session.acquire(
            driverIdentity: authentication.driverIdentity,
            clientId: authentication.clientId,
            at: Date()
        ) {
        case .accepted(let sessionEffect):
            applySessionEffects(sessionEffect)
            let effect = admission.completeAuthentication(authentication)
            cancelAuthenticationDeadline(for: authentication.clientId)
            await applyAdmissionEffects(effect)
            _ = await delivery.clientAuthenticated(authentication.clientId, respond: authentication.respond)

        case .rejected(let diagnostic):
            await applyAdmissionEffects(admission.rejectForSessionLock(
                authentication.clientId,
                diagnostic: diagnostic,
                respond: authentication.respond
            ))
        }
    }

    private func applyAdmissionEffects(_ effects: [MuscleAdmissionEffect]) async {
        for effect in effects {
            switch effect {
            case .sendResponse(let message, let requestId, let respond):
                await sendResponse(message, requestId: requestId, to: .response(respond))
            case .sendClient(let message, let requestId, let clientId):
                await sendResponse(message, requestId: requestId, to: .client(clientId))
            case .delayedDisconnect(let clientId):
                scheduleDelayedDisconnect(clientId)
            case .log(let event):
                logAdmissionEvent(event)
            }
        }
    }

    private func logAdmissionEvent(_ event: MuscleAdmissionLogEvent) {
        switch event {
        case .clientAuthenticatedWithToken(let clientId):
            muscleAuthenticationLogger.info("Client \(clientId) authenticated with token")
        case .sessionLockRejected(let clientId, let message):
            muscleAuthenticationLogger.warning("Client \(clientId) rejected - \(message, privacy: .public)")
        case .rateLimited(let clientId):
            muscleAuthenticationLogger.warning("Client \(clientId) rate limited, handling message")
        case .undecodableUnauthenticatedMessage(let clientId):
            muscleAuthenticationLogger.warning("Client \(clientId) sent unparsable message before authenticating")
        case .undecodableAuthenticatedMessage(let clientId):
            muscleAuthenticationLogger.warning("Authenticated client \(clientId) sent unparsable message")
        case .authenticatedProtocolMessage(let clientId, let wireType):
            muscleAuthenticationLogger.warning(
                "Authenticated client \(clientId) sent protocol message \(wireType.rawValue, privacy: .public) after admission"
            )
        case .unauthenticatedMessage(let clientId, let message):
            muscleAuthenticationLogger.warning("Client \(clientId) rejected before auth: \(message, privacy: .public)")
        case .authenticationDeadline(let clientId, let deadlineSeconds):
            muscleAuthenticationLogger.warning("Client \(clientId) did not authenticate within \(deadlineSeconds)s deadline")
        case .versionMismatch(let clientId, let serverVersion, let clientVersion):
            muscleAuthenticationLogger.warning(
                "Client \(clientId) buttonHeistVersion mismatch: server=\(serverVersion), client=\(clientVersion)"
            )
        case .missingRegisteredAddress(let clientId):
            muscleAuthenticationLogger.warning("Client \(clientId) has no registered address, rejecting auth")
        case .lockedOut(let clientId, let address):
            muscleAuthenticationLogger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
        case .invalidToken(let clientId, let attempts):
            muscleAuthenticationLogger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
        case .lockoutStarted(let address, let attempts):
            muscleAuthenticationLogger.warning("Address \(address) locked out after \(attempts) failed attempts")
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
        await applyAdmissionEffects(admission.authenticationDeadline(
            clientId,
            deadlineSeconds: Self.authDeadlineSeconds
        ))
    }

    // MARK: - Session Release

    private func sessionReleaseTimerFired(generation: UInt64) async {
        guard sessionReleaseTimer.isCurrentScheduledGeneration(generation) else { return }
        await releaseSession()
    }

    private func releaseSession() async {
        applySessionEffects(session.release())
    }

    private func applySessionEffects(_ effects: [TheMuscleSession.Effect]) {
        for effect in effects {
            switch effect {
            case .log(let event):
                logSessionEvent(event)
            case .cancelReleaseTimer:
                cancelSessionReleaseTimer()
            case .replaceReleaseTimer(let timeout):
                replaceSessionReleaseTimer(timeout: timeout)
            }
        }
    }

    private func logSessionEvent(_ event: TheMuscleSession.LogEvent) {
        switch event {
        case .sessionClaimed(let clientId):
            muscleLogger.info("Session claimed by client \(clientId)")
        case .clientRejoinedDuringGracePeriod(let clientId):
            muscleLogger.info("Client \(clientId) rejoined session during grace period")
        case .sessionReleased:
            muscleLogger.info("Session released")
        case .releaseTimerStarted(let timeout):
            muscleLogger.info("All session connections gone, starting \(timeout)s release timer")
        }
    }

    private func replaceSessionReleaseTimer(timeout: TimeInterval) {
        sessionReleaseTimer.replace(timeout: timeout) { [weak self] generation in
            await self?.sessionReleaseTimerFired(generation: generation)
        }
    }

    private func cancelSessionReleaseTimer() {
        sessionReleaseTimer.cancel()
    }

    // MARK: - Helpers

    func encodeEnvelope(
        _ message: ServerMessage,
        requestId: String? = nil
    ) -> Result<Data, ResponseEncodingFailure> {
        ResponseEnvelopeDelivery.encodeEnvelope(message, requestId: requestId)
    }

    private enum ResponseDestination: Sendable {
        case response(TheMuscleAdmission.ResponseHandler)
        case client(Int)
    }

    @discardableResult
    private func sendResponse(
        _ message: ServerMessage,
        requestId: String? = nil,
        to destination: ResponseDestination
    ) async -> ResponseDeliveryResult {
        let result: ResponseDeliveryResult
        switch destination {
        case .response(let respond):
            result = ResponseEnvelopeDelivery.sendMessage(message, requestId: requestId, respond: respond)

        case .client(let clientId):
            result = await sendResponseToClient(message, requestId: requestId, clientId: clientId)
        }
        logResponseDeliveryResult(result)
        return result
    }

    private func sendResponseToClient(
        _ message: ServerMessage,
        requestId: String?,
        clientId: Int
    ) async -> ResponseDeliveryResult {
        switch encodeEnvelope(message, requestId: requestId) {
        case .success(let data):
            switch await delivery.send(data, toClient: clientId) {
            case .enqueued:
                return .delivered
            case .failed(let failure):
                return ResponseDeliveryResult(clientId: clientId, sendFailure: failure)
            }

        case .failure(let failure):
            return .failed(.responseEncodingFailed(failure))
        }
    }

    private func logResponseDeliveryResult(_ result: ResponseDeliveryResult) {
        switch result {
        case .delivered:
            break
        case .refused(let failure), .failed(let failure):
            muscleLogger.error("\(failure.description)")
        case .transportUnavailable:
            muscleLogger.error("\(result.description)")
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

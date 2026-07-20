#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
import UIKit
import os

import TheScore

/// Orchestrates client registration, admission, delivery, and disconnects.
let muscleLogger = ButtonHeistLog.logger(.insideJob(.auth))

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
    private static let authTimeoutSeconds: UInt64 = 10
    private var admission: ClientAdmission.Reducer
    private var session: SessionLease
    private var delivery: ClientDelivery = .unwired
    private var sessionReleaseTimer = SessionReleaseTimer()

    private var delayedDisconnects = ClientAdmission.DelayedDisconnects(
        gracePeriod: TheMuscle.disconnectGracePeriod
    )
    private let authenticationTimeouts = ClientAdmission.Timeout.Deadlines(
        deadline: .seconds(TheMuscle.authTimeoutSeconds)
    )

    // MARK: - Init

    /// Caller must be on `@MainActor` because runtime assembly is MainActor-isolated.
    @MainActor
    init(
        sessionToken: SessionAuthToken,
        sessionReleaseTimeout: TimeInterval,
        authenticationPolicy: InsideJobAuthenticationPolicy = .default
    ) {
        self.admission = ClientAdmission.Reducer(
            sessionToken: sessionToken,
            authenticationPolicy: authenticationPolicy
        )
        self.session = SessionLease(
            releaseTimeout: sessionReleaseTimeout
        )
    }

    // MARK: - Test Seams

    /// Test seam: wait for the currently scheduled session release timer.
    func awaitSessionReleaseTimerForTesting() async {
        let timer = sessionReleaseTimer.task
        await timer?.value
    }

    /// Test seam: whether a session release timer is currently scheduled.
    var hasSessionReleaseTimerForTesting: Bool {
        sessionReleaseTimer.task != nil
    }

    /// Owner that currently holds the session (nil = no active session).
    var sessionOwner: SessionOwner? {
        session.activeSessionOwner
    }

    var exposedDriverId: DriverID? {
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

    var callbackDeliveryGenerationForTesting: ClientDelivery.Generation? {
        delivery.generation
    }

    // MARK: - Callback Wiring

    func beginCallbackWiring(_ generation: ClientDelivery.Generation) {
        delivery.begin(generation)
    }

    /// Install transport-facing callbacks. Called once by `TheGetaway.wireTransport`.
    @discardableResult
    func installCallbacks(
        sendToClient: @escaping @Sendable (Data, Int) async -> ServerSendOutcome,
        disconnectClient: @escaping @Sendable (Int) async -> Void,
        onClientAuthenticated: @escaping @MainActor @Sendable (Int, @escaping SocketResponseHandler) async -> Void,
        generation: ClientDelivery.Generation
    ) -> ClientDelivery.InstallOutcome {
        delivery.install(ClientDelivery.Callbacks(
            sendToClient: sendToClient,
            disconnectClient: disconnectClient,
            onClientAuthenticated: onClientAuthenticated
        ), for: generation)
    }

    func invalidateCallbacks(for generation: ClientDelivery.Generation) {
        delivery.invalidate(generation)
    }

    // MARK: - Public API

    /// Register the remote address for a client (called when TCP connection is established).
    func registerClientAddress(_ clientId: Int, address: ClientNetworkAddress) async {
        await executeAdmissionEffects(admission.registerClientAddress(clientId, address: address))
    }

    @discardableResult
    func sendServerHello(clientId: Int) async -> ResponseDeliveryOutcome {
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
        respond: @escaping SocketResponseHandler
    ) async -> ClientAdmission {
        await resolve(admission.admit(
            clientId,
            data: data,
            respond: respond
        ))
    }

    func handleClientDisconnected(_ clientId: Int) async {
        await executeAdmissionEffects(admission.removeClient(clientId))
        applySessionEffects(session.removeConnection(clientId, at: Date()))
    }

    func tearDown() async {
        delivery.reset()
        await executeAdmissionEffects(admission.removeAllClients())
        let disconnectGeneration = delayedDisconnects
        await disconnectGeneration.drain()
        if delayedDisconnects === disconnectGeneration {
            delayedDisconnects = ClientAdmission.DelayedDisconnects(gracePeriod: Self.disconnectGracePeriod)
        }
        await releaseSession()
    }

    // MARK: - Admission Orchestration

    private func resolve(_ decision: ClientAdmission.Decision) async -> ClientAdmission {
        switch decision {
        case .admitted(let message):
            return .admitted(message)
        case .handled(let effect):
            await executeAdmissionEffects(effect)
            return .handled
        case .sessionAdmission(let sessionAdmission):
            await admitSession(sessionAdmission)
            return .handled
        }
    }

    private func admitSession(_ sessionAdmission: ClientAdmission.SessionAdmission) async {
        switch session.acquire(
            owner: sessionAdmission.owner,
            clientId: sessionAdmission.clientId,
            at: Date()
        ) {
        case .accepted(let sessionEffect):
            applySessionEffects(sessionEffect)
            let effect = admission.completeAuthentication(sessionAdmission)
            await executeAdmissionEffects(effect)
            _ = await delivery.clientAuthenticated(sessionAdmission.clientId, respond: sessionAdmission.respond)

        case .rejected(let diagnostic):
            await executeAdmissionEffects(admission.rejectForSessionLock(
                sessionAdmission.clientId,
                diagnostic: diagnostic,
                respond: sessionAdmission.respond
            ))
        }
    }

    private func executeAdmissionEffects(_ effects: [ClientAdmission.Effect]) async {
        for effect in effects {
            switch effect {
            case .replaceAuthenticationDeadline(let clientId):
                authenticationTimeouts.replace(for: clientId) { [weak self] in
                    await self?.executeAuthenticationTimeout(clientId)
                }
            case .cancelAuthenticationDeadline(let clientId):
                authenticationTimeouts.cancel(clientId)
            case .cancelAllAuthenticationDeadlines:
                authenticationTimeouts.cancelAll()
            case .sendResponse(let message, let requestId, let respond):
                await sendResponse(message, requestId: requestId, to: .response(respond))
            case .sendClient(let message, let requestId, let clientId):
                await sendResponse(message, requestId: requestId, to: .client(clientId))
            case .delayedDisconnect(let clientId):
                authenticationTimeouts.cancel(clientId)
                scheduleDelayedDisconnect(clientId)
            case .log(let event):
                recordAdmissionLog(event)
            }
        }
    }

    private func recordAdmissionLog(_ event: ClientAdmission.Log) {
        switch event {
        case .clientAuthenticatedWithToken(let clientId):
            muscleLogger.info("Client \(clientId) authenticated with token")
        case .sessionLockRejected(let clientId, let message):
            muscleLogger.warning("Client \(clientId) rejected - \(message, privacy: .public)")
        case .rateLimited(let clientId):
            muscleLogger.warning("Client \(clientId) rate limited, handling message")
        case .undecodableUnauthenticatedMessage(let clientId):
            muscleLogger.warning("Client \(clientId) sent unparsable message before authenticating")
        case .undecodableAuthenticatedMessage(let clientId):
            muscleLogger.warning("Authenticated client \(clientId) sent unparsable message")
        case .authenticatedProtocolMessage(let clientId, let wireType):
            muscleLogger.warning(
                "Authenticated client \(clientId) sent protocol message \(wireType.rawValue, privacy: .public) after admission"
            )
        case .unauthenticatedMessage(let clientId, let message):
            muscleLogger.warning("Client \(clientId) rejected before auth: \(message, privacy: .public)")
        case .authenticationTimeout(let clientId, let timeoutSeconds):
            muscleLogger.warning("Client \(clientId) did not authenticate within \(timeoutSeconds)s deadline")
        case .versionMismatch(let clientId, let serverVersion, let clientVersion):
            muscleLogger.warning(
                "Client \(clientId) buttonHeistVersion mismatch: server=\(serverVersion), client=\(clientVersion)"
            )
        case .missingRegisteredAddress(let clientId):
            muscleLogger.warning("Client \(clientId) has no registered address, rejecting auth")
        case .lockedOut(let clientId, let address):
            muscleLogger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
        case .invalidToken(let clientId, let attempts):
            muscleLogger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
        case .lockoutStarted(let address, let attempts):
            muscleLogger.warning("Address \(address) locked out after \(attempts) failed attempts")
        }
    }

    // MARK: - Delayed Disconnect

    /// Schedule a delayed disconnect so the recipient can flush the final error payload.
    private func scheduleDelayedDisconnect(_ clientId: Int) {
        delayedDisconnects.schedule(clientId: clientId) { [weak self] in
            await self?.fireDisconnect(clientId)
        }
    }

    private func fireDisconnect(_ clientId: Int) async {
        _ = await delivery.disconnect(clientId)
    }

    // MARK: - Authentication Deadline

    private func executeAuthenticationTimeout(_ clientId: Int) async {
        await executeAdmissionEffects(admission.authenticationTimeout(
            clientId,
            timeoutSeconds: Self.authTimeoutSeconds
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

    private func applySessionEffects(_ effects: [SessionLease.Effect]) {
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

    private func logSessionEvent(_ event: SessionLease.LogEvent) {
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
        requestId: RequestID? = nil
    ) -> Result<Data, ResponseEncodingFailure> {
        ResponseEnvelopeDelivery.encodeEnvelope(message, requestId: requestId)
    }

    private enum ResponseDestination: Sendable {
        case response(ClientAdmission.ResponseHandler)
        case client(Int)
    }

    @discardableResult
    private func sendResponse(
        _ message: ServerMessage,
        requestId: RequestID? = nil,
        to destination: ResponseDestination
    ) async -> ResponseDeliveryOutcome {
        let outcome: ResponseDeliveryOutcome
        switch destination {
        case .response(let respond):
            outcome = await ResponseEnvelopeDelivery.sendMessage(message, requestId: requestId, respond: respond)

        case .client(let clientId):
            outcome = await sendResponseToClient(message, requestId: requestId, clientId: clientId)
        }
        logResponseDeliveryOutcome(outcome)
        return outcome
    }

    private func sendResponseToClient(
        _ message: ServerMessage,
        requestId: RequestID?,
        clientId: Int
    ) async -> ResponseDeliveryOutcome {
        switch encodeEnvelope(message, requestId: requestId) {
        case .success(let data):
            switch await delivery.send(data, toClient: clientId) {
            case .delivered:
                return .delivered
            case .failed(let failure):
                return ResponseDeliveryOutcome(sendFailure: failure)
            }

        case .failure(let failure):
            return .failed(.responseEncodingFailed(failure))
        }
    }

    private func logResponseDeliveryOutcome(_ outcome: ResponseDeliveryOutcome) {
        switch outcome {
        case .delivered:
            break
        case .refused(let failure), .failed(let failure):
            muscleLogger.error("\(failure.description)")
        case .transportUnavailable:
            muscleLogger.error("\(outcome.description)")
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

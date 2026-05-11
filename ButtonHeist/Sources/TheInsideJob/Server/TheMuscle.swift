#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import os.log

import TheScore

/// Manages client authentication, session token validation, and UI-based connection approval.
///
/// The session token is a coordination primitive — it keeps agents from stepping on each
/// other's sessions, not a security credential. Anyone with debug access to the device
/// can read it from the logs and connect.
///
/// Token resolution order:
/// 1. Explicit token (from INSIDEJOB_TOKEN env var or InsideJobToken plist key)
/// 2. New auto-generated UUID (fresh each launch, logged to console)
///
/// Auth behavior is determined per-connection by the incoming token:
/// - Token matches → authenticated immediately (no UI prompt)
/// - Empty token → UI approval prompt (Allow/Deny), approved clients receive the token
/// - Wrong token → rejected with hint to retry without a token for a fresh session
/// - Any connection while a session is active from a different driver → busy signal
private let logger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

/// Isolation: `actor`. All auth state — `clients`, `addressAuthStates`,
/// `sessionPhase`, `lockoutTasks` — is mutated exclusively on TheMuscle's
/// own actor. UI alert presentation lives in a `@MainActor AlertPresenter`
/// companion (see `AlertPresenter.swift`); callbacks installed by TheGetaway
/// (`sendToClient`, `markClientAuthenticated`, `disconnectClient`,
/// `onClientAuthenticated`, `onSessionActiveChanged`) are `@Sendable` and
/// hop to the appropriate context inside their implementations.
actor TheMuscle {

    private static let disconnectGracePeriod: Duration = .milliseconds(100)
    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 30

    // MARK: - Properties

    /// Per-address rate limiting state machine for brute-force protection.
    private enum AddressAuthPhase {
        /// Accumulating failures, not yet locked out.
        case failing(attempts: Int)
        /// Locked out after exceeding maxFailedAttempts.
        case lockedOut(until: Date, attempts: Int)
    }

    /// Rate-limiting state per remote address. Absent = clean (no failures).
    private var addressAuthStates: [String: AddressAuthPhase] = [:]

    /// Per-client lifecycle state machine.
    /// Each client traverses: connected → helloValidated → pendingApproval | authenticated | observer.
    /// Disconnection removes the entry entirely.
    private enum ClientPhase {
        case connected(address: String)
        case helloValidated(address: String)
        case pendingApproval(address: String, respond: @Sendable (Data) -> Void, isObserver: Bool, driverId: String?)
        case authenticated(address: String, driverIdentity: String, subscribed: Bool)
        case observer(address: String, subscribed: Bool)

        var address: String {
            switch self {
            case .connected(let address), .helloValidated(let address),
                 .pendingApproval(let address, _, _, _),
                 .authenticated(let address, _, _), .observer(let address, _):
                return address
            }
        }

        var isAuthenticated: Bool {
            switch self {
            case .authenticated, .observer: return true
            default: return false
            }
        }

        var isSubscribed: Bool {
            switch self {
            case .authenticated(_, _, let subscribed), .observer(_, let subscribed): return subscribed
            default: return false
            }
        }

        var isObserver: Bool {
            if case .observer = self { return true }
            return false
        }

        var hasCompletedHello: Bool {
            switch self {
            case .connected: return false
            default: return true
            }
        }

        var driverIdentity: String? {
            if case .authenticated(_, let identity, _) = self { return identity }
            return nil
        }
    }

    /// Single source of truth for all per-client state. Absent = no such client.
    private var clients: [Int: ClientPhase] = [:]

    private(set) var sessionToken: String
    private let alerts: AlertPresenter

    /// Outstanding "wait then disconnect" tasks. Each entry is a Task spawned by
    /// `scheduleDelayedDisconnect(_:)` that will fire `disconnectClient` after
    /// `disconnectGracePeriod`. Every task self-cleans on completion or
    /// cancellation by removing its own handle from this dictionary; on
    /// `tearDown()` every outstanding task is cancelled so a torn-down
    /// TheMuscle never disconnects against a stale client ID. We key by an
    /// internal monotonic ID so the Task closure doesn't need to capture
    /// its own handle (which would create a "variable captured before
    /// initialization" issue under strict concurrency).
    private var lockoutTasks: [UInt64: Task<Void, Never>] = [:]
    private var nextLockoutId: UInt64 = 0

    // MARK: - Computed Client Accessors

    /// IDs of all authenticated clients (drivers + observers).
    var authenticatedClientIDs: Set<Int> {
        Set(clients.lazy.filter { $0.value.isAuthenticated }.map(\.key))
    }

    /// Count of authenticated clients.
    var authenticatedClientCount: Int {
        clients.values.lazy.filter(\.isAuthenticated).count
    }

    /// IDs of all clients that have completed the hello handshake (any phase past connected).
    var helloValidatedClients: Set<Int> {
        Set(clients.lazy.filter { $0.value.hasCompletedHello }.map(\.key))
    }

    /// IDs of clients subscribed to hierarchy broadcasts.
    var subscribedClients: Set<Int> {
        Set(clients.lazy.filter { $0.value.isSubscribed }.map(\.key))
    }

    /// True when at least one client is subscribed.
    var hasSubscribers: Bool { clients.values.contains(where: \.isSubscribed) }

    /// IDs of clients connected in observe mode.
    var observerClients: Set<Int> {
        Set(clients.lazy.filter { $0.value.isObserver }.map(\.key))
    }

    /// Whether observers require token authentication (default: true; override with env: INSIDEJOB_RESTRICT_WATCHERS=0, plist: InsideJobRestrictWatchers=false)
    private let restrictWatchers: Bool

    // MARK: - Session Lock State

    /// Explicit state machine for the session lifecycle.
    /// Idle → active (driver claims) → draining (all connections gone, timer running) → idle.
    private enum SessionPhase {
        /// No active session — any driver may claim.
        case idle
        /// A driver owns the session with at least one live connection.
        case active(driverId: String, connections: Set<Int>)
        /// All connections disconnected; session will release when the timer fires.
        case draining(driverId: String, releaseTimer: Task<Void, Never>)
    }

    private var sessionPhase: SessionPhase = .idle
    /// Timeout before releasing a session after all connections disconnect or go idle
    private let sessionReleaseTimeout: TimeInterval

    // Computed accessors — preserve the external read interface.

    /// Driver identity that currently holds the session (nil = no active session).
    var activeSessionDriverId: String? {
        switch sessionPhase {
        case .idle: return nil
        case .active(let driverId, _): return driverId
        case .draining(let driverId, _): return driverId
        }
    }

    /// Client IDs belonging to the active session.
    var activeSessionConnections: Set<Int> {
        switch sessionPhase {
        case .active(_, let connections): return connections
        case .idle, .draining: return []
        }
    }

    // MARK: - Callbacks (set by TheInsideJob)

    var sendToClient: (@Sendable (_ data: Data, _ clientId: Int) -> Void)?
    var markClientAuthenticated: (@Sendable (_ clientId: Int) -> Void)?
    var disconnectClient: (@Sendable (_ clientId: Int) -> Void)?
    var onClientAuthenticated: (@Sendable (_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?
    /// Called when the session active state changes (true = session claimed, false = released)
    var onSessionActiveChanged: (@Sendable (_ isActive: Bool) -> Void)?

    // MARK: - Init

    /// Caller must be on `@MainActor` (the alert presenter is `@MainActor`-isolated
    /// and is constructed eagerly when none is provided). Both production
    /// (`TheInsideJob.init`) and the tests today satisfy this. Pass a custom
    /// presenter when you need to construct from outside MainActor.
    @MainActor
    init(explicitToken: String?, alerts: AlertPresenter? = nil) {
        self.sessionToken = explicitToken ?? UUID().uuidString
        self.alerts = alerts ?? AlertPresenter()
        if EnvironmentKey.insideJobRestrictWatchers.value != nil {
            self.restrictWatchers = EnvironmentKey.insideJobRestrictWatchers.boolValue
        } else if let plistValue = Bundle.main.object(forInfoDictionaryKey: "InsideJobRestrictWatchers") as? Bool {
            self.restrictWatchers = plistValue
        } else {
            self.restrictWatchers = true
        }
        if let envTimeout = EnvironmentKey.insideJobSessionTimeout.value,
           let parsed = TimeInterval(envTimeout) {
            self.sessionReleaseTimeout = min(max(1.0, parsed), 3600.0)
        } else {
            self.sessionReleaseTimeout = 30.0
        }
    }

    // MARK: - Callback Wiring

    /// Install transport-facing callbacks. Called once by `TheGetaway.wireTransport`.
    /// Bundles assignment into a single actor hop so the consumer doesn't pay
    /// five `await`s.
    func installCallbacks(
        sendToClient: @escaping @Sendable (Data, Int) -> Void,
        markClientAuthenticated: @escaping @Sendable (Int) -> Void,
        disconnectClient: @escaping @Sendable (Int) -> Void,
        onClientAuthenticated: @escaping @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void,
        onSessionActiveChanged: @escaping @Sendable (Bool) -> Void
    ) {
        self.sendToClient = sendToClient
        self.markClientAuthenticated = markClientAuthenticated
        self.disconnectClient = disconnectClient
        self.onClientAuthenticated = onClientAuthenticated
        self.onSessionActiveChanged = onSessionActiveChanged
    }

    // MARK: - Public API

    /// Register the remote address for a client (called when TCP connection is established).
    func registerClientAddress(_ clientId: Int, address: String) {
        clients[clientId] = .connected(address: address)
    }

    func sendServerHello(clientId: Int) {
        guard let data = encodeEnvelope(.serverHello) else { return }
        sendToClient?(data, clientId)
    }

    /// Called when a ping is received from an authenticated client.
    /// Resets the session inactivity timer if the client belongs to the active session.
    func noteClientActivity(_ clientId: Int) {
        guard activeSessionConnections.contains(clientId) else { return }
        resetInactivityTimer()
    }

    // MARK: - Subscription Management

    /// Register a client for hierarchy update broadcasts.
    func subscribe(clientId: Int) {
        setSubscribed(true, for: clientId)
        logger.info("Client \(clientId) subscribed (\(self.subscribedClients.count) subscribers)")
    }

    /// Remove a client from hierarchy update broadcasts.
    func unsubscribe(clientId: Int) {
        setSubscribed(false, for: clientId)
        logger.info("Client \(clientId) unsubscribed (\(self.subscribedClients.count) subscribers)")
    }

    /// Send data to all subscribed clients.
    func broadcastToSubscribed(_ data: Data) {
        for (clientId, phase) in clients where phase.isSubscribed {
            sendToClient?(data, clientId)
        }
    }

    func handleUnauthenticatedMessage(_ clientId: Int, data: Data, respond: @escaping @Sendable (Data) -> Void) {
        guard let envelope = decodeRequest(data) else {
            logger.warning("Client \(clientId) sent unparsable message before authenticating, disconnecting")
            disconnectClient?(clientId)
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
            if let phase = clients[clientId] {
                clients[clientId] = .helloValidated(address: phase.address)
            }
            sendMessage(.authRequired, respond: respond)
            return
        case .watch(let payload):
            guard clients[clientId]?.hasCompletedHello == true else {
                logger.warning("Client \(clientId) attempted watch before hello")
                disconnectClient?(clientId)
                return
            }
            handleWatchRequest(clientId, payload: payload, respond: respond)
            return
        case .authenticate(let payload):
            guard clients[clientId]?.hasCompletedHello == true else {
                logger.warning("Client \(clientId) attempted auth before hello")
                disconnectClient?(clientId)
                return
            }
            processAuthentication(clientId, payload: payload, respond: respond)
            return
        default:
            logger.warning("Client \(clientId) sent invalid pre-auth message, disconnecting")
            disconnectClient?(clientId)
            return
        }
    }

    private func processAuthentication(_ clientId: Int, payload: AuthenticatePayload, respond: @escaping @Sendable (Data) -> Void) {
        guard let phase = clients[clientId] else {
            logger.warning("Client \(clientId) has no registered address, rejecting auth")
            sendMessage(.error(ServerError(kind: .authFailure, message: "Connection rejected.")), respond: respond)
            scheduleDelayedDisconnect(clientId)
            return
        }
        let address = phase.address
        if isLockedOut(address: address) {
            sendMessage(.error(ServerError(kind: .authFailure, message: "Too many failed attempts. Try again later.")), respond: respond)
            logger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
            scheduleDelayedDisconnect(clientId)
            return
        }

        if payload.token.isEmpty {
            // No token → request UI approval (Allow/Deny prompt on device)
            logger.info("Client \(clientId) requesting UI approval (no token)")
            clients[clientId] = .pendingApproval(address: address, respond: respond, isObserver: false, driverId: payload.driverId)
            showApprovalAlert(clientId: clientId)
            return
        }

        guard constantTimeEqual(payload.token, sessionToken) else {
            // Wrong token → reject with guidance to retry without a token
            let attempts = recordFailedAttempt(address: address)
            if attempts >= TheMuscle.maxFailedAttempts {
                logger.warning("Address \(address) locked out after \(attempts) failed attempts")
            }
            sendMessage(.error(ServerError(kind: .authFailure, message: "Invalid token. Retry without a token to request a fresh session.")), respond: respond)
            logger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
            scheduleDelayedDisconnect(clientId)
            return
        }

        // Token matches → authenticate and acquire session
        clearFailedAttempts(address: address)
        let driverIdentity = effectiveDriverId(driverId: payload.driverId, token: payload.token)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond) {
            return
        }

        clients[clientId] = .authenticated(address: address, driverIdentity: driverIdentity, subscribed: false)
        markClientAuthenticated?(clientId)
        logger.info("Client \(clientId) authenticated with token")
        onClientAuthenticated?(clientId, respond)
    }

    func handleClientDisconnected(_ clientId: Int) {
        let removed = clients.removeValue(forKey: clientId)
        if case .pendingApproval = removed {
            dismissAlert()
        }
        removeSessionConnection(clientId)
    }

    func approveClient(_ clientId: Int) {
        guard case .pendingApproval(let address, let respond, _, let driverId) = clients[clientId] else { return }

        let driverIdentity = effectiveDriverId(driverId: driverId, token: sessionToken)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond) {
            return
        }

        clients[clientId] = .authenticated(address: address, driverIdentity: driverIdentity, subscribed: false)
        markClientAuthenticated?(clientId)
        logger.info("Client \(clientId) approved via UI")
        sendMessage(.authApproved(AuthApprovedPayload(token: sessionToken)), respond: respond)
        onClientAuthenticated?(clientId, respond)
    }

    func denyClient(_ clientId: Int) {
        guard case .pendingApproval(let address, let respond, _, _) = clients[clientId] else { return }
        clients[clientId] = .helloValidated(address: address)
        sendMessage(.error(ServerError(kind: .authFailure, message: "Connection denied by user")), respond: respond)
        logger.info("Client \(clientId) denied via UI")
        scheduleDelayedDisconnect(clientId)
    }

    func tearDown() {
        clients.removeAll()
        for task in lockoutTasks.values {
            task.cancel()
        }
        lockoutTasks.removeAll()
        // Cancel the release timer (if draining) explicitly before tearing down
        // the rest of the session so a fired timer can't see a half-released
        // TheMuscle. `releaseSession()` also calls this, but stating it here
        // documents the intent at the shutdown boundary.
        cancelTimerIfDraining()
        releaseSession()
        dismissAlert()
    }

    // MARK: - Delayed Disconnect

    /// Schedule a `disconnectClient` callback for `clientId` after
    /// `disconnectGracePeriod` so the recipient can flush a final error
    /// payload before the connection is torn down. The handle is retained
    /// in `lockoutTasks` until the body completes (or `tearDown()` cancels
    /// it), so a torn-down TheMuscle never fires a stale disconnect.
    private func scheduleDelayedDisconnect(_ clientId: Int) {
        nextLockoutId &+= 1
        let lockoutId = nextLockoutId
        let task = Task { [weak self] in
            // Sleep returns false on cancellation; whether cancelled or not,
            // we still want to detach our own handle from `lockoutTasks` so
            // it doesn't accumulate.
            let proceed = await Task.cancellableSleep(for: TheMuscle.disconnectGracePeriod)
            if proceed {
                await self?.fireDisconnect(clientId)
            }
            await self?.removeLockoutTask(id: lockoutId)
        }
        lockoutTasks[lockoutId] = task
    }

    /// Called from the delayed-disconnect Task body to actually fire the
    /// `disconnectClient` callback while inside actor isolation.
    private func fireDisconnect(_ clientId: Int) {
        disconnectClient?(clientId)
    }

    /// Drop a finished/cancelled lockout task from the tracking dictionary.
    private func removeLockoutTask(id: UInt64) {
        lockoutTasks.removeValue(forKey: id)
    }

    // MARK: - Status Accessors

    /// Whether a driver session is currently active on this Inside Job instance.
    var isSessionActive: Bool {
        activeSessionDriverId != nil
    }

    /// Whether watchers are allowed for the current session.
    /// For now this is derived from restrictWatchers: when restrictWatchers is false,
    /// observers are allowed once a session is active; when true, only the driver may connect.
    var watchersAllowed: Bool {
        isSessionActive && !restrictWatchers
    }

    /// Number of active connections participating in the session (driver + any watchers).
    var activeSessionConnectionCount: Int {
        activeSessionConnections.count
    }

    // MARK: - Observer Auth

    /// Handle a watch request from an unauthenticated client.
    /// Observers require token authentication by default. Set INSIDEJOB_RESTRICT_WATCHERS=0
    /// to allow unauthenticated observers. Observers never claim a session.
    private func handleWatchRequest(_ clientId: Int, payload: WatchPayload, respond: @escaping @Sendable (Data) -> Void) {
        if restrictWatchers {
            guard let phase = clients[clientId] else {
                sendMessage(.error(ServerError(kind: .authFailure, message: "Connection rejected.")), respond: respond)
                scheduleDelayedDisconnect(clientId)
                return
            }
            let address = phase.address
            if isLockedOut(address: address) {
                sendMessage(.error(ServerError(kind: .authFailure, message: "Too many failed attempts. Try again later.")), respond: respond)
                logger.warning("Observer \(clientId) locked out (address: \(address)), rejecting")
                scheduleDelayedDisconnect(clientId)
                return
            }
            guard !payload.token.isEmpty else {
                sendMessage(.error(ServerError(kind: .authFailure, message: "Watch mode requires a token.")), respond: respond)
                logger.warning("Observer \(clientId) sent no token with restrictWatchers=true, rejected")
                scheduleDelayedDisconnect(clientId)
                return
            }
            guard constantTimeEqual(payload.token, sessionToken) else {
                let attempts = recordFailedAttempt(address: address)
                if attempts >= TheMuscle.maxFailedAttempts {
                    logger.warning("Address \(address) locked out after \(attempts) failed watch attempts")
                }
                sendMessage(.error(ServerError(kind: .authFailure, message: "Invalid token.")), respond: respond)
                logger.warning("Observer \(clientId) sent invalid token, rejected (attempt \(attempts))")
                scheduleDelayedDisconnect(clientId)
                return
            }
            clearFailedAttempts(address: address)
        }
        approveObserver(clientId, respond: respond)
    }

    /// Approve an observer directly (no UI needed)
    private func approveObserver(_ clientId: Int, respond: @escaping @Sendable (Data) -> Void) {
        guard let phase = clients[clientId] else { return }
        clients[clientId] = .observer(address: phase.address, subscribed: true)
        markClientAuthenticated?(clientId)
        sendMessage(.authApproved(AuthApprovedPayload()), respond: respond)
        logger.info("Observer \(clientId) approved (no session lock)")
        onClientAuthenticated?(clientId, respond)
    }

    // MARK: - Session Lock

    /// Resolve the effective driver identity for session locking.
    /// Uses driverId if provided, falls back to token.
    private func effectiveDriverId(driverId: String?, token: String) -> String {
        if let driverId, !driverId.isEmpty {
            return "driver:\(driverId)"
        }
        return "token:\(token)"
    }

    /// Attempt to acquire the session for a client. Returns true if acquired, false if rejected.
    ///
    /// Session rules:
    /// - No active session → claim it
    /// - Active session, same driver → rejoin (cancel release timer)
    /// - Active session, different driver → busy signal
    private func acquireSession(driverIdentity: String, clientId: Int, respond: @escaping @Sendable (Data) -> Void) -> Bool {
        switch sessionPhase {
        case .idle:
            claimSession(driverIdentity: driverIdentity, clientId: clientId)
            return true

        case .active(let activeId, var connections) where driverIdentity == activeId:
            connections.insert(clientId)
            sessionPhase = .active(driverId: activeId, connections: connections)
            logger.info("Client \(clientId) joined existing session")
            return true

        case .draining(let activeId, let timer) where driverIdentity == activeId:
            timer.cancel()
            sessionPhase = .active(driverId: activeId, connections: [clientId])
            logger.info("Client \(clientId) rejoined session during grace period")
            return true

        case .active, .draining:
            let payload = SessionLockedPayload(
                message: "Session is locked by another driver. Session will time out after \(Int(sessionReleaseTimeout))s of inactivity.",
                activeConnections: activeSessionConnections.count
            )
            sendMessage(.sessionLocked(payload), respond: respond)
            logger.warning("Client \(clientId) rejected — session locked (\(self.activeSessionConnections.count) active connection(s))")
            scheduleDelayedDisconnect(clientId)
            return false
        }
    }

    private func claimSession(driverIdentity: String, clientId: Int) {
        cancelTimerIfDraining()
        sessionPhase = .active(driverId: driverIdentity, connections: [clientId])
        logger.info("Session claimed by client \(clientId)")
        onSessionActiveChanged?(true)
    }

    private func releaseSession() {
        let hadSession = switch sessionPhase {
        case .idle: false
        case .active, .draining: true
        }
        cancelTimerIfDraining()
        sessionPhase = .idle
        if hadSession {
            logger.info("Session released")
            onSessionActiveChanged?(false)
        }
    }

    /// Remove a client from the active session. Transitions to draining if no connections remain.
    private func removeSessionConnection(_ clientId: Int) {
        guard case .active(let driverId, var connections) = sessionPhase else { return }
        connections.remove(clientId)
        if connections.isEmpty {
            logger.info("All session connections gone, starting \(self.sessionReleaseTimeout)s release timer")
            let timer = makeReleaseTimer()
            sessionPhase = .draining(driverId: driverId, releaseTimer: timer)
        } else {
            sessionPhase = .active(driverId: driverId, connections: connections)
        }
    }

    /// Cancel the release timer if currently draining.
    private func cancelTimerIfDraining() {
        if case .draining(_, let timer) = sessionPhase {
            timer.cancel()
        }
    }

    /// Create a release timer task that fires after `sessionReleaseTimeout`.
    private func makeReleaseTimer() -> Task<Void, Never> {
        Task { [weak self, sessionReleaseTimeout] in
            guard await Task.cancellableSleep(for: .seconds(sessionReleaseTimeout)) else { return }
            guard !Task.isCancelled else { return }
            await self?.releaseSession()
        }
    }

    /// Reset the inactivity timer (called on heartbeat/ping from active session client).
    private func resetInactivityTimer() {
        switch sessionPhase {
        case .idle:
            return
        case .active:
            // Connections exist — no timer needed; timer starts on last disconnect
            return
        case .draining(let driverId, let oldTimer):
            oldTimer.cancel()
            let timer = makeReleaseTimer()
            sessionPhase = .draining(driverId: driverId, releaseTimer: timer)
        }
    }

    // MARK: - Client Subscription State

    /// Toggle the subscribed flag on an authenticated or observer client.
    private func setSubscribed(_ subscribed: Bool, for clientId: Int) {
        switch clients[clientId] {
        case .authenticated(let address, let driverIdentity, _):
            clients[clientId] = .authenticated(address: address, driverIdentity: driverIdentity, subscribed: subscribed)
        case .observer(let address, _):
            clients[clientId] = .observer(address: address, subscribed: subscribed)
        default:
            logger.debug("Ignoring subscribe(\(subscribed)) for client \(clientId) in phase \(String(describing: self.clients[clientId]))")
        }
    }

    // MARK: - Rate Limiting Helpers

    /// Check if an address is currently locked out. Clears expired lockouts automatically.
    /// Returns true if locked out (caller should reject).
    private func isLockedOut(address: String) -> Bool {
        guard case .lockedOut(let expiry, _) = addressAuthStates[address] else { return false }
        if Date() < expiry {
            return true
        }
        addressAuthStates.removeValue(forKey: address)
        return false
    }

    /// Record a failed auth attempt for an address. Returns the new attempt count.
    @discardableResult
    private func recordFailedAttempt(address: String) -> Int {
        let currentAttempts = switch addressAuthStates[address] {
        case .failing(let count): count
        case .lockedOut(_, let count): count
        case nil: 0
        }
        let newAttempts = currentAttempts + 1
        if newAttempts >= TheMuscle.maxFailedAttempts {
            addressAuthStates[address] = .lockedOut(
                until: Date().addingTimeInterval(TheMuscle.lockoutDuration),
                attempts: newAttempts
            )
        } else {
            addressAuthStates[address] = .failing(attempts: newAttempts)
        }
        return newAttempts
    }

    /// Clear rate-limiting state for an address after successful auth.
    private func clearFailedAttempts(address: String) {
        addressAuthStates.removeValue(forKey: address)
    }

    // MARK: - Alert Presentation

    /// Present the connection-approval UI for `clientId`. The `onAllow` /
    /// `onDeny` callbacks hop back into actor isolation to mutate auth state.
    private func showApprovalAlert(clientId: Int) {
        let presenter = alerts
        Task { @MainActor [weak self] in
            presenter.presentApproval(
                clientId: clientId,
                onAllow: { [weak self] in
                    Task { await self?.approveClient(clientId) }
                },
                onDeny: { [weak self] in
                    Task { await self?.denyClient(clientId) }
                }
            )
            // Silence the unused-self warning: `self` is captured to anchor
            // the alert presentation to TheMuscle's lifetime, but the alert
            // outlives the immediate scope through `presenter`.
            _ = self
        }
    }

    private func dismissAlert() {
        let presenter = alerts
        Task { @MainActor in
            presenter.dismiss()
        }
    }

    // MARK: - Helpers

    func clientIDs(for driverIdentity: String) -> [Int] {
        clients.compactMap { clientId, phase in
            phase.driverIdentity == driverIdentity ? clientId : nil
        }
    }

    func encodeEnvelope(_ message: ServerMessage) -> Data? {
        do {
            return try ResponseEnvelope(message: message).encoded()
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

    private func sendMessage(_ message: ServerMessage, respond: @escaping @Sendable (Data) -> Void) {
        if let data = encodeEnvelope(message) {
            respond(data)
        } else if let errorData = encodeEnvelope(.error(ServerError(kind: .general, message: "Encoding failed"))) {
            respond(errorData)
        }
    }
    /// Constant-time comparison for equal-length strings. Returns early on length mismatch (acceptable per AUTH.md threat model).
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (lhs, rhs) in zip(aBytes, bBytes) {
            result |= lhs ^ rhs
        }
        return result == 0
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

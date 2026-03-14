#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import os.log
import TheScore

/// Manages client authentication, token validation, and UI-based connection approval.
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

@MainActor
final class TheMuscle {

    /// Grace period (100ms) before disconnecting a rejected client, giving them time to read the error.
    private static let disconnectGracePeriod: UInt64 = 100_000_000

    /// Maximum consecutive failed auth attempts before temporary lockout.
    private static let maxFailedAttempts = 5

    /// Lockout duration after exceeding maxFailedAttempts.
    private static let lockoutDuration: TimeInterval = 30

    // MARK: - Properties

    /// Tracks failed auth attempts per remote address for brute-force protection.
    private var failedAuthAttempts: [String: Int] = [:]
    /// Remote addresses temporarily locked out after too many failed attempts.
    private var lockedOutAddresses: [String: Date] = [:]
    /// Maps client IDs to their remote address for lockout tracking across reconnections.
    private var clientAddresses: [Int: String] = [:]

    private(set) var authToken: String
    private var pendingApprovalClients: [Int: @Sendable (Data) -> Void] = [:]
    private(set) var authenticatedClientCount: Int = 0
    private(set) var authenticatedClientIDs: Set<Int> = []
    private(set) var helloValidatedClients: Set<Int> = []
    private weak var presentedAlert: UIAlertController?

    // MARK: - Subscription Tracking

    /// Clients that have opted in to receive hierarchy update broadcasts.
    private(set) var subscribedClients: Set<Int> = []

    /// True when at least one client is subscribed.
    var hasSubscribers: Bool { !subscribedClients.isEmpty }

    // MARK: - Observer Tracking

    /// Clients connected in observe mode — not part of any session.
    private(set) var observerClients: Set<Int> = []
    /// Pending approval clients that requested observe mode
    private var pendingObserverClients: Set<Int> = []
    /// Whether observers require token authentication (default: true; override with env: INSIDEJOB_RESTRICT_WATCHERS=0, plist: InsideJobRestrictWatchers=false)
    private let restrictWatchers: Bool

    // MARK: - Session Lock State

    /// Driver identity that currently holds the session (nil = no active session).
    /// This is derived from driverId (when provided) or the auth token (fallback).
    private(set) var activeSessionDriverId: String?
    /// Client IDs belonging to the active session
    private(set) var activeSessionConnections: Set<Int> = []
    /// Maps each authenticated client to their effective driver identity
    private var clientDriverIds: [Int: String] = [:]
    /// Timer that fires to release the session after inactivity (no connections and no heartbeat)
    private var sessionReleaseTimer: Task<Void, Never>?
    /// Timeout before releasing a session after all connections disconnect or go idle
    private let sessionReleaseTimeout: TimeInterval

    // MARK: - Callbacks (set by TheInsideJob)

    var sendToClient: ((_ data: Data, _ clientId: Int) -> Void)?
    var markClientAuthenticated: ((_ clientId: Int) -> Void)?
    var disconnectClient: ((_ clientId: Int) -> Void)?
    var onClientAuthenticated: ((_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?
    /// Called when the session active state changes (true = session claimed, false = released)
    var onSessionActiveChanged: ((_ isActive: Bool) -> Void)?

    // MARK: - Init

    init(explicitToken: String?) {
        self.authToken = TheMuscle.resolveToken(explicit: explicitToken)
        if let envValue = ProcessInfo.processInfo.environment["INSIDEJOB_RESTRICT_WATCHERS"] {
            self.restrictWatchers = ["1", "true", "yes"].contains(envValue.lowercased())
        } else if let plistValue = Bundle.main.object(forInfoDictionaryKey: "InsideJobRestrictWatchers") as? Bool {
            self.restrictWatchers = plistValue
        } else {
            self.restrictWatchers = true
        }
        if let envTimeout = ProcessInfo.processInfo.environment["INSIDEJOB_SESSION_TIMEOUT"],
           let parsed = TimeInterval(envTimeout) {
            self.sessionReleaseTimeout = max(1.0, parsed)
        } else {
            self.sessionReleaseTimeout = 30.0
        }
    }

    // MARK: - Token Resolution

    private static func resolveToken(explicit: String?) -> String {
        if let explicit {
            return explicit
        }
        return UUID().uuidString
    }

    // MARK: - Public API

    /// Register the remote address for a client (called when TCP connection is established).
    func registerClientAddress(_ clientId: Int, address: String) {
        clientAddresses[clientId] = address
    }

    func sendServerHello(clientId: Int) {
        guard let data = try? JSONEncoder().encode(ResponseEnvelope(message: .serverHello)) else { return }
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
        subscribedClients.insert(clientId)
        logger.info("Client \(clientId) subscribed (\(self.subscribedClients.count) subscribers)")
    }

    /// Remove a client from hierarchy update broadcasts.
    func unsubscribe(clientId: Int) {
        subscribedClients.remove(clientId)
        logger.info("Client \(clientId) unsubscribed (\(self.subscribedClients.count) subscribers)")
    }

    /// Send data to all subscribed clients.
    func broadcastToSubscribed(_ data: Data) {
        for clientId in subscribedClients {
            sendToClient?(data, clientId)
        }
    }

    func handleUnauthenticatedMessage(_ clientId: Int, data: Data, respond: @escaping @Sendable (Data) -> Void) {
        guard let envelope = try? JSONDecoder().decode(RequestEnvelope.self, from: data) else {
            logger.warning("Client \(clientId) sent unparsable message before authenticating, disconnecting")
            disconnectClient?(clientId)
            return
        }

        guard envelope.protocolVersion == protocolVersion else {
            sendMessage(
                .protocolMismatch(ProtocolMismatchPayload(
                    expectedProtocolVersion: protocolVersion,
                    receivedProtocolVersion: envelope.protocolVersion
                )),
                respond: respond
            )
            logger.warning("Client \(clientId) protocol mismatch: expected \(protocolVersion), got \(envelope.protocolVersion)")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                self?.disconnectClient?(clientId)
            }
            return
        }

        switch envelope.message {
        case .clientHello:
            helloValidatedClients.insert(clientId)
            sendMessage(.authRequired, respond: respond)
            return
        case .watch(let payload):
            guard helloValidatedClients.contains(clientId) else {
                logger.warning("Client \(clientId) attempted watch before hello")
                disconnectClient?(clientId)
                return
            }
            handleWatchRequest(clientId, payload: payload, respond: respond)
            return
        case .authenticate:
            guard helloValidatedClients.contains(clientId) else {
                logger.warning("Client \(clientId) attempted auth before hello")
                disconnectClient?(clientId)
                return
            }
            // Fall through to existing auth logic below
        default:
            logger.warning("Client \(clientId) sent invalid pre-auth message, disconnecting")
            disconnectClient?(clientId)
            return
        }

        guard case .authenticate(let payload) = envelope.message else { return }

        // Check lockout before processing auth (keyed on remote address to persist across reconnections)
        let address = clientAddresses[clientId]
        if let address, let lockoutExpiry = lockedOutAddresses[address], Date() < lockoutExpiry {
            sendMessage(.authFailed("Too many failed attempts. Try again later."), respond: respond)
            logger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                self?.disconnectClient?(clientId)
            }
            return
        }
        if let address { lockedOutAddresses.removeValue(forKey: address) }

        if payload.token.isEmpty {
            // No token → request UI approval (Allow/Deny prompt on device)
            logger.info("Client \(clientId) requesting UI approval (no token)")
            pendingApprovalClients[clientId] = respond
            showApprovalAlert(
                clientId: clientId,
                onAllow: { [weak self] in self?.approveClient(clientId) },
                onDeny: { [weak self] in self?.denyClient(clientId) }
            )
            return
        }

        guard payload.token == authToken else {
            // Wrong token → reject with guidance to retry without a token
            let attemptKey = address ?? "unknown-\(clientId)"
            let attempts = (failedAuthAttempts[attemptKey] ?? 0) + 1
            failedAuthAttempts[attemptKey] = attempts
            if attempts >= TheMuscle.maxFailedAttempts {
                lockedOutAddresses[attemptKey] = Date().addingTimeInterval(TheMuscle.lockoutDuration)
                logger.warning("Address \(attemptKey) locked out after \(attempts) failed attempts")
            }
            sendMessage(.authFailed("Invalid token. Retry without a token to request a fresh session."), respond: respond)
            logger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                self?.disconnectClient?(clientId)
            }
            return
        }

        // Token matches → authenticate and acquire session
        if let address { failedAuthAttempts.removeValue(forKey: address) }
        let driverIdentity = effectiveDriverId(driverId: payload.driverId, token: payload.token)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond) {
            return
        }

        markClientAuthenticated?(clientId)
        logger.info("Client \(clientId) authenticated with token")
        authenticatedClientIDs.insert(clientId)
        clientDriverIds[clientId] = driverIdentity
        updateAuthenticatedCount(delta: 1)
        onClientAuthenticated?(clientId, respond)
    }

    func handleClientDisconnected(_ clientId: Int) {
        pendingApprovalClients.removeValue(forKey: clientId)
        clientDriverIds.removeValue(forKey: clientId)
        clientAddresses.removeValue(forKey: clientId)
        subscribedClients.remove(clientId)
        observerClients.remove(clientId)
        pendingObserverClients.remove(clientId)
        helloValidatedClients.remove(clientId)
        if authenticatedClientIDs.remove(clientId) != nil {
            updateAuthenticatedCount(delta: -1)
        }

        // Session tracking
        activeSessionConnections.remove(clientId)
        if activeSessionDriverId != nil && activeSessionConnections.isEmpty {
            logger.info("All session connections gone, starting \(self.sessionReleaseTimeout)s release timer")
            startReleaseTimer()
        }
    }

    func approveClient(_ clientId: Int) {
        guard let respond = pendingApprovalClients.removeValue(forKey: clientId) else { return }

        // UI-approved clients use the server's authToken — session check with that token
        let driverIdentity = effectiveDriverId(driverId: nil, token: authToken)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, respond: respond) {
            return
        }

        markClientAuthenticated?(clientId)
        logger.info("Client \(clientId) approved via UI")
        authenticatedClientIDs.insert(clientId)
        clientDriverIds[clientId] = driverIdentity
        sendMessage(.authApproved(AuthApprovedPayload(token: authToken)), respond: respond)
        updateAuthenticatedCount(delta: 1)
        onClientAuthenticated?(clientId, respond)
    }

    func denyClient(_ clientId: Int) {
        guard let respond = pendingApprovalClients.removeValue(forKey: clientId) else { return }
        sendMessage(.authFailed("Connection denied by user"), respond: respond)
        logger.info("Client \(clientId) denied via UI")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
            self?.disconnectClient?(clientId)
        }
    }

    func tearDown() {
        pendingApprovalClients.removeAll()
        authenticatedClientIDs.removeAll()
        authenticatedClientCount = 0
        clientDriverIds.removeAll()
        helloValidatedClients.removeAll()
        subscribedClients.removeAll()
        observerClients.removeAll()
        pendingObserverClients.removeAll()
        releaseSession()
        dismissAlert()
    }

    func invalidateToken() {
        authToken = UUID().uuidString
        logger.info("Token invalidated, new token: \(self.authToken, privacy: .sensitive)")
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
            guard !payload.token.isEmpty else {
                sendMessage(.authFailed("Watch mode requires a token."), respond: respond)
                logger.warning("Observer \(clientId) sent no token with restrictWatchers=true, rejected")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                    self?.disconnectClient?(clientId)
                }
                return
            }
            guard payload.token == authToken else {
                sendMessage(.authFailed("Invalid token."), respond: respond)
                logger.warning("Observer \(clientId) sent invalid token, rejected")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                    self?.disconnectClient?(clientId)
                }
                return
            }
        }
        approveObserver(clientId, respond: respond)
    }

    /// Approve an observer from the pending-approval path (UI prompt)
    private func approveObserver(_ clientId: Int) {
        guard let respond = pendingApprovalClients.removeValue(forKey: clientId) else { return }
        pendingObserverClients.remove(clientId)
        markClientAuthenticated?(clientId)
        authenticatedClientIDs.insert(clientId)
        observerClients.insert(clientId)
        subscribedClients.insert(clientId)
        sendMessage(.authApproved(AuthApprovedPayload()), respond: respond)
        updateAuthenticatedCount(delta: 1)
        logger.info("Observer \(clientId) approved via UI")
        onClientAuthenticated?(clientId, respond)
    }

    /// Approve an observer directly (no UI needed)
    private func approveObserver(_ clientId: Int, respond: @escaping @Sendable (Data) -> Void) {
        markClientAuthenticated?(clientId)
        authenticatedClientIDs.insert(clientId)
        observerClients.insert(clientId)
        subscribedClients.insert(clientId)
        sendMessage(.authApproved(AuthApprovedPayload()), respond: respond)
        updateAuthenticatedCount(delta: 1)
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
        if let activeId = activeSessionDriverId {
            if driverIdentity == activeId {
                // Same driver — allow, cancel any pending release timer
                sessionReleaseTimer?.cancel()
                sessionReleaseTimer = nil
                activeSessionConnections.insert(clientId)
                logger.info("Client \(clientId) joined existing session")
                return true
            } else {
                // Different driver — busy signal, no force takeover
                let payload = SessionLockedPayload(
                    message: "Session is locked by another driver. Session will time out after \(Int(sessionReleaseTimeout))s of inactivity.",
                    activeConnections: activeSessionConnections.count
                )
                sendMessage(.sessionLocked(payload), respond: respond)
                logger.warning("Client \(clientId) rejected — session locked (\(self.activeSessionConnections.count) active connection(s))")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                    self?.disconnectClient?(clientId)
                }
                return false
            }
        } else {
            // No active session — claim it
            claimSession(driverIdentity: driverIdentity, clientId: clientId)
            return true
        }
    }

    private func claimSession(driverIdentity: String, clientId: Int) {
        activeSessionDriverId = driverIdentity
        activeSessionConnections = [clientId]
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = nil
        logger.info("Session claimed by client \(clientId)")
        onSessionActiveChanged?(true)
    }

    private func releaseSession() {
        let hadSession = activeSessionDriverId != nil
        activeSessionDriverId = nil
        activeSessionConnections.removeAll()
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = nil
        if hadSession {
            logger.info("Session released")
            onSessionActiveChanged?(false)
        }
    }

    /// Start the single inactivity timer. Fires after `sessionReleaseTimeout` to release the session.
    private func startReleaseTimer() {
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = Task { [weak self, sessionReleaseTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(sessionReleaseTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.releaseSession()
        }
    }

    /// Reset the inactivity timer (called on heartbeat/ping from active session client).
    private func resetInactivityTimer() {
        guard activeSessionDriverId != nil else { return }
        if activeSessionConnections.isEmpty {
            // No connections — restart the release countdown
            startReleaseTimer()
        }
        // If there are active connections, no timer needed — timer starts on last disconnect
    }

    // MARK: - Private

    private func updateAuthenticatedCount(delta: Int) {
        authenticatedClientCount = max(0, authenticatedClientCount + delta)
    }

    private func showApprovalAlert(
        clientId: Int,
        onAllow: @escaping @MainActor () -> Void,
        onDeny: @escaping @MainActor () -> Void
    ) {
        dismissAlert()

        let alert = UIAlertController(
            title: "Connection Request",
            message: "Connection #\(clientId) is requesting access.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Deny", style: .destructive) { _ in onDeny() })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in onAllow() })

        guard let vc = Self.topViewController() else { return }
        vc.present(alert, animated: true)
        presentedAlert = alert
    }

    private func dismissAlert() {
        presentedAlert?.dismiss(animated: false)
        presentedAlert = nil
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var vc = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }

    func clientIDs(for driverIdentity: String) -> [Int] {
        clientDriverIds.filter { $0.value == driverIdentity }.map(\.key)
    }

    private func sendMessage(_ message: ServerMessage, respond: @escaping @Sendable (Data) -> Void) {
        guard let data = try? JSONEncoder().encode(ResponseEnvelope(message: message)) else {
            logger.error("Failed to encode message")
            return
        }
        respond(data)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

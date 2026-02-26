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
private let logger = Logger(subsystem: "com.buttonheist.insidejob", category: "auth")

@MainActor
final class TheMuscle {

    /// Grace period (100ms) before disconnecting a rejected client, giving them time to read the error.
    private static let disconnectGracePeriod: UInt64 = 100_000_000

    // MARK: - Properties

    private(set) var authToken: String
    private var pendingApprovalClients: [Int: @Sendable (Data) -> Void] = [:]
    private(set) var authenticatedClientCount: Int = 0
    private(set) var authenticatedClientIDs: Set<Int> = []
    private weak var presentedAlert: UIAlertController?

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

    // MARK: - Callbacks (set by InsideJob)

    var sendToClient: ((_ data: Data, _ clientId: Int) -> Void)?
    var markClientAuthenticated: ((_ clientId: Int) -> Void)?
    var disconnectClient: ((_ clientId: Int) -> Void)?
    var onClientAuthenticated: ((_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?
    /// Called during force-takeover to disconnect all clients from the evicted session
    var disconnectClientsForSession: ((_ clientIds: [Int]) -> Void)?

    // MARK: - Init

    init(explicitToken: String?) {
        self.authToken = TheMuscle.resolveToken(explicit: explicitToken)
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

    func sendAuthRequired(clientId: Int) {
        guard let data = try? JSONEncoder().encode(ServerMessage.authRequired) else { return }
        sendToClient?(data, clientId)
    }

    /// Called when a ping is received from an authenticated client.
    /// Resets the session inactivity timer if the client belongs to the active session.
    func noteClientActivity(_ clientId: Int) {
        guard activeSessionConnections.contains(clientId) else { return }
        resetInactivityTimer()
    }

    func handleUnauthenticatedMessage(_ clientId: Int, data: Data, respond: @escaping @Sendable (Data) -> Void) {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
              case .authenticate(let payload) = message else {
            logger.warning("Client \(clientId) sent non-auth message before authenticating, disconnecting")
            disconnectClient?(clientId)
            return
        }

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
            sendMessage(.authFailed("Invalid token. Retry without a token to request a fresh session."), respond: respond)
            logger.warning("Client \(clientId) sent invalid token, rejected")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: TheMuscle.disconnectGracePeriod)
                self?.disconnectClient?(clientId)
            }
            return
        }

        // Token matches → authenticate and acquire session
        let driverIdentity = effectiveDriverId(driverId: payload.driverId, token: payload.token)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, forceSession: payload.forceSession == true, respond: respond) {
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
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, forceSession: false, respond: respond) {
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
        releaseSession()
        dismissAlert()
    }

    func invalidateToken() {
        authToken = UUID().uuidString
        logger.info("Token invalidated, new token: \(self.authToken)")
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
    /// - Active session, different driver → busy signal (no force takeover)
    private func acquireSession(driverIdentity: String, clientId: Int, forceSession: Bool, respond: @escaping @Sendable (Data) -> Void) -> Bool {
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
    }

    private func releaseSession() {
        let hadSession = activeSessionDriverId != nil
        activeSessionDriverId = nil
        activeSessionConnections.removeAll()
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = nil
        if hadSession {
            logger.info("Session released")
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
        guard let data = try? JSONEncoder().encode(message) else {
            logger.error("Failed to encode message")
            return
        }
        respond(data)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

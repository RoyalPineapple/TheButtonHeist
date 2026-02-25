#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit
import TheGoods

/// Manages client authentication, token validation, and UI-based connection approval.
///
/// Token resolution order:
/// 1. Explicit token (from INSIDEMAN_TOKEN env var or InsideManToken plist key)
/// 2. Persisted token (from UserDefaults — survives app relaunch)
/// 3. New auto-generated UUID (stored in UserDefaults for next launch)
///
/// When the token is auto-generated (not explicitly set), `requiresUIApproval` is true
/// and clients can request on-device Allow/Deny approval by sending an empty token.
@MainActor
final class TheMuscle {

    // MARK: - Constants

    private static let tokenKey = "InsideManAuthToken"

    // MARK: - Properties

    private(set) var authToken: String
    let requiresUIApproval: Bool
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
    /// Timer that fires to release the session after all connections disconnect
    private var sessionReleaseTimer: Task<Void, Never>?
    /// Timeout before releasing a session after all connections disconnect
    private let sessionReleaseTimeout: TimeInterval

    // MARK: - Callbacks (set by InsideMan)

    var sendToClient: ((_ data: Data, _ clientId: Int) -> Void)?
    var markClientAuthenticated: ((_ clientId: Int) -> Void)?
    var disconnectClient: ((_ clientId: Int) -> Void)?
    var onClientAuthenticated: ((_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?
    /// Called during force-takeover to disconnect all clients from the evicted session
    var disconnectClientsForSession: ((_ clientIds: [Int]) -> Void)?

    // MARK: - Init

    init(explicitToken: String?) {
        let resolved = TheMuscle.resolveToken(explicit: explicitToken)
        self.authToken = resolved.token
        self.requiresUIApproval = resolved.needsApproval
        if let envTimeout = ProcessInfo.processInfo.environment["INSIDEMAN_SESSION_TIMEOUT"],
           let parsed = TimeInterval(envTimeout) {
            self.sessionReleaseTimeout = max(1.0, parsed)
        } else {
            self.sessionReleaseTimeout = 30.0
        }
    }

    // MARK: - Token Resolution

    private static func resolveToken(explicit: String?) -> (token: String, needsApproval: Bool) {
        if let explicit {
            return (explicit, false)
        }
        if let stored = UserDefaults.standard.string(forKey: tokenKey), !stored.isEmpty {
            return (stored, true)
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: tokenKey)
        return (generated, true)
    }

    // MARK: - Public API

    func sendAuthRequired(clientId: Int) {
        guard let data = try? JSONEncoder().encode(ServerMessage.authRequired) else { return }
        sendToClient?(data, clientId)
    }

    func handleUnauthenticatedMessage(_ clientId: Int, data: Data, respond: @escaping @Sendable (Data) -> Void) {
        guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
              case .authenticate(let payload) = message else {
            NSLog("[TheMuscle] Client \(clientId) sent non-auth message before authenticating, disconnecting")
            disconnectClient?(clientId)
            return
        }

        // Empty token + UI approval mode → show approval alert
        if payload.token.isEmpty && requiresUIApproval {
            NSLog("[TheMuscle] Client \(clientId) requesting UI approval")
            pendingApprovalClients[clientId] = respond
            showApprovalAlert(
                clientId: clientId,
                onAllow: { [weak self] in self?.approveClient(clientId) },
                onDeny: { [weak self] in self?.denyClient(clientId) }
            )
            return
        }

        guard payload.token == authToken else {
            sendMessage(.authFailed("Invalid token"), respond: respond)
            NSLog("[TheMuscle] Client \(clientId) failed auth")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.disconnectClient?(clientId)
            }
            return
        }

        // Session lock check
        let driverIdentity = effectiveDriverId(driverId: payload.driverId, token: payload.token)
        if !acquireSession(driverIdentity: driverIdentity, clientId: clientId, forceSession: payload.forceSession == true, respond: respond) {
            return
        }

        markClientAuthenticated?(clientId)
        NSLog("[TheMuscle] Client \(clientId) authenticated")
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
            NSLog("[TheMuscle] All session connections gone, starting \(sessionReleaseTimeout)s release timer")
            sessionReleaseTimer?.cancel()
            sessionReleaseTimer = Task { [weak self, sessionReleaseTimeout] in
                try? await Task.sleep(nanoseconds: UInt64(sessionReleaseTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.releaseSession()
            }
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
        NSLog("[TheMuscle] Client \(clientId) approved via UI")
        authenticatedClientIDs.insert(clientId)
        clientDriverIds[clientId] = driverIdentity
        sendMessage(.authApproved(AuthApprovedPayload(token: authToken)), respond: respond)
        updateAuthenticatedCount(delta: 1)
        onClientAuthenticated?(clientId, respond)
    }

    func denyClient(_ clientId: Int) {
        guard let respond = pendingApprovalClients.removeValue(forKey: clientId) else { return }
        sendMessage(.authFailed("Connection denied by user"), respond: respond)
        NSLog("[TheMuscle] Client \(clientId) denied via UI")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
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
        let newToken = UUID().uuidString
        UserDefaults.standard.set(newToken, forKey: TheMuscle.tokenKey)
        authToken = newToken
        NSLog("[TheMuscle] Token invalidated, new token generated")
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
    private func acquireSession(driverIdentity: String, clientId: Int, forceSession: Bool, respond: @escaping @Sendable (Data) -> Void) -> Bool {
        if let activeId = activeSessionDriverId {
            if driverIdentity == activeId {
                // Same driver — allow, cancel any pending release timer
                sessionReleaseTimer?.cancel()
                sessionReleaseTimer = nil
                activeSessionConnections.insert(clientId)
                NSLog("[TheMuscle] Client \(clientId) joined existing session")
                return true
            } else if forceSession {
                // Force takeover — evict existing session
                let evictedClients = Array(activeSessionConnections)
                NSLog("[TheMuscle] Client \(clientId) force-taking session, evicting \(evictedClients.count) connection(s)")
                releaseSession()
                disconnectClientsForSession?(evictedClients)
                claimSession(driverIdentity: driverIdentity, clientId: clientId)
                return true
            } else {
                // Different driver, no force — reject
                let payload = SessionLockedPayload(
                    message: "Session is locked by another driver",
                    activeConnections: activeSessionConnections.count
                )
                sendMessage(.sessionLocked(payload), respond: respond)
                NSLog("[TheMuscle] Client \(clientId) rejected — session locked (\(activeSessionConnections.count) active connection(s))")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000)
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
        NSLog("[TheMuscle] Session claimed by client \(clientId)")
    }

    private func releaseSession() {
        let hadSession = activeSessionDriverId != nil
        activeSessionDriverId = nil
        activeSessionConnections.removeAll()
        sessionReleaseTimer?.cancel()
        sessionReleaseTimer = nil
        if hadSession {
            NSLog("[TheMuscle] Session released")
        }
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
            NSLog("[TheMuscle] Failed to encode message")
            return
        }
        respond(data)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

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

    // MARK: - Callbacks (set by InsideMan)

    var sendToClient: ((_ data: Data, _ clientId: Int) -> Void)?
    var markClientAuthenticated: ((_ clientId: Int) -> Void)?
    var disconnectClient: ((_ clientId: Int) -> Void)?
    var onClientAuthenticated: ((_ clientId: Int, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?

    // MARK: - Init

    init(explicitToken: String?) {
        let resolved = TheMuscle.resolveToken(explicit: explicitToken)
        self.authToken = resolved.token
        self.requiresUIApproval = resolved.needsApproval
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

        markClientAuthenticated?(clientId)
        NSLog("[TheMuscle] Client \(clientId) authenticated")
        authenticatedClientIDs.insert(clientId)
        updateAuthenticatedCount(delta: 1)
        onClientAuthenticated?(clientId, respond)
    }

    func handleClientDisconnected(_ clientId: Int) {
        pendingApprovalClients.removeValue(forKey: clientId)
        if authenticatedClientIDs.remove(clientId) != nil {
            updateAuthenticatedCount(delta: -1)
        }
    }

    func approveClient(_ clientId: Int) {
        guard let respond = pendingApprovalClients.removeValue(forKey: clientId) else { return }
        markClientAuthenticated?(clientId)
        NSLog("[TheMuscle] Client \(clientId) approved via UI")
        authenticatedClientIDs.insert(clientId)
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
        dismissAlert()
    }

    func invalidateToken() {
        let newToken = UUID().uuidString
        UserDefaults.standard.set(newToken, forKey: TheMuscle.tokenKey)
        authToken = newToken
        NSLog("[TheMuscle] Token invalidated, new token generated")
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

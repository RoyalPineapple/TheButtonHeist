#if canImport(UIKit)
#if DEBUG
import UIKit

/// Shows a system alert for connection approval prompts.
@MainActor
public enum ConnectionApprovalOverlay {

    private static weak var presentedAlert: UIAlertController?

    static func show(state: OverlayState) {
        // Only the approval state shows UI; waiting/connected are silent.
    }

    static func showApproval(
        clientId: Int,
        onAllow: @escaping @MainActor () -> Void,
        onDeny: @escaping @MainActor () -> Void
    ) {
        // Dismiss any existing alert first
        presentedAlert?.dismiss(animated: false)

        let alert = UIAlertController(
            title: "Connection Request",
            message: "Connection #\(clientId) is requesting access.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Deny", style: .destructive) { _ in onDeny() })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in onAllow() })

        guard let vc = topViewController() else { return }
        vc.present(alert, animated: true)
        presentedAlert = alert
    }

    static func updateConnectedCount(_ count: Int) {
        // No persistent UI needed
    }

    static func hide() {
        presentedAlert?.dismiss(animated: false)
        presentedAlert = nil
    }

    enum OverlayState {
        case waiting
        case pendingApproval(clientId: Int, onAllow: @MainActor () -> Void, onDeny: @MainActor () -> Void)
        case connected(count: Int)
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
}
#endif // DEBUG
#endif // canImport(UIKit)

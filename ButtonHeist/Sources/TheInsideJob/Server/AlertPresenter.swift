#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

/// Presents the connection-approval `UIAlertController` for `TheMuscle`.
///
/// Extracted as a separate `@MainActor` companion so `TheMuscle` itself can be
/// converted to an `actor`. The presenter owns the live alert reference and the
/// top-view-controller lookup — both of which require MainActor isolation —
/// while the auth state machine in `TheMuscle` runs on its own actor.
///
/// The presenter is intentionally minimal: it does not know about clients,
/// tokens, or session lifecycle. It accepts `onAllow` / `onDeny` closures
/// (already isolated to `@MainActor`) that the caller hops back to actor
/// context to run actual decision logic.
@MainActor
final class AlertPresenter {

    private weak var presentedAlert: UIAlertController?

    init() {}

    // MARK: - Approval Alert

    /// Show the connection-approval alert for `clientId`.
    ///
    /// If a previous alert is still on screen, dismisses it first. If no
    /// foreground view controller is available, runs `onDeny` immediately so
    /// the caller's auth state machine doesn't get stuck waiting for input.
    func presentApproval(
        clientId: Int,
        onAllow: @escaping @MainActor () -> Void,
        onDeny: @escaping @MainActor () -> Void
    ) {
        dismiss()

        let alert = UIAlertController(
            title: "Connection Request",
            message: "Connection #\(clientId) is requesting access.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Deny", style: .destructive) { _ in onDeny() })
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in onAllow() })

        guard let viewController = Self.topViewController() else {
            onDeny()
            return
        }
        viewController.present(alert, animated: true)
        presentedAlert = alert
    }

    /// Dismiss any currently-presented approval alert.
    func dismiss() {
        presentedAlert?.dismiss(animated: false)
        presentedAlert = nil
    }

    // MARK: - Private Helpers

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var viewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        while let presented = viewController.presentedViewController {
            viewController = presented
        }
        return viewController
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

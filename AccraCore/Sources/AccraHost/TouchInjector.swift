#if canImport(UIKit)
import UIKit

/// Injects synthetic touch events using KIF-style private APIs.
/// Used as fallback when accessibilityActivate() doesn't handle activation.
@MainActor
final class TouchInjector {

    // MARK: - Public API

    /// Simulate a tap at the given screen coordinates.
    /// - Parameter point: Point in screen coordinates
    /// - Returns: True if tap was dispatched successfully
    ///
    /// Note: This uses private UIKit APIs which may not work in all environments.
    /// On iOS 26+ Simulator, synthetic taps may not be available.
    func tap(at point: CGPoint) -> Bool {
        guard let window = getKeyWindow() else {
            print("[TouchInjector] No key window found")
            return false
        }

        // Convert screen coordinates to window coordinates
        let windowPoint = window.convert(point, from: nil)

        // First, try high-level approach: find the view and trigger its action
        if let hitView = window.hitTest(windowPoint, with: nil) {
            // Try to activate via accessibility
            if hitView.accessibilityActivate() {
                print("[TouchInjector] Activated via accessibilityActivate")
                return true
            }

            // Try sendActions for UIControl
            if let control = hitView as? UIControl {
                control.sendActions(for: .touchUpInside)
                print("[TouchInjector] Activated via sendActions")
                return true
            }

            // Walk up the responder chain to find a control
            var responder: UIResponder? = hitView
            while let r = responder {
                if let control = r as? UIControl {
                    control.sendActions(for: .touchUpInside)
                    print("[TouchInjector] Activated control in responder chain")
                    return true
                }
                responder = r.next
            }
        }

        // Low-level touch injection is disabled on iOS 26+ as the private APIs have changed.
        // The high-level methods (accessibilityActivate, sendActions) should be used instead.
        print("[TouchInjector] No tappable control found at coordinates")
        return false
    }

    // MARK: - Private Helpers

    private func getKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

}
#endif

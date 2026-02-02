#if canImport(UIKit)
import UIKit

/// Passthrough view controller for tap overlay
@MainActor
private class TapOverlayViewController: UIViewController {
    override func loadView() {
        let v = PassthroughView()
        v.backgroundColor = .clear
        self.view = v
    }
}

/// View that passes through all touches
@MainActor
private class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

/// Passthrough window for tap overlay
@MainActor
private class TapOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

/// Circle view for tap visualization
@MainActor
private class TapCircleView: UIView {
    init(at point: CGPoint, diameter: CGFloat) {
        let radius = diameter / 2
        super.init(frame: CGRect(x: point.x - radius, y: point.y - radius,
                                 width: diameter, height: diameter))
        backgroundColor = UIColor.white.withAlphaComponent(0.5)
        layer.cornerRadius = radius
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.4
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }
}

/// Visual indicator for tap actions. Shows a white 40x40 circle that scales up and fades out.
@MainActor
public enum TapVisualizerView {

    private static var overlayWindow: TapOverlayWindow?
    private static let diameter: CGFloat = 40.0
    private static let animationDuration: TimeInterval = 0.8

    /// Show the tap animation at the given point
    public static func showTap(at point: CGPoint) {
        // Get active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        // Create overlay window if needed
        if overlayWindow == nil || overlayWindow?.windowScene !== windowScene {
            let window = TapOverlayWindow(windowScene: windowScene)
            window.frame = windowScene.screen.bounds
            window.backgroundColor = .clear
            window.windowLevel = .statusBar + 100
            window.rootViewController = TapOverlayViewController()
            window.isUserInteractionEnabled = false
            window.makeKeyAndVisible()
            overlayWindow = window
        }

        guard let rootView = overlayWindow?.rootViewController?.view else { return }

        // Create and add circle
        let circle = TapCircleView(at: point, diameter: diameter)
        rootView.addSubview(circle)

        // Animate: scale up and fade out
        UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut) {
            circle.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            circle.alpha = 0
        } completion: { _ in
            circle.removeFromSuperview()
        }
    }
}
#endif

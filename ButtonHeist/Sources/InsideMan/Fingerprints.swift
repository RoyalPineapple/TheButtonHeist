#if canImport(UIKit)
#if DEBUG
import UIKit

/// Passthrough window for fingerprint overlay (internal so InsideMan can filter it from traversal)
@MainActor
class FingerprintWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Visual interaction indicators for tap and gesture tracking.
extension TheSafecracker {

    private static var fingerprintWindow: FingerprintWindow?
    private static var trackingCircles: [UIView] = []
    private static let fingerprintDiameter: CGFloat = 40.0
    private static let fingerprintAnimationDuration: TimeInterval = 0.8

    private func ensureFingerprintRootView() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
            return nil
        }

        if Self.fingerprintWindow == nil || Self.fingerprintWindow?.windowScene !== windowScene {
            let window = FingerprintWindow(windowScene: windowScene)
            window.frame = windowScene.screen.bounds
            window.backgroundColor = .clear
            window.windowLevel = .statusBar + 100
            let vc = UIViewController()
            let v = UIView()
            v.backgroundColor = .clear
            vc.view = v
            window.rootViewController = vc
            window.isUserInteractionEnabled = false
            window.isHidden = false
            Self.fingerprintWindow = window
        }

        return Self.fingerprintWindow?.rootViewController?.view
    }

    private func createCircleView(at point: CGPoint) -> UIView {
        let radius = Self.fingerprintDiameter / 2
        let circle = UIView(frame: CGRect(x: point.x - radius, y: point.y - radius,
                                          width: Self.fingerprintDiameter, height: Self.fingerprintDiameter))
        circle.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        circle.layer.cornerRadius = radius
        circle.layer.borderWidth = 2
        circle.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOffset = .zero
        circle.layer.shadowRadius = 4
        circle.layer.shadowOpacity = 0.4
        circle.isUserInteractionEnabled = false
        return circle
    }

    /// Show a fingerprint animation at the given point (for taps and instant actions).
    func showFingerprint(at point: CGPoint) {
        guard let rootView = ensureFingerprintRootView() else { return }

        let circle = createCircleView(at: point)
        rootView.addSubview(circle)

        UIView.animate(withDuration: Self.fingerprintAnimationDuration, delay: 0, options: .curveEaseOut) {
            circle.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            circle.alpha = 0
        } completion: { _ in
            circle.removeFromSuperview()
        }
    }

    /// Begin tracking fingerprints during a continuous gesture.
    /// Pass one point per finger. Animates in quickly from zero scale.
    func beginTrackingFingerprints(at points: [CGPoint]) {
        guard let rootView = ensureFingerprintRootView() else { return }

        Self.trackingCircles.forEach { $0.removeFromSuperview() }
        Self.trackingCircles = points.map { point in
            let circle = createCircleView(at: point)
            circle.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            circle.alpha = 0
            rootView.addSubview(circle)
            UIView.animate(withDuration: 0.12, delay: 0, options: .curveEaseOut) {
                circle.transform = .identity
                circle.alpha = 1
            }
            return circle
        }
    }

    /// Move tracking fingerprints to follow touch positions (one point per finger).
    func updateTrackingFingerprints(to points: [CGPoint]) {
        for (circle, point) in zip(Self.trackingCircles, points) {
            circle.center = point
        }
    }

    /// End tracking and slowly fade out all fingerprint circles.
    func endTrackingFingerprints() {
        let circles = Self.trackingCircles
        Self.trackingCircles = []
        for circle in circles {
            UIView.animate(withDuration: 0.6, delay: 0, options: .curveEaseOut) {
                circle.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                circle.alpha = 0
            } completion: { _ in
                circle.removeFromSuperview()
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

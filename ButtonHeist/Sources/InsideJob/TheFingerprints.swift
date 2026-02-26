#if canImport(UIKit)
#if DEBUG
import UIKit

/// Passthrough window for fingerprint overlay (internal so InsideJob can filter it from traversal)
@MainActor
class FingerprintWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Visual interaction indicators for tap and gesture tracking.
///
/// Extracted from a TheSafecracker extension so it can be used as a
/// standalone collaborator and eventually configured independently.
@MainActor
final class TheFingerprints {

    private var fingerprintWindow: FingerprintWindow?
    private var trackingCircles: [UIView] = []
    private let fingerprintDiameter: CGFloat = 40.0

    // MARK: - Configuration

    /// When `true`, all fingerprint indicators are suppressed (no-op).
    /// Checked once at init from `INSIDEJOB_DISABLE_FINGERPRINTS` env var
    /// or `InsideJobDisableFingerprints` Info.plist key.
    let isDisabled: Bool

    init() {
        // Environment variable takes priority
        if let envValue = ProcessInfo.processInfo.environment["INSIDEJOB_DISABLE_FINGERPRINTS"],
           ["1", "true", "yes"].contains(envValue.lowercased()) {
            self.isDisabled = true
        } else if let plistValue = Bundle.main.object(forInfoDictionaryKey: "InsideJobDisableFingerprints") as? Bool,
                  plistValue {
            self.isDisabled = true
        } else {
            self.isDisabled = false
        }
    }

    // MARK: - Timing Constants

    private static let minimumDisplayDuration: TimeInterval = 0.5
    private static let fadeOutDuration: TimeInterval = 0.5

    // MARK: - Root View

    private func ensureFingerprintRootView() -> UIView? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
            return nil
        }

        if fingerprintWindow == nil || fingerprintWindow?.windowScene !== windowScene {
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
            fingerprintWindow = window
        }

        return fingerprintWindow?.rootViewController?.view
    }

    // MARK: - Circle Factory

    private func createCircleView(at point: CGPoint) -> UIView {
        let radius = fingerprintDiameter / 2
        let circle = UIView(frame: CGRect(x: point.x - radius, y: point.y - radius,
                                          width: fingerprintDiameter, height: fingerprintDiameter))
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

    // MARK: - Instant Fingerprints (Taps)

    /// Show a fingerprint indicator at the given point (for taps and instant actions).
    /// Appears at full size, holds for `minimumDisplayDuration`, then fades out.
    func showFingerprint(at point: CGPoint) {
        guard !isDisabled else { return }
        guard let rootView = ensureFingerprintRootView() else { return }

        let circle = createCircleView(at: point)
        rootView.addSubview(circle)

        UIView.animate(
            withDuration: Self.fadeOutDuration,
            delay: Self.minimumDisplayDuration,
            options: .curveEaseOut
        ) {
            circle.alpha = 0
        } completion: { _ in
            circle.removeFromSuperview()
        }
    }

    // MARK: - Continuous Gesture Tracking

    /// Timestamp when tracking circles became fully visible, used to
    /// enforce the minimum display duration before fade-out.
    private var trackingStartTime: CFTimeInterval = 0

    /// Begin tracking fingerprints during a continuous gesture.
    /// Pass one point per finger. Animates in quickly from zero scale.
    func beginTrackingFingerprints(at points: [CGPoint]) {
        guard !isDisabled else { return }
        guard let rootView = ensureFingerprintRootView() else { return }

        trackingCircles.forEach { $0.removeFromSuperview() }
        trackingCircles = points.map { point in
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
        trackingStartTime = CACurrentMediaTime()
    }

    /// Move tracking fingerprints to follow touch positions (one point per finger).
    func updateTrackingFingerprints(to points: [CGPoint]) {
        guard !isDisabled else { return }
        for (circle, point) in zip(trackingCircles, points) {
            circle.center = point
        }
    }

    /// End tracking and fade out all fingerprint circles.
    /// Enforces the minimum display duration before starting the fade.
    func endTrackingFingerprints() {
        guard !isDisabled else { return }
        let circles = trackingCircles
        trackingCircles = []

        let elapsed = CACurrentMediaTime() - trackingStartTime
        let remainingHold = max(Self.minimumDisplayDuration - elapsed, 0)

        for circle in circles {
            UIView.animate(
                withDuration: Self.fadeOutDuration,
                delay: remainingHold,
                options: .curveEaseOut
            ) {
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

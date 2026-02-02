#if canImport(UIKit)
import UIKit

/// Visual indicator for tap actions, styled like iOS Simulator's touch indicators.
/// Shows a white circle that scales up and fades out.
@MainActor
final class TapVisualizerView: UIView {

    // Simulator-style constants
    private static let diameter: CGFloat = 44.0
    private static let borderWidth: CGFloat = 2.0
    private static let fillColor = UIColor.white.withAlphaComponent(0.3)
    private static let borderColor = UIColor.white.withAlphaComponent(0.8)
    private static let animationDuration: TimeInterval = 0.4

    init(center point: CGPoint) {
        let radius = Self.diameter / 2.0
        let frame = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: Self.diameter,
            height: Self.diameter
        )
        super.init(frame: frame)

        backgroundColor = Self.fillColor
        layer.borderWidth = Self.borderWidth
        layer.borderColor = Self.borderColor.cgColor
        layer.cornerRadius = radius
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return nil
    }

    /// Show the tap animation at the given point, then remove from view hierarchy.
    static func showTap(at point: CGPoint) {
        guard let window = getKeyWindow() else { return }

        let visualizer = TapVisualizerView(center: point)
        window.addSubview(visualizer)

        // Scale up and fade out
        UIView.animate(withDuration: animationDuration, delay: 0, options: .curveEaseOut) {
            visualizer.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
            visualizer.alpha = 0
        } completion: { _ in
            visualizer.removeFromSuperview()
        }
    }

    private static func getKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif

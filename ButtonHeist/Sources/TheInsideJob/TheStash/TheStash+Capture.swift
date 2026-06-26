#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Screen Capture

extension TheStash {

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = tripwire.getTraversableWindows()
        guard let plan = Self.makeScreenCapturePlan(for: windows) else { return nil }

        let renderer = UIGraphicsImageRenderer(size: plan.bounds.size)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
            for item in plan.windows.reversed() {
                context.saveGState()
                context.concatenate(item.transform)
                item.window.drawHierarchy(in: item.drawBounds, afterScreenUpdates: true)
                context.restoreGState()
            }
        }
        return (image, CGRect(origin: .zero, size: plan.bounds.size))
    }

    struct ScreenCapturePlan {
        let bounds: CGRect
        let windows: [ScreenCapturePlanWindow]
    }

    struct ScreenCapturePlanWindow {
        let window: UIWindow
        let drawBounds: CGRect
        let transform: CGAffineTransform
    }

    struct ScreenCaptureWindowGeometry {
        let frame: CGRect
        let bounds: CGRect
        let center: CGPoint
        let transform: CGAffineTransform

        init(
            frame: CGRect,
            bounds: CGRect,
            center: CGPoint,
            transform: CGAffineTransform
        ) {
            self.frame = frame
            self.bounds = bounds
            self.center = center
            self.transform = transform
        }

        @MainActor init(window: UIWindow) {
            self.init(
                frame: window.frame,
                bounds: window.bounds,
                center: window.center,
                transform: window.transform
            )
        }
    }

    static func makeScreenCapturePlan(
        for windows: [(window: UIWindow, rootView: UIView)]
    ) -> ScreenCapturePlan? {
        let captureWindows = windows
            .map { (window: $0.window, geometry: ScreenCaptureWindowGeometry(window: $0.window)) }
            .filter { isValidCaptureRect($0.geometry.frame) && isValidCaptureRect($0.geometry.bounds) }
        guard !captureWindows.isEmpty else { return nil }

        guard let bounds = screenCaptureBounds(for: captureWindows.map(\.geometry)) else { return nil }

        let plannedWindows = captureWindows.map { item in
            ScreenCapturePlanWindow(
                window: item.window,
                drawBounds: item.geometry.bounds,
                transform: screenCaptureTransform(for: item.geometry, relativeTo: bounds)
            )
        }

        return ScreenCapturePlan(
            bounds: CGRect(origin: .zero, size: bounds.size),
            windows: plannedWindows
        )
    }

    static func screenCaptureBounds(
        for windows: [ScreenCaptureWindowGeometry]
    ) -> CGRect? {
        let bounds = windows
            .map { $0.frame.standardized }
            .reduce(CGRect.null) { $0.union($1) }
        guard isValidCaptureRect(bounds) else { return nil }
        return bounds
    }

    static func screenCaptureTransform(
        for window: ScreenCaptureWindowGeometry,
        relativeTo captureBounds: CGRect
    ) -> CGAffineTransform {
        let translatedToCapture = CGAffineTransform(translationX: -captureBounds.minX, y: -captureBounds.minY)
            .translatedBy(x: window.center.x, y: window.center.y)
        return window.transform
            .concatenating(translatedToCapture)
            .translatedBy(x: -window.bounds.midX, y: -window.bounds.midY)
    }

    private static func isValidCaptureRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

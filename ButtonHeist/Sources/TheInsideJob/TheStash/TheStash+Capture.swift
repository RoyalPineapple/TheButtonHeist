#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Screen Capture

extension TheStash {

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = tripwire.getTraversableWindows()
        guard let background = windows.last else { return nil }
        let bounds = background.window.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
            for (window, _) in windows.reversed() {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        return (image, bounds)
    }

    /// Capture the screen including the fingerprint overlay (for recordings).
    /// Unlike captureScreen(), this includes TheFingerprints.FingerprintWindow so
    /// tap/swipe indicators are visible in the video. Collects visible windows
    /// from foreground-active scenes so system-managed popup windows are included
    /// without compositing inactive multi-window scenes into recordings.
    func captureScreenForRecording() -> UIImage? {
        let allWindows = TheTripwire.orderedVisibleWindows(includeFingerprints: true).reversed()

        guard let background = allWindows.first else { return nil }
        let bounds = background.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            for window in allWindows {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
    }

    /// If recording, capture a bonus frame to ensure the action's visual effect is captured.
    func captureActionFrame() async {
        if let stakeout {
            await stakeout.captureActionFrame()
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

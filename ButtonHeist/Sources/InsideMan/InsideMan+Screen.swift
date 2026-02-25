#if canImport(UIKit)
#if DEBUG
import UIKit
import TheGoods

extension InsideMan {

    // MARK: - Screen Capture

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = getTraversableWindows()
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

    func broadcastScreen() {
        guard !subscribedClients.isEmpty else { return }
        guard let (image, bounds) = captureScreen(),
              let pngData = image.pngData() else { return }

        let screenPayload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        if let data = try? JSONEncoder().encode(ServerMessage.screen(screenPayload)) {
            broadcastToSubscribed(data)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

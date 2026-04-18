#if canImport(UIKit)
#if DEBUG
import UIKit

/// Scene-aware replacement for `UIScreen.main`, which is deprecated in iOS 16+.
/// Resolves the active screen via the key window scene, then any foreground
/// scene, then the first connected scene, falling back to `UIScreen.main`
/// only when no scene is available.
@MainActor
enum ScreenMetrics {

    static var current: UIScreen {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyScene = scenes.first(where: { scene in
            scene.windows.contains(where: \.isKeyWindow)
        }) {
            return keyScene.screen
        }
        if let foregroundScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return foregroundScene.screen
        }
        if let firstScene = scenes.first {
            return firstScene.screen
        }
        return UIScreen.main
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

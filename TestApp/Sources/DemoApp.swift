import SwiftUI
import TheInsideJob

private enum TestAnimationClock {
    static let speed: Float? = {
        guard
            let rawValue = ProcessInfo.processInfo.environment["BUTTONHEIST_TEST_ANIMATION_SPEED"],
            let speed = Float(rawValue),
            speed.isFinite,
            speed > 0
        else {
            return nil
        }
        return speed
    }()

    @MainActor
    static func applyToVisibleWindows() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach(apply)
    }

    @MainActor
    static func apply(to window: UIWindow) {
        guard let speed else { return }
        window.layer.speed = speed
    }
}

@main
struct DemoApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(settings.colorScheme.resolved)
                .tint(settings.accentColor.color)
                .dynamicTypeSize(settings.textSize.dynamicTypeSize)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    TestAnimationClock.applyToVisibleWindows()
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: UIWindow.didBecomeVisibleNotification)
                ) { notification in
                    guard let window = notification.object as? UIWindow else { return }
                    TestAnimationClock.apply(to: window)
                }
        }
    }
}

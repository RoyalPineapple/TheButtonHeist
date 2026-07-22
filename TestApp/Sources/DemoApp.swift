import SwiftUI
import TheInsideJob

private enum TestAnimationPolicy {
    static let disablesAnimations =
        ProcessInfo.processInfo.environment["BUTTONHEIST_TEST_DISABLE_ANIMATIONS"] == "1"

    static func apply() {
        if disablesAnimations {
            UIView.setAnimationsEnabled(false)
        }
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
                    TestAnimationPolicy.apply()
                }
        }
    }
}

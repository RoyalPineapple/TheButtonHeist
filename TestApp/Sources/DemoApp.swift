import SwiftUI
import TheInsideJob

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
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                        UIView.setAnimationsEnabled(false)
                    }
                }
        }
    }
}

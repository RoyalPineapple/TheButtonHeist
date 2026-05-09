import SwiftUI
import TheInsideJob

@main
struct DemoApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .preferredColorScheme(settings.colorScheme.resolved)
                .tint(settings.accentColor.color)
                .dynamicTypeSize(settings.textSize.dynamicTypeSize)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

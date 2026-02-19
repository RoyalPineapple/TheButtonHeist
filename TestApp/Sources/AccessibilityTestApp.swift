import SwiftUI
import InsideMan

@main
struct AccessibilityTestApp: App {
    // InsideMan auto-starts via ObjC +load with port from Info.plist
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .preferredColorScheme(settings.colorScheme.resolved)
                .tint(settings.accentColor.color)
                .dynamicTypeSize(settings.textSize.dynamicTypeSize)
        }
    }
}

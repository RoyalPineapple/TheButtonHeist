import SwiftUI
import InsideMan

@main
struct AccessibilityTestApp: App {
    // InsideMan auto-starts via ObjC +load with port from Info.plist

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

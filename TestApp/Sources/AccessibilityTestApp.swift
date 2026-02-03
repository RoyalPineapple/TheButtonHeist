import SwiftUI
import AccraHost

@main
struct AccessibilityTestApp: App {
    // AccraHost auto-starts via ObjC +load with port from Info.plist

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

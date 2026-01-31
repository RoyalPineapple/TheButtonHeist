import SwiftUI
import AccraHost

@main
struct AccessibilityTestApp: App {
    init() {
        // Start the Accra host server
        try? AccraHost.shared.start()
        AccraHost.shared.startPolling(interval: 1.0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

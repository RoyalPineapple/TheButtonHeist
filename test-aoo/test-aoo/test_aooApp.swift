//
//  test_aooApp.swift
//  test-aoo
//
//  Created by aodawa on 31/01/2026.
//

import SwiftUI
import AccessibilityBridgeServer

@main
struct test_aooApp: App {
    init() {
        // Start the accessibility bridge server for remote inspection
        Task { @MainActor in
            do {
                try AccessibilityBridgeServer.shared.start()
                // Enable polling for automatic updates during development
                AccessibilityBridgeServer.shared.startPolling(interval: 0.5)
                print("[test-aoo] AccessibilityBridgeServer started with polling")
            } catch {
                print("[test-aoo] Failed to start AccessibilityBridgeServer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(autoStartDemo: true)
        }
    }
}

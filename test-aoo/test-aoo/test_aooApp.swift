//
//  test_aooApp.swift
//  test-aoo
//
//  Created by aodawa on 31/01/2026.
//

import SwiftUI
import AccessibilitySnapshotParser
import AccessibilityBridgeServer

@main
struct test_aooApp: App {
    init() {
        // Start the accessibility bridge server for remote inspection
        Task { @MainActor in
            do {
                try AccessibilityBridgeServer.shared.start()
                print("[test-aoo] AccessibilityBridgeServer started successfully")
            } catch {
                print("[test-aoo] Failed to start AccessibilityBridgeServer: \(error)")
            }
        }

        // Run exploration on launch after a short delay to let the UI set up
        // (Disabled by default - uncomment to run explorations)
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        //     runAllExplorations()
        // }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Run all explorations and print to console
func runAllExplorations() {
    print("\n" + String(repeating: "=", count: 60))
    print("ACCESSIBILITY EXPLORATION - AUTOMATIC RUN")
    print(String(repeating: "=", count: 60) + "\n")

    // 1. Parser approach
    print(">>> PHASE 1: AccessibilitySnapshotParser <<<\n")
    runParserExploration()

    print("\n" + String(repeating: "-", count: 60) + "\n")

    // 2. Private API approach
    print(">>> PHASE 2: Private API Exploration <<<\n")
    let explorer = PrivateAccessibilityExplorer.shared
    let output = explorer.runFullExploration()
    print(output)

    print("\n" + String(repeating: "-", count: 60) + "\n")

    // 3. SwiftUI Internals (Class Introspection)
    print(">>> PHASE 3: SwiftUI Accessibility Internals <<<\n")
    let swiftUIOutput = exploreSwiftUIAccessibility()
    print(swiftUIOutput)

    print("\n" + String(repeating: "-", count: 60) + "\n")

    // 4. AXRuntime Internals (SKIPPED - too verbose)
    print(">>> PHASE 4: AXRuntime Framework Internals <<<\n")
    print("   [Skipped - see ClassIntrospector.swift for full output]\n")
    // let axRuntimeOutput = exploreAXRuntimeInternals()
    // print(axRuntimeOutput)

    print("\n" + String(repeating: "-", count: 60) + "\n")

    // 5. External Client (ASAccessibilityEnabler-style)
    print(">>> PHASE 5: External Accessibility Client <<<\n")
    let externalOutput = exploreExternalAccessibility()
    print(externalOutput)

    print("\n" + String(repeating: "=", count: 60))
    print("EXPLORATION COMPLETE")
    print(String(repeating: "=", count: 60) + "\n")
}

func runParserExploration() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else {
        print("ERROR: Could not access window")
        return
    }

    guard let rootView = window.rootViewController?.view else {
        print("ERROR: Could not access root view")
        return
    }

    print("Window: \(window)")
    print("Root VC: \(String(describing: window.rootViewController))")
    print("Root View Type: \(type(of: rootView))")
    print("")

    // Use the AccessibilitySnapshotParser to traverse the hierarchy
    let parser = AccessibilityHierarchyParser()
    let markers = parser.parseAccessibilityElements(in: rootView)

    print("Found \(markers.count) accessibility elements:\n")

    for (index, marker) in markers.enumerated() {
        print("[\(index + 1)] \(marker.description)")
        if let label = marker.label {
            print("    Label: \(label)")
        }
        if let value = marker.value {
            print("    Value: \(value)")
        }
        if let hint = marker.hint {
            print("    Hint: \(hint)")
        }
        if let identifier = marker.identifier {
            print("    ID: \(identifier)")
        }
        print("    Traits: \(formatTraitsForConsole(marker.traits))")
        print("")
    }
}

private func formatTraitsForConsole(_ traits: UIAccessibilityTraits) -> String {
    var result: [String] = []
    if traits.contains(.button) { result.append("button") }
    if traits.contains(.link) { result.append("link") }
    if traits.contains(.header) { result.append("header") }
    if traits.contains(.image) { result.append("image") }
    if traits.contains(.staticText) { result.append("staticText") }
    if traits.contains(.selected) { result.append("selected") }
    if traits.contains(.adjustable) { result.append("adjustable") }
    if result.isEmpty { return "none" }
    return result.joined(separator: ", ")
}

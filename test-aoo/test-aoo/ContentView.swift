//
//  ContentView.swift
//  test-aoo
//
//  Created by aodawa on 31/01/2026.
//

import SwiftUI
import AccessibilitySnapshotParser

struct ContentView: View {
    @State private var accessibilityInfo: String = "Tap a button to inspect accessibility"

    var body: some View {
        VStack(spacing: 16) {
            // Sample UI elements with accessibility
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityLabel("Globe icon")

            Text("Hello, world!")
                .accessibilityLabel("Greeting")
                .accessibilityHint("A friendly greeting message")

            // Inspection buttons
            HStack(spacing: 12) {
                Button("Parser") {
                    inspectWithParser()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Inspect with parser")

                Button("Private API") {
                    explorePrivateAPIs()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Explore private APIs")
            }

            // Results
            ScrollView {
                Text(accessibilityInfo)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(maxHeight: 400)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding()
    }

    // MARK: - Parser Approach (Phase 1)

    private func inspectWithParser() {
        // Phase 1 approach: Access UIWindow from SwiftUI app via connectedScenes
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            let msg = "ERROR: Could not access window"
            print(msg)
            accessibilityInfo = msg
            return
        }

        guard let rootView = window.rootViewController?.view else {
            let msg = "ERROR: Could not access root view"
            print(msg)
            accessibilityInfo = msg
            return
        }

        var output = "=== AccessibilitySnapshotParser Results ===\n\n"
        output += "Window: \(window)\n"
        output += "Root VC: \(String(describing: window.rootViewController))\n"
        output += "Root View: \(type(of: rootView))\n\n"

        // Use the AccessibilitySnapshotParser to traverse the hierarchy
        let parser = AccessibilityHierarchyParser()
        let markers = parser.parseAccessibilityElements(in: rootView)

        output += "Found \(markers.count) accessibility elements:\n\n"
        for (index, marker) in markers.enumerated() {
            output += "[\(index + 1)] \(marker.description)\n"
            if let label = marker.label {
                output += "    Label: \(label)\n"
            }
            if let value = marker.value {
                output += "    Value: \(value)\n"
            }
            if let hint = marker.hint {
                output += "    Hint: \(hint)\n"
            }
            if let identifier = marker.identifier {
                output += "    ID: \(identifier)\n"
            }
            output += "    Traits: \(formatTraits(marker.traits))\n"
            output += "\n"
        }

        // Print to console
        print("\n>>> PARSER BUTTON PRESSED <<<")
        print(output)

        accessibilityInfo = output
    }

    // MARK: - Private API Exploration (Phase 2)

    private func explorePrivateAPIs() {
        print("\n>>> PRIVATE API BUTTON PRESSED <<<")
        let explorer = PrivateAccessibilityExplorer.shared
        let output = explorer.runFullExploration()
        print(output)
        accessibilityInfo = output
    }

    private func formatTraits(_ traits: UIAccessibilityTraits) -> String {
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
}

#Preview {
    ContentView()
}

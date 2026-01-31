import SwiftUI
import AccessibilityBridgeProtocol

struct ContentView: View {
    @State private var browser = BonjourBrowser()
    @State private var selectedDeviceName: String?

    // Sample data for testing the UI
    private let sampleElements: [AccessibilityElementData] = [
        AccessibilityElementData(
            traversalIndex: 0,
            description: "Navigation Bar",
            label: "My App",
            value: nil,
            traits: ["header"],
            identifier: "navBar",
            hint: nil,
            frameX: 0, frameY: 0, frameWidth: 393, frameHeight: 44,
            activationPointX: 196.5, activationPointY: 22,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 1,
            description: "Welcome message",
            label: "Hello, World!",
            value: nil,
            traits: ["staticText"],
            identifier: nil,
            hint: nil,
            frameX: 16, frameY: 100, frameWidth: 361, frameHeight: 24,
            activationPointX: 196.5, activationPointY: 112,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 2,
            description: "Submit Button",
            label: "Submit",
            value: nil,
            traits: ["button"],
            identifier: "submitBtn",
            hint: "Double tap to submit the form",
            frameX: 100, frameY: 200, frameWidth: 193, frameHeight: 44,
            activationPointX: 196.5, activationPointY: 222,
            customActions: ["Delete", "Edit"]
        ),
        AccessibilityElementData(
            traversalIndex: 3,
            description: "Email Input",
            label: "Email",
            value: "user@example.com",
            traits: ["textField"],
            identifier: "emailField",
            hint: "Enter your email address",
            frameX: 16, frameY: 260, frameWidth: 361, frameHeight: 44,
            activationPointX: 196.5, activationPointY: 282,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 4,
            description: "Learn More Link",
            label: "Learn more about our service",
            value: nil,
            traits: ["link"],
            identifier: nil,
            hint: nil,
            frameX: 16, frameY: 320, frameWidth: 200, frameHeight: 20,
            activationPointX: 116, activationPointY: 330,
            customActions: []
        ),
        AccessibilityElementData(
            traversalIndex: 5,
            description: "Profile Image",
            label: "User profile picture",
            value: nil,
            traits: ["image"],
            identifier: "profileImg",
            hint: nil,
            frameX: 300, frameY: 50, frameWidth: 60, frameHeight: 60,
            activationPointX: 330, activationPointY: 80,
            customActions: []
        )
    ]

    var body: some View {
        NavigationSplitView {
            List(browser.devices, id: \.name, selection: $selectedDeviceName) { device in
                Label(device.name, systemImage: "iphone")
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem {
                    Button(action: { browser.startBrowsing() }) {
                        Image(systemName: browser.isSearching ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                    }
                }
            }
        } detail: {
            if selectedDeviceName != nil {
                // Show demo HierarchyListView with sample data
                HierarchyListView(elements: sampleElements)
            } else {
                Text("Select a device")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
    }
}

#Preview {
    ContentView()
}

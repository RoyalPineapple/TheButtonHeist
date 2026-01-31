import SwiftUI
import AccessibilityBridgeProtocol

struct ContentView: View {
    @State private var browser = BonjourBrowser()
    @State private var selectedDeviceName: String?

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
            if let name = selectedDeviceName {
                Text("Selected: \(name)")
            } else {
                Text("No selection")
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

import SwiftUI
import AccessibilityBridgeProtocol

struct ContentView: View {
    @State private var browser = BonjourBrowser()
    @State private var client = WebSocketClient()
    @State private var selectedDevice: BonjourBrowser.DiscoveredDevice?

    var body: some View {
        NavigationSplitView {
            // Sidebar: Device list
            List(browser.devices, selection: $selectedDevice) { device in
                Label(device.name, systemImage: "iphone")
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem {
                    Button(action: { browser.startBrowsing() }) {
                        Image(systemName: browser.isSearching ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                    }
                    .help(browser.isSearching ? "Searching..." : "Refresh devices")
                }
            }
        } detail: {
            // Detail: Hierarchy view
            if case let .connected(info) = client.state {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text(info.appName)
                                .font(.headline)
                            Text("\(info.deviceName) • iOS \(info.systemVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let updateTime = client.lastUpdateTime {
                            Text("Updated: \(updateTime.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Refresh") {
                            client.requestHierarchy()
                        }
                    }
                    .padding()
                    .background(.bar)

                    Divider()

                    // Element list
                    HierarchyListView(elements: client.elements)
                }
            } else if case .connecting = client.state {
                ProgressView("Connecting...")
            } else if case let .error(message) = client.state {
                ContentUnavailableView(
                    "Connection Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else {
                ContentUnavailableView(
                    "No Device Selected",
                    systemImage: "iphone.slash",
                    description: Text("Select an iOS device from the sidebar to inspect its accessibility hierarchy")
                )
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onChange(of: selectedDevice) { oldValue, newValue in
            if let device = newValue {
                client.connect(to: device.endpoint)
            } else {
                client.disconnect()
            }
        }
    }
}

#Preview {
    ContentView()
}

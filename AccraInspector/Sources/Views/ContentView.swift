import SwiftUI
import AccraCore
import AccraClient

struct ContentView: View {
    @StateObject private var client = AccraClient()
    @State private var selectedDevice: DiscoveredDevice?

    var body: some View {
        NavigationSplitView {
            List(client.discoveredDevices, selection: $selectedDevice) { device in
                Label(client.displayName(for: device), systemImage: "iphone")
                    .tag(device)
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem {
                    Button(action: { client.startDiscovery() }) {
                        Image(systemName: client.isDiscovering ? "antenna.radiowaves.left.and.right" : "arrow.clockwise")
                    }
                }
            }
        } detail: {
            detailView
        }
        .onChange(of: selectedDevice) { _, newDevice in
            if let device = newDevice {
                client.connect(to: device)
            } else {
                client.disconnect()
            }
        }
        .onAppear {
            client.startDiscovery()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch client.connectionState {
        case .connected:
            if let hierarchy = client.currentHierarchy {
                HierarchyListView(elements: hierarchy.elements)
            } else {
                ProgressView("Loading hierarchy...")
            }
        case .connecting:
            ProgressView("Connecting...")
        case .failed(let error):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                Text("Connection Failed")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .disconnected:
            Text("Select a device")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}

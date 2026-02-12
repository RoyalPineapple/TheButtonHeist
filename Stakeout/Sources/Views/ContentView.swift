import SwiftUI
import ButtonHeist

struct ContentView: View {
    @StateObject private var client = HeistClient()
    @State private var selectedDevice: DiscoveredDevice?
    @State private var selectedElement: UIElement?
    @State private var showTreeView = true

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
            if let hierarchy = client.currentSnapshot {
                HStack(spacing: 0) {
                    // Left: Element list (tree or flat)
                    VStack(spacing: 0) {
                        // View mode toggle
                        HStack {
                            Picker("View", selection: $showTreeView) {
                                Image(systemName: "list.bullet.indent")
                                    .tag(true)
                                Image(systemName: "list.bullet")
                                    .tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 80)
                            .help(showTreeView ? "Tree View" : "Flat List")
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .windowBackgroundColor))

                        Divider()

                        if showTreeView, let tree = hierarchy.tree {
                            HierarchyTreeView(
                                tree: tree,
                                elements: hierarchy.elements,
                                selectedElement: $selectedElement
                            )
                        } else {
                            HierarchyListView(
                                elements: hierarchy.elements,
                                selectedElement: $selectedElement
                            )
                        }
                    }
                    .frame(width: 280)

                    Divider()

                    // Middle: Screenshot (centered, not expanding)
                    ScreenshotView(
                        screenshotPayload: client.currentScreenshot,
                        elements: hierarchy.elements,
                        selectedElement: $selectedElement,
                        onActivate: { element in
                            activateElement(element)
                        }
                    )
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Right: Inspector (always visible)
                    inspectorPane
                        .frame(width: 250)
                }
                .safeAreaInset(edge: .bottom) {
                    if let device = client.connectedDevice {
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected to \(device.name)")
                                .font(.caption)
                            Spacer()
                            Text("Updated: \(hierarchy.timestamp.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(.bar)
                    }
                }
            } else {
                ProgressView("Loading...")
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

    @ViewBuilder
    private var inspectorPane: some View {
        if let element = selectedElement {
            ElementInspectorView(
                element: element,
                onActivate: { activateElement(element) }
            )
        } else {
            VStack {
                Spacer()
                Text("Select an element")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func activateElement(_ element: UIElement) {
        let target = ActionTarget(
            identifier: element.identifier,
            order: element.order
        )
        client.send(.activate(target))
    }
}

#Preview {
    ContentView()
}

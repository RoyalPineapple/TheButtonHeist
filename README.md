# Accra

**Accessibility inspection toolkit for iOS apps**

Accra lets you inspect the accessibility hierarchy of iOS apps in real-time from your Mac. Connect to any iOS app running AccraHost over your local network to see how VoiceOver and other assistive technologies perceive your UI.

## Features

- **Real-time inspection** — See accessibility elements update as your app's UI changes
- **Bonjour discovery** — Automatically find iOS devices running AccraHost on your network
- **Multiple interfaces** — GUI app for visual inspection, CLI for scripting and CI
- **Clean API** — AccraClient provides an `ObservableObject` for easy SwiftUI integration
- **Cross-platform types** — Shared data models work on both iOS and macOS

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Your Mac                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  AccraInspector  │  │    accra CLI     │  │   Your Tool      │  │
│  │    (GUI app)     │  │                  │  │                  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │            │
│           └─────────────────────┼─────────────────────┘            │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │   AccraClient   │  ← Bonjour + WebSocket  │
│                        │   (framework)   │                         │
│                        └────────┬────────┘                         │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ Local Network
┌─────────────────────────────────┼───────────────────────────────────┐
│                        ┌────────┴────────┐                         │
│                        │   AccraHost     │  ← Embedded in your app │
│                        │   (framework)   │                         │
│                        └────────┬────────┘                         │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │  Your iOS App   │                         │
│                        └─────────────────┘                         │
│                           iOS Device                                │
└─────────────────────────────────────────────────────────────────────┘
```

## Modules

| Module | Platform | Description |
|--------|----------|-------------|
| **AccraCore** | iOS + macOS | Shared types, messages, and constants |
| **AccraHost** | iOS | Server that exposes accessibility hierarchy over WebSocket |
| **AccraClient** | macOS | Client library for discovery and connection |
| **AccraInspector** | macOS | GUI app for visual inspection |
| **accra** | macOS | CLI tool for scripting and automation |

## Quick Start

### 1. Add AccraHost to Your iOS App

Add the AccraCore package to your project and import AccraHost:

```swift
import AccraHost

@main
struct MyApp: App {
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
```

For UIKit apps:

```swift
import AccraHost

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        try? AccraHost.shared.start()
        AccraHost.shared.startPolling(interval: 1.0)
        return true
    }
}
```

Add the required Info.plist entries for local network access:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the accessibility inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_a11ybridge._tcp</string>
</array>
```

### 2. Run the Inspector

**GUI App:**
```bash
# Build and run the inspector app
tuist generate
open Accra.xcworkspace
# Run the AccraInspector scheme
```

**CLI:**
```bash
cd AccraCLI
swift run accra --once    # Single snapshot
swift run accra           # Watch mode (live updates)
swift run accra --format json --once | jq .  # JSON for scripting
```

### 3. Connect

1. Run your iOS app on a device or simulator
2. Launch AccraInspector or the CLI on your Mac
3. Your device will appear automatically via Bonjour
4. Select it to connect and view the accessibility hierarchy

## CLI Usage

```
USAGE: accra [--format <format>] [--once] [--quiet] [--timeout <timeout>] [--verbose]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit (default: watch mode)
  -q, --quiet             Suppress status messages (only output data)
  -t, --timeout <timeout> Timeout in seconds waiting for device (default: 0)
  -v, --verbose           Show verbose output
  -h, --help              Show help information.
```

**Examples:**

```bash
# Interactive watch mode - see live updates
accra

# Single snapshot in human-readable format
accra --once

# JSON output for scripting
accra --format json --once

# Quiet mode - only data, no status messages
accra -q --once

# With timeout
accra --timeout 10 --once
```

## Using AccraClient in Your Own Tools

AccraClient provides a clean API for building custom accessibility tools:

```swift
import AccraClient
import AccraCore

@MainActor
class MyInspector: ObservableObject {
    let client = AccraClient()

    init() {
        // Start discovering devices
        client.startDiscovery()
    }

    func connect(to device: DiscoveredDevice) {
        client.connect(to: device)
    }
}
```

**SwiftUI Integration:**

```swift
struct InspectorView: View {
    @StateObject private var client = AccraClient()

    var body: some View {
        List(client.discoveredDevices) { device in
            Button(device.name) {
                client.connect(to: device)
            }
        }
        .onAppear {
            client.startDiscovery()
        }
    }
}
```

**Callback-based usage (for non-SwiftUI):**

```swift
let client = AccraClient()

client.onDeviceDiscovered = { device in
    print("Found: \(device.name)")
    client.connect(to: device)
}

client.onHierarchyUpdate = { payload in
    for element in payload.elements {
        print("\(element.label ?? element.description)")
    }
}

client.startDiscovery()
```

## Data Model

### AccessibilityElementData

Each element in the hierarchy contains:

| Property | Type | Description |
|----------|------|-------------|
| `traversalIndex` | `Int` | VoiceOver reading order |
| `description` | `String` | Accessibility description |
| `label` | `String?` | Accessibility label |
| `value` | `String?` | Current value (for controls) |
| `traits` | `[String]` | Traits like "button", "header", etc. |
| `identifier` | `String?` | Accessibility identifier |
| `hint` | `String?` | Accessibility hint |
| `frameX/Y/Width/Height` | `Double` | Screen coordinates |
| `activationPointX/Y` | `Double` | Touch target center |
| `customActions` | `[String]` | Custom action names |

## Development Setup

### Prerequisites

- Xcode 15+
- [Tuist](https://tuist.io) for project generation
- iOS 17+ / macOS 14+

### Building

```bash
# Install Tuist if needed
curl -Ls https://install.tuist.io | bash

# Generate Xcode project
tuist generate

# Open workspace
open Accra.xcworkspace
```

### Project Structure

```
accra/
├── AccraCore/
│   └── Sources/
│       ├── AccraCore/       # Shared types (Messages.swift)
│       ├── AccraHost/       # iOS server
│       └── AccraClient/     # macOS client library
├── AccraInspector/
│   └── Sources/             # macOS GUI app
├── AccraCLI/
│   └── Sources/             # CLI tool
├── TestApp/
│   ├── Sources/             # SwiftUI test app
│   └── UIKitSources/        # UIKit test app
├── Project.swift            # Tuist configuration
└── Workspace.swift
```

### Running Tests

```bash
# Build all targets
xcodebuild -workspace Accra.xcworkspace -scheme AccraCore build
xcodebuild -workspace Accra.xcworkspace -scheme AccraHost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -workspace Accra.xcworkspace -scheme AccraClient build
xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector build

# Run CLI
cd AccraCLI && swift run accra --help
```

## Wire Protocol

Communication uses JSON over WebSocket:

**Client → Server:**
- `requestHierarchy` — Request current hierarchy
- `subscribe` — Subscribe to automatic updates
- `unsubscribe` — Stop receiving updates
- `ping` — Keepalive

**Server → Client:**
- `info` — Server info on connection
- `hierarchy` — Accessibility hierarchy data
- `pong` — Ping response
- `error` — Error message

Bonjour service type: `_a11ybridge._tcp`

## Troubleshooting

### Device not appearing

1. Ensure both devices are on the same network
2. Check that AccraHost is started in your app
3. Verify Info.plist has the Bonjour service entry
4. On iOS, accept the local network permission prompt

### Connection fails immediately

- Check that no firewall is blocking the connection
- The iOS app must be in the foreground initially
- Try restarting the app

### Empty hierarchy

- Ensure the app has visible UI
- Check that `startPolling()` is called
- The root view must be accessible to UIAccessibility

## License

MIT

## Acknowledgments

Built on [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) for parsing UIKit accessibility hierarchies.

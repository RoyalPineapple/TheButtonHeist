# Accra

**Accessibility inspection and automation toolkit for iOS apps**

Accra lets you inspect and interact with the accessibility hierarchy of iOS apps in real-time from your Mac. Connect to any iOS app running AccraHost over local network or USB to see how VoiceOver perceives your UI, and automate accessibility testing.

## Features

- **Real-time inspection** - See accessibility elements update as your app's UI changes
- **Remote actions** - Tap elements and trigger actions programmatically
- **USB connectivity** - Connect to devices over USB when WiFi is unavailable
- **Auto-start** - AccraHost starts automatically when your app launches
- **Fixed port** - Predictable port (1455) for reliable scripted connections
- **Multiple interfaces** - GUI app, CLI, Python, or custom tools

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Your Mac                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  AccraInspector  │  │    accra CLI     │  │  Python/Scripts  │  │
│  │    (GUI app)     │  │                  │  │                  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │            │
│           └─────────────────────┼─────────────────────┘            │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │   AccraClient   │  ← Bonjour discovery    │
│                        │   (framework)   │    or direct TCP        │
│                        └────────┬────────┘                         │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ Local Network / USB (IPv6)
┌─────────────────────────────────┼───────────────────────────────────┐
│                        ┌────────┴────────┐                         │
│                        │   AccraHost     │  ← Auto-starts on load  │
│                        │   (framework)   │    Port 1455            │
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
| **AccraHost** | iOS | Server that exposes accessibility hierarchy over TCP |
| **AccraClient** | macOS | Client library for discovery and connection |
| **AccraInspector** | macOS | GUI app for visual inspection |
| **accra** | macOS | CLI tool for scripting and automation |

## Quick Start

### 1. Add AccraHost to Your iOS App

Add the AccraCore package to your project and import AccraHost. **AccraHost auto-starts via ObjC +load** - no code changes needed beyond importing the framework.

**SwiftUI:**
```swift
import SwiftUI
import AccraHost

@main
struct MyApp: App {
    // AccraHost auto-starts via ObjC +load with port from Info.plist

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**UIKit:**
```swift
import UIKit
import AccraHost

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // AccraHost auto-starts via ObjC +load with port from Info.plist
        return true
    }
}
```

Add the required Info.plist entries:

```xml
<!-- Fixed port for AccraHost (required) -->
<key>AccraHostPort</key>
<integer>1455</integer>

<!-- Network permissions -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the accessibility inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_a11ybridge._tcp</string>
</array>
```

### 2. Connect

**Over USB (recommended):**
```bash
# Quick connection script
./scripts/usb-connect.sh "Your Device Name"

# Python
python3 scripts/accra_usb.py
```

**Over WiFi:**
```bash
cd AccraCLI
swift run accra --once    # Single snapshot
swift run accra           # Watch mode (live updates)
```

**GUI App:**
```bash
tuist generate
open Accra.xcworkspace
# Run the AccraInspector scheme
```

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
```

## USB Connectivity

When WiFi is unreliable (VPN, network segmentation), connect over USB using the CoreDevice IPv6 tunnel.

**Quick connect:**
```bash
./scripts/usb-connect.sh "iPhone 15 Pro"
```

**Python:**
```python
from scripts.accra_usb import AccraUSBConnection

with AccraUSBConnection() as conn:
    print(f"Connected to: {conn.info['appName']}")
    hierarchy = conn.get_hierarchy()

    # Interact with elements
    conn.activate(identifier="loginButton")
    conn.tap(x=196.5, y=659)
```

**Manual:**
```bash
# Find device IPv6
lsof -i -P -n | grep CoreDev

# Connect directly
nc -6 fd9a:6190:eed7::1 1455
```

See [docs/USB_DEVICE_CONNECTIVITY.md](docs/USB_DEVICE_CONNECTIVITY.md) for details.

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

### Building for Device (Command Line)

```bash
# Build with signing
xcodebuild -workspace Accra.xcworkspace \
  -scheme AccessibilityTestApp \
  -destination 'platform=iOS,name=Your Device' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build

# Install
xcrun devicectl device install app \
  --device "Your Device" \
  ~/Library/Developer/Xcode/DerivedData/Accra-*/Build/Products/Debug-iphoneos/AccessibilityTestApp.app
```

### Project Structure

```
accra/
├── AccraCore/
│   └── Sources/
│       ├── AccraCore/       # Shared types (Messages.swift)
│       ├── AccraHost/       # iOS server
│       ├── AccraHostLoader/ # ObjC auto-start
│       └── AccraClient/     # macOS client library
├── AccraInspector/
│   └── Sources/             # macOS GUI app
├── AccraCLI/
│   └── Sources/             # CLI tool
├── TestApp/
│   ├── Sources/             # SwiftUI test app
│   └── UIKitSources/        # UIKit test app
├── scripts/
│   ├── usb-connect.sh       # USB connection helper
│   └── accra_usb.py         # Python USB module
├── docs/
│   └── USB_DEVICE_CONNECTIVITY.md
├── Project.swift            # Tuist configuration
└── Workspace.swift
```

## Wire Protocol

Communication uses newline-delimited JSON over TCP:

**Client → Server:**
- `requestHierarchy` - Request current hierarchy
- `activate` - Activate element (VoiceOver double-tap)
- `tap` - Tap at coordinates or element
- `ping` - Keepalive

**Server → Client:**
- `info` - Server info on connection
- `hierarchy` - Accessibility hierarchy data
- `actionResult` - Result of activate/tap
- `pong` - Ping response

**Port:** 1455 (configurable via Info.plist)
**Bonjour service:** `_a11ybridge._tcp`

## Troubleshooting

### Device not appearing (WiFi)

1. Ensure both devices are on the same network
2. Check that AccraHost framework is linked
3. Verify Info.plist has the Bonjour service entry
4. On iOS, accept the local network permission prompt

### USB connection refused

1. Check device is connected: `xcrun devicectl list devices`
2. Verify app is running on device
3. Check port in Info.plist matches (default: 1455)
4. Find IPv6 tunnel: `lsof -i -P -n | grep CoreDev`

### Empty hierarchy

- Ensure the app has visible UI
- The root view must be accessible to UIAccessibility

## Documentation

- [USB Device Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) - USB connection guide
- [Architecture](docs/ARCHITECTURE.md) - System design and data flow
- [Wire Protocol](docs/WIRE-PROTOCOL.md) - Complete protocol specification
- [API Reference](docs/API.md) - Detailed API documentation
- [Contributing Guide](CONTRIBUTING.md) - How to contribute
- [Changelog](CHANGELOG.md) - Version history

## License

MIT

## Acknowledgments

Built on [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) for parsing UIKit accessibility hierarchies.

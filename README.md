# ButtonHeist

**Let AI agents drive iOS apps**

ButtonHeist gives AI agents (and humans) full control over iOS apps. Embed InsideMan in your app, then connect with the MCP server to let Claude inspect UI, tap buttons, swipe, type, and navigate — all programmatically over a persistent connection.

## Features

- **MCP server** - Model Context Protocol server lets AI agents like Claude drive any iOS app
- **Real-time inspection** - See UI elements update as your app's UI changes
- **Remote actions** - Tap elements and trigger actions programmatically
- **Touch gestures** - Full gesture simulation: tap, long press, swipe, drag, pinch, rotate, two-finger tap
- **Multi-touch** - Simultaneous multi-finger gesture injection via IOKit HID events
- **USB connectivity** - Connect to devices over USB when WiFi is unavailable
- **Auto-start** - InsideMan starts automatically when your app launches
- **Fixed port** - Predictable port (1455) for reliable scripted connections
- **Multiple interfaces** - MCP server, GUI app, CLI, Python, or custom tools

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Your Mac                                   │
│                                                                      │
│  ┌──────────────────┐                                               │
│  │  AI Agent        │  (Claude, or any MCP client)                  │
│  │  (e.g. Claude)   │                                               │
│  └────────┬─────────┘                                               │
│           │ MCP (JSON-RPC over stdio)                                │
│  ┌────────┴─────────┐                                               │
│  │ buttonheist-mcp  │  ← Persistent connection, no per-call overhead│
│  │  (MCP server)    │                                               │
│  └────────┬─────────┘                                               │
│           │                                                          │
│  ┌────────┴─────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │     Stakeout     │  │  buttonheist CLI │  │  Python/Scripts  │  │
│  │    (GUI app)     │  │                  │  │                  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │            │
│           └─────────────────────┼─────────────────────┘            │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │   ButtonHeist   │  ← Bonjour discovery    │
│                        │  (HeistClient)  │    or direct TCP        │
│                        └────────┬────────┘                         │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ Local Network / USB (IPv6)
┌─────────────────────────────────┼───────────────────────────────────┐
│                        ┌────────┴────────┐                         │
│                        │    InsideMan    │  ← Auto-starts on load  │
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
| **TheGoods** | iOS + macOS | Shared types, messages, and constants |
| **InsideMan** | iOS | Server that exposes UI element snapshot over TCP, with synthetic touch injection |
| **Wheelman** | iOS + macOS | Cross-platform networking (TCP server/client, Bonjour discovery) |
| **ButtonHeist** | macOS | Client framework with HeistClient class; re-exports TheGoods + Wheelman |
| **ButtonHeistMCP** | macOS | MCP server — lets AI agents drive iOS apps via Model Context Protocol |
| **Stakeout** | macOS | GUI app for visual inspection with screenshots and element overlays |
| **buttonheist** | macOS | CLI tool with watch, action, touch, and screenshot commands |

## Quick Start

### 1. Add InsideMan to Your iOS App

Add the ButtonHeist package to your project and import InsideMan. **InsideMan auto-starts via ObjC +load** - no code changes needed beyond importing the framework.

**SwiftUI:**
```swift
import SwiftUI
import InsideMan

@main
struct MyApp: App {
    // InsideMan auto-starts via ObjC +load with port from Info.plist

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
import InsideMan

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // InsideMan auto-starts via ObjC +load with port from Info.plist
        return true
    }
}
```

Add the required Info.plist entries:

```xml
<!-- Fixed port for InsideMan (required) -->
<key>InsideManPort</key>
<integer>1455</integer>

<!-- Network permissions -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the element inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### 2. Connect with an AI Agent (MCP)

The MCP server gives AI agents like Claude persistent access to your app. Build once, then point your MCP client at the binary:

```bash
# Build the MCP server
cd ButtonHeistMCP
swift build -c release
```

Add to your Claude Code `.mcp.json` (or any MCP client config):

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "/path/to/ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

The MCP server automatically discovers your iOS app via Bonjour and connects. It exposes 13 tools:

| Tool | Description |
|------|-------------|
| `get_snapshot` | Read the full UI element hierarchy |
| `get_screenshot` | Capture a PNG screenshot |
| `tap` | Tap an element or coordinate |
| `long_press` | Long press with configurable duration |
| `swipe` | Swipe by direction or between coordinates |
| `drag` | Drag between two points |
| `pinch` | Pinch/zoom gesture |
| `rotate` | Two-finger rotation |
| `two_finger_tap` | Simultaneous two-finger tap |
| `activate` | Accessibility activate (VoiceOver double-tap) |
| `increment` / `decrement` | Adjust sliders, steppers, pickers |
| `perform_custom_action` | Invoke named custom accessibility actions |

The MCP server maintains a persistent TCP connection to the device, so there's no connection overhead between tool calls — AI agents can chain dozens of interactions without delay.

### 3. Connect Manually

**Over USB (recommended):**
```bash
# Quick connection script
./scripts/usb-connect.sh "Your Device Name"

# Python
python3 scripts/buttonheist_usb.py
```

**Over WiFi:**
```bash
cd ButtonHeistCLI
swift run buttonheist --once    # Single snapshot
swift run buttonheist           # Watch mode (live updates)
```

**GUI App:**
```bash
tuist generate
open ButtonHeist.xcworkspace
# Run the Stakeout scheme
```

## CLI Usage

The CLI has four subcommands: `watch` (default), `action`, `touch`, and `screenshot`.

### watch (default)

```
USAGE: buttonheist watch [--format <format>] [--once] [--quiet] [--timeout <timeout>] [--verbose]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit (default: watch mode)
  -q, --quiet             Suppress status messages (only output data)
  -t, --timeout <timeout> Timeout in seconds waiting for device (default: 0)
  -v, --verbose           Show verbose output
```

### action

```
USAGE: buttonheist action [--identifier <id>] [--index <n>] [--type <type>] [--custom-action <name>] [--x <x>] [--y <y>] [--timeout <t>] [--quiet]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Traversal index
  --type <type>           Action: activate, increment, decrement, tap, custom (default: activate)
  --custom-action <name>  Custom action name (when type is 'custom')
  --x <x>, --y <y>       Tap coordinates (when type is 'tap')
  -t, --timeout <t>       Timeout in seconds (default: 10)
```

### touch

```
USAGE: buttonheist touch <subcommand>

SUBCOMMANDS:
  tap                     Tap at a point or element
  longpress               Long press at a point or element
  swipe                   Swipe between two points or in a direction
  drag                    Drag from one point to another
  pinch                   Pinch/zoom at a point or element
  rotate                  Rotate at a point or element
  two-finger-tap          Tap with two fingers at a point or element
```

All touch subcommands accept `--identifier`, `--index`, or coordinate options to specify the target.

### screenshot

```
USAGE: buttonheist screenshot [--output <path>] [--timeout <t>] [--quiet]

OPTIONS:
  -o, --output <path>     Output file path (default: stdout as raw PNG)
  -t, --timeout <t>       Timeout in seconds (default: 10)
```

**Examples:**

```bash
# Interactive watch mode - see live updates
buttonheist

# Single snapshot in human-readable format
buttonheist --once

# JSON output for scripting
buttonheist --format json --once

# Activate a button by identifier
buttonheist action --identifier loginButton

# Tap at coordinates
buttonheist action --type tap --x 196.5 --y 659

# Increment a slider
buttonheist action --type increment --identifier volumeSlider

# Capture screenshot to file
buttonheist screenshot --output screen.png

# Pipe screenshot to another tool
buttonheist screenshot | imgcat

# Touch gestures
buttonheist touch tap --identifier loginButton
buttonheist touch tap --x 100 --y 200
buttonheist touch longpress --identifier myButton --duration 1.0
buttonheist touch swipe --identifier list --direction up
buttonheist touch swipe --from-x 200 --from-y 400 --to-x 200 --to-y 100
buttonheist touch drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist touch pinch --identifier mapView --scale 2.0
buttonheist touch rotate --x 200 --y 300 --angle 1.57
buttonheist touch two-finger-tap --identifier zoomControl
```

## USB Connectivity

When WiFi is unreliable (VPN, network segmentation), connect over USB using the CoreDevice IPv6 tunnel.

**Quick connect:**
```bash
./scripts/usb-connect.sh "iPhone 15 Pro"
```

**Python:**
```python
from scripts.buttonheist_usb import ButtonHeistUSBConnection

with ButtonHeistUSBConnection() as conn:
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

### UIElement

Each element in the hierarchy contains:

| Property | Type | Description |
|----------|------|-------------|
| `order` | `Int` | Element reading order |
| `description` | `String` | Description |
| `label` | `String?` | Label |
| `value` | `String?` | Current value (for controls) |
| `identifier` | `String?` | Identifier |
| `frameX/Y/Width/Height` | `Double` | Screen coordinates |
| `actions` | `[String]` | Available actions (activate, increment, decrement, custom) |

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
open ButtonHeist.xcworkspace
```

### Building for Device (Command Line)

```bash
# Build with signing
xcodebuild -workspace ButtonHeist.xcworkspace \
  -scheme AccessibilityTestApp \
  -destination 'platform=iOS,name=Your Device' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build

# Install
xcrun devicectl device install app \
  --device "Your Device" \
  ~/Library/Developer/Xcode/DerivedData/ButtonHeist-*/Build/Products/Debug-iphoneos/AccessibilityTestApp.app
```

### Project Structure

```
buttonheist/
├── ButtonHeist/
│   └── Sources/
│       ├── TheGoods/              # Shared types (Messages.swift)
│       ├── InsideMan/             # iOS server
│       │   ├── InsideMan.swift            # Main server singleton
│       │   ├── SimpleSocketServer.swift   # BSD socket TCP server
│       │   ├── SafeCracker.swift           # Multi-touch gesture simulation
│       │   ├── SyntheticTouchFactory.swift    # UITouch creation via private APIs
│       │   ├── SyntheticEventFactory.swift    # UIEvent manipulation
│       │   ├── IOHIDEventBuilder.swift        # Low-level HID event creation
│       │   └── TapVisualizerView.swift        # Visual tap feedback overlay
│       ├── InsideManLoader/       # ObjC auto-start (+load)
│       ├── Wheelman/                 # Cross-platform networking
│       │   ├── DiscoveredDevice.swift       # Device model
│       │   ├── DeviceDiscovery.swift        # Bonjour browsing
│       │   ├── DeviceConnection.swift       # BSD socket connection
│       │   └── SimpleSocketServer.swift     # TCP server
│       └── ButtonHeist/              # macOS client framework
│           ├── HeistClient.swift            # Main client (ObservableObject)
│           └── Exports.swift                # Re-exports TheGoods + Wheelman
├── Stakeout/
│   └── Sources/                   # macOS GUI app
│       ├── Views/                 # SwiftUI views
│       └── Design/                # Design tokens (colors, typography)
├── ButtonHeistMCP/
│   ├── Package.swift              # Swift 6.0 package (depends on ButtonHeist + MCP SDK)
│   └── Sources/
│       └── main.swift             # MCP server with 13 tools for AI agent automation
├── ButtonHeistCLI/
│   └── Sources/                   # CLI tool
│       ├── main.swift             # Entry point with watch/action/touch/screenshot commands
│       ├── CLIRunner.swift        # Watch mode implementation
│       ├── ActionCommand.swift    # Action command
│       ├── TouchCommand.swift     # Touch gesture commands (7 subcommands)
│       └── ScreenshotCommand.swift    # Screenshot command
├── TestApp/
│   ├── Sources/                   # SwiftUI test app ("A11y SwiftUI")
│   │   ├── RootView.swift             # Navigation menu
│   │   ├── ContentView.swift          # UI showcase
│   │   └── TouchCanvasView.swift      # Multi-touch drawing canvas
│   └── UIKitSources/              # UIKit test app ("A11y UIKit")
├── AccessibilitySnapshot/         # Git submodule (hierarchy parsing)
├── scripts/
│   ├── usb-connect.sh             # USB connection helper
│   └── buttonheist_usb.py         # Python USB module
├── docs/
│   ├── ARCHITECTURE.md            # System design
│   ├── WIRE-PROTOCOL.md           # Protocol specification
│   ├── API.md                     # API reference
│   └── USB_DEVICE_CONNECTIVITY.md # USB guide
├── Project.swift                  # Tuist configuration
└── Workspace.swift
```

## Wire Protocol

Communication uses newline-delimited JSON over TCP (protocol version 2.0):

**Client → Server:**
- `requestSnapshot` - Request current hierarchy
- `subscribe` / `unsubscribe` - Automatic update subscription
- `activate` - Activate element (VoiceOver double-tap)
- `increment` / `decrement` - Adjust adjustable elements
- `performCustomAction` - Invoke named custom action
- `touchTap` - Tap at coordinates or element
- `touchLongPress` - Long press with configurable duration
- `touchSwipe` - Swipe by direction or coordinates
- `touchDrag` - Drag between two points
- `touchPinch` - Pinch/zoom gesture
- `touchRotate` - Rotation gesture
- `touchTwoFingerTap` - Two-finger tap
- `requestScreenshot` - Request PNG screenshot
- `ping` - Keepalive

**Server → Client:**
- `info` - Server info on connection
- `hierarchy` - UI element snapshot (flat list + optional tree)
- `actionResult` - Result of action with method used
- `screenshot` - Base64-encoded PNG with dimensions
- `error` - Error description
- `pong` - Ping response

**Port:** 1455 (configurable via Info.plist)
**Bonjour service:** `_buttonheist._tcp`

## Troubleshooting

### Device not appearing (WiFi)

1. Ensure both devices are on the same network
2. Check that InsideMan framework is linked
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

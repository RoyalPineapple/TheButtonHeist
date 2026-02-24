# ButtonHeist

**Let AI agents drive iOS apps**

ButtonHeist gives AI agents (and humans) full control over iOS apps. Embed InsideMan in your app, then connect with the MCP server to let Claude inspect UI, tap buttons, swipe, type, and navigate — all programmatically over a persistent connection.

## Features

- **MCP server** - Model Context Protocol server lets AI agents like Claude drive any iOS app
- **Real-time inspection** - See UI elements update as your app's UI changes
- **Remote actions** - Tap elements and trigger actions programmatically
- **Touch gestures** - Full gesture simulation: tap, long press, swipe, drag, pinch, rotate, two-finger tap, draw path, draw bezier
- **Multi-touch** - Simultaneous multi-finger gesture injection via IOKit HID events
- **USB connectivity** - Connect to devices over USB when WiFi is unavailable
- **Auto-start** - InsideMan starts automatically when your app launches
- **Multi-device** - Run many instances on many simulators with stable identifiers for each
- **Device targeting** - Match devices by name, short ID, simulator UDID, or vendor identifier
- **Fixed port** - Predictable port (1455) for reliable scripted connections
- **Token auth** - Token-based authentication with auto-generated or configured secrets
- **Multiple interfaces** - MCP server, CLI, Python, or custom tools

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
│  │ buttonheist-mcp  │  ← Thin proxy, exposes single `run` tool      │
│  │  (MCP server)    │                                               │
│  └────────┬─────────┘                                               │
│           │ spawns subprocess                                        │
│  ┌────────┴─────────────────┐  ┌──────────────────┐               │
│  │  buttonheist session     │  │  Python/Scripts  │               │
│  │  (persistent CLI session)│  │                  │               │
│  └────────┬─────────────────┘  └────────┬─────────┘               │
│           │                             │                           │
│           └─────────────────────────────┘                           │
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
│                        │   (framework)   │    Port 1455 + Bonjour  │
│                        └────────┬────────┘                         │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │  Your iOS App   │                         │
│                        └─────────────────┘                         │
│                           iOS Device                                │
└─────────────────────────────────────────────────────────────────────┘
```

**End-to-end data flow:**
```
AI Agent → MCP (stdio) → buttonheist-mcp → spawns → buttonheist session → HeistClient → Network → InsideMan
```

## Modules

| Module | Platform | Description |
|--------|----------|-------------|
| **TheGoods** | iOS + macOS | Shared types, messages, and constants |
| **InsideMan** | iOS | Server that exposes UI element interface over TCP, with synthetic touch injection |
| **Wheelman** | iOS + macOS | Cross-platform networking (TCP server/client, Bonjour discovery) |
| **ButtonHeist** | macOS | Client framework with HeistClient class; re-exports TheGoods + Wheelman |
| **ButtonHeistMCP** | macOS | MCP server — lets AI agents drive iOS apps via Model Context Protocol |
| **buttonheist** | macOS | CLI tool with list, watch, action, touch, screenshot, and session commands |

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

ButtonHeist's MCP server gives AI agents like Claude **eyes and hands** for your iOS app. The agent can see the screen, read the UI hierarchy, and perform any gesture — tap, swipe, draw, type — all through native tool calls.

**Build the MCP server:**

```bash
cd ButtonHeistMCP
swift build -c release
```

**Add `.mcp.json` to your project root:**

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

**Targeting a specific device** (when running multiple simulators):

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "DEADBEEF-1234-5678-9ABC-DEF012345678"]
    }
  }
}
```

You can also target by `BUTTONHEIST_DEVICE` environment variable, device name, app name, or short ID prefix.

That's it. When an MCP-compatible AI agent (Claude Code, Claude Desktop, or any MCP client) opens a session in your project directory, it reads `.mcp.json` and spawns the `buttonheist-mcp` process. The server spawns a `buttonheist session` subprocess that discovers your iOS app via Bonjour and exposes a single `run` tool through which all commands are dispatched.

**How it works end-to-end:**

```
1. AI agent starts a session in your project directory
2. MCP client reads .mcp.json, spawns buttonheist-mcp
3. buttonheist-mcp spawns a `buttonheist session` subprocess that discovers your iOS app via Bonjour
4. The subprocess maintains a persistent TCP connection — stays open for the entire session
5. Agent sees a single `run` tool — commands are passed as parameters (e.g. command: "get_screen")
6. Agent calls run() with the desired command — no shell commands, no scripts, no manual wiring
```

The agent can now look at your app and interact with it naturally:

```
Agent: "Let me see what's on screen"
→ calls run(command: "get_screen") → sees your app's UI as an image
→ calls run(command: "get_interface") → reads the accessibility hierarchy as structured data

Agent: "I'll tap the login button"
→ calls run(command: "tap", identifier: "loginButton")
→ gets success/failure result

Agent: "Let me draw a signature"
→ calls run(command: "draw_bezier", startX: 100, startY: 400, segments: [...])
→ smooth curve traced on screen
```

Because the connection is persistent (no per-call Bonjour discovery or TCP handshake), tool calls complete in milliseconds. An agent can chain dozens of interactions — navigate through screens, fill forms, verify visual state — without delay.

**Available tool:**

The MCP server exposes a single `run` tool. Pass the desired command name and any parameters:

```json
{"command": "tap", "identifier": "loginButton"}
{"command": "get_screen"}
{"command": "swipe", "identifier": "scrollView", "direction": "up"}
```

**Available commands:**

| Command | Description |
|---------|-------------|
| `get_interface` | Read the full UI element hierarchy |
| `get_screen` | Capture a PNG screen capture |
| `tap` | Tap an element or coordinate |
| `long_press` | Long press with configurable duration |
| `swipe` | Swipe by direction or between coordinates |
| `drag` | Drag between two points |
| `pinch` | Pinch/zoom gesture |
| `rotate` | Two-finger rotation |
| `two_finger_tap` | Simultaneous two-finger tap |
| `draw_path` | Draw along a path of waypoints |
| `draw_bezier` | Draw along cubic bezier curves |
| `activate` | Accessibility activate (VoiceOver double-tap) |
| `increment` / `decrement` | Adjust sliders, steppers, pickers |
| `perform_custom_action` | Invoke named custom accessibility actions |
| `type_text` | Type text into the focused element |
| `edit_action` | Edit text in an element |
| `dismiss_keyboard` | Dismiss the on-screen keyboard |
| `wait_for_idle` | Wait until the UI settles |
| `list_devices` | List all discovered iOS devices with identifiers |
| `status` | Show connection status |
| `help` | List available commands |

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

## CLI Usage

The CLI has seven subcommands: `list`, `watch` (default), `action`, `touch`, `type`, `screenshot`, and `session`. All subcommands that connect to a device support `--device <filter>` for targeting.

All subcommands that connect to a device accept `--device <filter>` to target a specific instance by name, short ID prefix, simulator UDID, or vendor identifier.

### list

```
USAGE: buttonheist list [--timeout <timeout>] [--format <format>]

OPTIONS:
  -t, --timeout <timeout> Discovery timeout in seconds (default: 3)
  -f, --format <format>   Output format: human, json (default: human)
```

Lists all discovered devices with their app name, device name, short ID, and device identifiers (simulator UDID or vendor identifier).

### watch (default)

```
USAGE: buttonheist watch [--format <format>] [--once] [--quiet] [--timeout <timeout>] [--verbose] [--device <filter>]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit (default: watch mode)
  -q, --quiet             Suppress status messages (only output data)
  -t, --timeout <timeout> Timeout in seconds waiting for device (default: 0)
  -v, --verbose           Show verbose output
  --device <filter>       Target device by name, ID prefix, simulator UDID, or vendor ID
```

### action

```
USAGE: buttonheist action [--identifier <id>] [--index <n>] [--type <type>] [--custom-action <name>] [--x <x>] [--y <y>] [--timeout <t>] [--quiet] [--device <filter>]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Traversal index
  --type <type>           Action: activate, increment, decrement, tap, custom (default: activate)
  --custom-action <name>  Custom action name (when type is 'custom')
  --x <x>, --y <y>       Tap coordinates (when type is 'tap')
  -t, --timeout <t>       Timeout in seconds (default: 10)
  --device <filter>       Target device by name, ID prefix, simulator UDID, or vendor ID
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
  two-finger-tap          Two-finger tap at a point or element
  draw-path               Draw along a path of points
  draw-bezier             Draw along cubic bezier curves
```

All touch subcommands accept `--identifier`, `--index`, or coordinate options to specify the target, and `--device` to target a specific device.

### screenshot

```
USAGE: buttonheist screenshot [--output <path>] [--timeout <t>] [--quiet] [--device <filter>]

OPTIONS:
  -o, --output <path>     Output file path (default: stdout as raw PNG)
  -t, --timeout <t>       Timeout in seconds (default: 10)
  --device <filter>       Target device by name, ID prefix, simulator UDID, or vendor ID
```

**Examples:**

```bash
# List all discovered devices
buttonheist list
buttonheist list --format json

# Interactive watch mode - see live updates
buttonheist

# Target a specific device by short ID, UDID, or name
buttonheist --device a1b2 watch --once
buttonheist --device DEADBEEF-1234 watch --once

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
buttonheist touch draw-path --points "100,400 200,300 300,400" --duration 1.0
buttonheist touch draw-bezier --bezier-file curve.json --velocity 300
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

### HeistElement

Each element in the hierarchy contains:

| Property | Type | Description |
|----------|------|-------------|
| `order` | `Int` | Element reading order (0-based) |
| `description` | `String` | VoiceOver description |
| `label` | `String?` | Label |
| `value` | `String?` | Current value (for controls) |
| `identifier` | `String?` | Identifier |
| `hint` | `String?` | Accessibility hint |
| `traits` | `[String]` | Trait names (e.g., `["button"]`, `["adjustable"]`) |
| `frameX/Y/Width/Height` | `Double` | Screen coordinates in points |
| `activationPointX/Y` | `Double` | Where VoiceOver would tap |
| `respondsToUserInteraction` | `Bool` | Whether the element is interactive |
| `customContent` | `[{label, value, isImportant}]?` | Custom accessibility content |
| `actions` | `[String]` | Available actions (`"activate"`, `"increment"`, `"decrement"`, or custom action names) |

## Development Setup

### Prerequisites

- Xcode 15+
- iOS 17+ / macOS 14+

### Building

```bash
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
│       │   ├── SafeCracker.swift           # Multi-touch gesture simulation
│       │   ├── SyntheticTouchFactory.swift    # UITouch creation via private APIs
│       │   ├── SyntheticEventFactory.swift    # UIEvent manipulation
│       │   ├── IOHIDEventBuilder.swift        # Low-level HID event creation
│       │   └── TapVisualizerView.swift        # Visual tap feedback overlay
│       ├── InsideManLoader/       # ObjC auto-start (+load)
│       ├── Wheelman/                 # Cross-platform networking
│       │   ├── DiscoveredDevice.swift       # Device model
│       │   ├── DeviceDiscovery.swift        # Bonjour browsing
│       │   ├── DeviceConnection.swift       # TCP client connection
│       │   └── SimpleSocketServer.swift     # TCP server (Network framework)
│       └── ButtonHeist/              # macOS client framework
│           ├── HeistClient.swift            # Main client (ObservableObject)
│           └── Exports.swift                # Re-exports TheGoods + Wheelman
├── ButtonHeistMCP/
│   ├── Package.swift              # Swift 6.0 package (depends on MCP SDK)
│   └── Sources/
│       └── main.swift             # MCP server — thin proxy to CLI session
├── ButtonHeistCLI/
│   └── Sources/                   # CLI tool
│       ├── main.swift             # Entry point with list/watch/action/touch/screenshot/session commands
│       ├── CLIRunner.swift        # Watch mode implementation
│       ├── ListCommand.swift      # Device listing command
│       ├── DeviceConnector.swift  # Shared discover→filter→connect helper
│       ├── ActionCommand.swift    # Action command
│       ├── TouchCommand.swift     # Touch gesture commands (9 subcommands)
│       ├── ScreenshotCommand.swift    # Screenshot command
│       └── SessionCommand.swift       # Persistent interactive session command
├── TestApp/
│   ├── Sources/                   # SwiftUI test app ("A11y SwiftUI")
│   │   ├── RootView.swift             # Navigation menu and main view
│   │   ├── ControlsDemoView.swift     # UI controls showcase
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
└── ButtonHeist.xcworkspace
```

## Wire Protocol

Communication uses newline-delimited JSON over TCP (protocol version 3.0):

**Client → Server:**
- `authenticate` - Token authentication (must be first message)
- `requestInterface` - Request current hierarchy
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
- `touchDrawPath` - Draw along a path of waypoints
- `touchDrawBezier` - Draw along bezier curves (sampled server-side)
- `typeText` - Type text via keyboard injection
- `editAction` - Perform edit action (copy, paste, cut, select, selectAll)
- `resignFirstResponder` - Dismiss keyboard
- `waitForIdle` - Wait for animations to settle
- `requestScreen` - Request PNG screenshot
- `ping` - Keepalive

**Server → Client:**
- `authRequired` - Server requires authentication
- `authFailed` - Authentication failed
- `info` - Server info after successful auth
- `interface` - UI element interface (flat list + optional tree)
- `actionResult` - Result of action with method, optional delta, and animation state
- `screen` - Base64-encoded PNG with dimensions
- `error` - Error description
- `pong` - Ping response

**Port:** 1455 (configurable via Info.plist)
**Bonjour service:** `_buttonheist._tcp`
**Service name format:** `{AppName}#{instanceId}`
**TXT record keys:** `simudid` (simulator UDID), `tokenhash` (auth token hash), `instanceid` (instance identifier)

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

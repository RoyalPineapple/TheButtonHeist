# ButtonHeist

**Let AI agents drive iOS apps.**

ButtonHeist gives AI agents (and humans) full control over iOS apps. Embed InsideMan in your app, then connect with the MCP server to let Claude inspect UI, tap buttons, swipe, type, and navigate — all programmatically over a persistent connection.

## Features

- **MCP server** — AI agents like Claude drive any iOS app through native tool calls
- **Full gesture simulation** — Tap, long press, swipe, drag, pinch, rotate, two-finger tap, draw path, draw bezier
- **Multi-touch** — Simultaneous multi-finger gesture injection via IOKit HID events
- **Real-time inspection** — See UI elements and screenshots update as the app changes
- **Text input** — Type text, delete characters, read back values — via UIKeyboardImpl injection
- **Token auth** — Token-based authentication with auto-generated or configured secrets, plus on-device Allow/Deny approval for new connections
- **Auto-start** — InsideMan starts automatically when your app launches (ObjC `+load`, DEBUG only)
- **Multi-device** — Run many instances on many simulators with stable identifiers
- **USB auto-discovery** — USB devices discovered automatically alongside WiFi via Bonjour
- **Multiple interfaces** — MCP server, CLI, or build your own

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
│  ┌────────┴─────────────────┐                                       │
│  │  buttonheist session     │                                       │
│  │  (persistent CLI session)│                                       │
│  └────────┬─────────────────┘                                       │
│           │                                                          │
│  ┌────────┴────────┐                                                │
│  │   ButtonHeist   │  ← Bonjour + USB auto-discovery                │
│  │  (HeistClient)  │                                                │
│  └────────┬────────┘                                                │
└───────────┼──────────────────────────────────────────────────────────┘
            │ Local Network / USB (IPv6)
┌───────────┼──────────────────────────────────────────────────────────┐
│  ┌────────┴────────┐                                                │
│  │    InsideMan    │  ← Auto-starts on load                         │
│  │   (framework)   │    Port 1455 + Bonjour                         │
│  └────────┬────────┘                                                │
│           │                                                          │
│  ┌────────┴────────┐                                                │
│  │  Your iOS App   │                                                │
│  └─────────────────┘                                                │
│                           iOS Device                                 │
└──────────────────────────────────────────────────────────────────────┘
```

**End-to-end:**
```
AI Agent → MCP (stdio) → buttonheist-mcp → buttonheist session → HeistClient → TCP → InsideMan
```

## Modules

| Module | Platform | Description | Details |
|--------|----------|-------------|---------|
| **TheGoods** | iOS + macOS | Shared types, messages, and constants | [ButtonHeist/](ButtonHeist/) |
| **InsideMan** | iOS | Server + synthetic touch injection, embedded in your app | [ButtonHeist/](ButtonHeist/) |
| **Wheelman** | iOS + macOS | TCP server/client, Bonjour discovery | [ButtonHeist/](ButtonHeist/) |
| **ButtonHeist** | macOS | Client framework (HeistClient); re-exports TheGoods + Wheelman | [ButtonHeist/](ButtonHeist/) |
| **ButtonHeistMCP** | macOS | MCP server — AI agents drive iOS apps via Model Context Protocol | [ButtonHeistMCP/](ButtonHeistMCP/) |
| **buttonheist** | macOS | CLI tool: list, watch, action, touch, type, screenshot, session | [ButtonHeistCLI/](ButtonHeistCLI/) |

## Quick Start

### 1. Add InsideMan to Your iOS App

Import InsideMan. It auto-starts via ObjC `+load` — no code changes needed beyond the import.

```swift
import SwiftUI
import InsideMan

@main
struct MyApp: App {
    // InsideMan auto-starts on framework load

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Add the required Info.plist entries:

```xml
<!-- Fixed port for InsideMan -->
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

Build the MCP server and drop a `.mcp.json` in your project root:

```bash
cd ButtonHeistMCP && swift build -c release
```

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

That's it. When Claude (or any MCP client) opens a session in your project, it spawns the server, discovers your iOS app via Bonjour, and the agent can interact naturally:

```
Agent: "Let me see what's on screen"
→ calls run(command: "get_screen") → sees the app as an image
→ calls run(command: "get_interface") → reads the UI hierarchy as structured data

Agent: "I'll tap the login button"
→ calls run(command: "tap", identifier: "loginButton")
→ gets success/failure result with what changed in the UI

Agent: "Let me type an email address"
→ calls run(command: "type_text", text: "user@example.com", identifier: "emailField")
→ gets the field's current value back
```

Tool calls complete in milliseconds — the connection is persistent, no per-call discovery or handshake.

For device targeting, command reference, and internals: **[ButtonHeistMCP/](ButtonHeistMCP/)**

### 3. Connect with the CLI

```bash
buttonheist list                                    # Discover devices
buttonheist --once                                  # Single hierarchy snapshot
buttonheist action --identifier loginButton         # Activate a button
buttonheist touch tap --x 100 --y 200               # Tap coordinates
buttonheist touch swipe --identifier list --direction up  # Swipe a list
buttonheist type --text "Hello" --identifier nameField    # Type text
buttonheist screenshot --output screen.png          # Capture screenshot
```

Full CLI reference with all 7 subcommands and 9 touch gestures: **[ButtonHeistCLI/](ButtonHeistCLI/)**

### 4. Connect over USB

USB devices are discovered automatically alongside WiFi. Both appear in `buttonheist list`:

```bash
buttonheist list
# [0] a1b2c3d4  AccessibilityTestApp  (WiFi)
# [1] usb-iPhone  iPhone (USB)
```

See [docs/USB_DEVICE_CONNECTIVITY.md](docs/USB_DEVICE_CONNECTIVITY.md) for details.

## Development

### Prerequisites

- Xcode 15+
- iOS 17+ / macOS 14+

### Building

```bash
open ButtonHeist.xcworkspace
```

### Project Structure

```
ButtonHeist/
├── ButtonHeist/Sources/          # Core frameworks (TheGoods, InsideMan, Wheelman, ButtonHeist)
├── ButtonHeistMCP/               # MCP server (Swift Package)
├── ButtonHeistCLI/               # CLI tool (Swift Package)
├── TestApp/                      # SwiftUI + UIKit test applications
├── AccessibilitySnapshot/        # Git submodule (hierarchy parsing)
├── docs/                         # Architecture, API, protocol, USB docs
└── ai-fuzzer/                    # Autonomous AI app fuzzing framework
```

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

- Ensure the app has visible UI on screen
- The root view must be accessible to UIAccessibility

## Documentation

**Frameworks and tools:**
- [ButtonHeist Frameworks](ButtonHeist/) — Core modules: TheGoods, InsideMan, Wheelman, client
- [MCP Server](ButtonHeistMCP/) — AI agent integration via Model Context Protocol
- [CLI Reference](ButtonHeistCLI/) — Full command-line documentation
- [Test Apps](TestApp/) — Sample iOS applications for testing

**Technical docs:**
- [Architecture](docs/ARCHITECTURE.md) — System design and data flow diagrams
- [API Reference](docs/API.md) — Complete API for all modules
- [Wire Protocol](docs/WIRE-PROTOCOL.md) — Protocol v3.1 specification
- [USB Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) — CoreDevice tunnel deep dive

**Project:**
- [AI Fuzzer](ai-fuzzer/) — Autonomous iOS app testing framework
- [Contributing](CONTRIBUTING.md) — Development setup and guidelines
- [Changelog](CHANGELOG.md) — Version history

## License

MIT

## Acknowledgments

Built on [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) for parsing UIKit accessibility hierarchies.

<img width="1536" height="1024" alt="ChatGPT Image Mar 3, 2026, 01_47_05 PM" src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

# Interface out. Agents in. Clean escape.

Button Heist gives AI agents full programmatic control of iOS apps — 2-3x fewer turns than any other MCP server for iOS. Embed one framework, connect over MCP or CLI, and the agent drives any screen: tap, swipe, type, scroll, inspect, record.

The efficiency comes from five capabilities that build on each other. Each one is useful alone. Together, they compound.

## Why It's Fast

### 1. The agent knows what everything is

Button Heist runs **inside your app**. It reads live `UIAccessibility` objects directly — labels, traits, activation points, custom actions, custom content, `respondsToUserInteraction`. The agent gets a complete, typed picture of every control on screen.

External tools read accessibility data through XPC or WebDriverAgent, which serializes it across process boundaries. Activation points, custom content, custom rotors, and available actions get dropped in translation. The agent gets a lossy summary and has to guess what it's missing.

When the agent knows a control is a stepper, it calls `increment`. When it knows a row has a "Delete" custom action, it calls `perform_custom_action("Delete")`. When it knows a button's activation point is offset from center, it taps in the right place. No guessing, no retries.

### 2. Every action tells the agent what changed

After every command, Button Heist returns an **interface delta** — elements added, removed, or changed — not just "ok." The agent knows immediately whether tapping "Login" dismissed the login screen or showed a validation error, without re-reading the full tree.

External tools return nothing after an action. The agent has to screenshot, re-fetch the tree, diff it mentally, and decide what happened. That's an extra round trip per action — and for an LLM, an extra reasoning step.

### 3. The agent knows when the UI is ready

`wait_for_idle` watches `CALayer` animations and reports when the screen has settled. `wait_for` watches for a specific element to appear or disappear. No fixed sleeps, no screenshot polling.

External tools can't see animation state — it doesn't cross the process boundary. Agents using them either sleep for a fixed duration (too long or too short) or screenshot in a loop until things look stable (expensive and unreliable).

### 4. Multiple actions in one call

`run_batch` sends an ordered sequence of commands in a single MCP round trip. Type an email, type a password, tap submit — one call, three actions, three deltas back.

This only works because of (2) and (3): each step in the batch gets its own delta, and the framework waits for idle between steps automatically. External tools can't batch because each action depends on re-reading the screen to plan the next one.

### 5. The agent declares what should happen

Each action or batch step can carry an `expect` — `"screen_changed"`, `"elements_changed"`, or a specific element update. The framework checks the delta against the expectation and reports whether it was met. If a batch step's expectation fails, the batch stops with diagnostics.

The agent doesn't verify outcomes by re-inspecting — the tool does it inline. This is the final multiplier: the agent can fire-and-forget a confident sequence instead of interleaving actions with verification reads.

### How they compound

An agent using Button Heist to add a todo item:

```
→ run_batch(steps: [
    {command: "type_text", identifier: "titleField", text: "Buy milk"},
    {command: "activate", identifier: "addButton", expect: "elements_changed"}
  ])
← 2 steps completed, expectation met, delta shows new row added
```

Two actions, one round trip, verified outcome. **One agent turn.**

The same task with an external tool:

```
→ get_accessibility_tree          (find the field)
← tree
→ tap(x: 187, y: 340)            (tap the field)
← ok
→ type("Buy milk")
← ok
→ get_accessibility_tree          (find the button)
← tree
→ tap(x: 305, y: 340)            (tap Add)
← ok
→ get_accessibility_tree          (verify it worked)
← tree
```

Seven calls, three tree fetches, no outcome verification. **Seven agent turns** — and the agent still has to reason about whether the tree changed correctly.

### Benchmarks

Thirteen tasks, three MCP servers, same model (Claude Sonnet 4.6), same app. All achieve high accuracy — the difference is how many turns it takes:

| | Turns | Wall time | Cost |
|---|-------|-----------|------|
| mobile-mcp | 61 | 308s | $0.99 |
| ios-simulator-mcp | 49 | 188s | $0.84 |
| **Button Heist** | **25** | **103s** | **$0.43** |

Numbers for the 11-step full-workflow task. BH shows 2-3x fewer turns across the full suite, with the gap widening on gesture-heavy tasks (swipe actions: 7 turns vs 34 vs 80). Full data in [docs/the-argument.md](docs/the-argument.md).

## What It Can Do

**Interact** — `activate` calls `accessibilityActivate()` first, falls back to synthetic tap. Full gesture suite: long press, swipe, drag, pinch, rotate, two-finger tap, bezier paths. Text input with edit actions (copy, paste, cut, select). Scroll by direction, scroll to edge, scroll until an element is visible. Increment/decrement on adjustable elements. Named custom actions.

**Inspect** — Full accessibility tree with 18 named traits (including private `backButton`), frames, activation points, custom content, available actions. `heistId` stable identifiers derived from trait + label (`button_login`, `header_settings`). Interface deltas after every action. Screenshots.

**Record** — H.264/MP4 screen recording with configurable FPS, resolution, touch overlay, and interaction logs. Auto-stops on inactivity or max duration.

**Connect** — WiFi via Bonjour, USB via CoreDevice tunnels. TLS 1.2+ with SHA-256 fingerprint pinning. Token auth with on-device Allow/Deny. Session locking (one driver at a time). Multi-device with per-instance isolation.

## Architecture

```mermaid
%% If you can read this, the diagram isn't rendering. Try github.com in a browser.
graph TD
    AI["AI Agent<br/>(Claude, or any MCP client)"]
    HUMAN["A Human<br/>(You even)"]
    MCP["buttonheist-mcp<br/>18 tools"]
    CLI["buttonheist CLI<br/>15 subcommands"]
    Client["TheFence / TheHandoff<br/>(ButtonHeist framework)"]
    IJ["TheInsideJob<br/>(embedded in your app)"]
    App["Your iOS App"]

    AI -->|"MCP (JSON-RPC over stdio)"| MCP
    MCP --> Client
    HUMAN -->|"A Terminal"| CLI
    CLI --> Client
    Client -->|"TLS over WiFi / USB"| IJ
    IJ --> App

    subgraph Intelligence["Intelligence"]
        HUMAN
        AI
    end

    subgraph Mac["Your Mac"]
        MCP
        CLI
        Client
    end

    subgraph Device["iOS Device or Simulator"]
        IJ
        App
    end
```

### Modules

| Module | Platform | What it does |
|--------|----------|-------------|
| **TheScore** | iOS + macOS | Wire protocol: 33 client messages, 18 server messages, `HeistElement`, `InterfaceDelta`, `ElementMatcher`, protocol v6.3 |
| **TheInsideJob** | iOS | In-app server: TCP + Bonjour, accessibility capture, touch injection, recording, auth. Auto-starts via ObjC `+load` (DEBUG only) |
| **ButtonHeist** | macOS | Client framework: TheFence (35-command dispatch + request correlation), TheHandoff (discovery + connection + state) |
| **ButtonHeistMCP** | macOS | MCP server: 18 tools dispatching through TheFence, including `run_batch` and `get_session_state` |
| **buttonheist** | macOS | CLI: 15 subcommands + interactive session REPL with auto-reconnect and three output formats (human/json/compact) |

### Meet the Crew

Every heist needs a team.

#### The Score

| Name | Role |
|------|------|
| **TheScore** | The shared playbook. Wire protocol types, messages, and constants used by both sides of the connection |

#### The Inside Team (iOS)

| Name | Role |
|------|------|
| **TheInsideJob** | The whole operation. TCP server, Bonjour, accessibility hierarchy, command dispatch to the crew |
| **TheSafecracker** | Cracks the UI. Taps, swipes, drags, pinch, rotate, text entry, edit actions — all via IOHIDEvent |
| **TheBagman** | Handles the goods. Accessibility hierarchy capture, heistId assignment, delta computation |
| **TheMuscle** | Keeps the door. Token validation, Allow/Deny UI, session lock, connection scoping |
| **TheStakeout** | The lookout. H.264 screen recording, frame timing, inactivity detection |
| **TheFingerprints** | Evidence. Touch indicators rendered on-device and baked into recordings |
| **TheTripwire** | Timing coordinator. Gates all "is the UI ready?" decisions — animation detection, presentation layer fingerprinting, settle waits |
| **ThePlant** | The advance. ObjC `+load` hook boots TheInsideJob before any Swift runs — link the framework, no app code |

#### The Outside Team (macOS)

| Name | Role |
|------|------|
| **TheFence** | Runs the show. 35 commands dispatched from CLI and MCP, request-response correlation, async waits |
| **TheHandoff** | Gets everyone in position. Bonjour + USB discovery, TLS connection, session state, injectable closures for testing |

#### The Legitimate Front

| Name | Role |
|------|------|
| **ButtonHeistCLI** | Your orders. `list`, `session`, `activate`, `touch`, `type`, `screenshot`, `record`, and more |
| **ButtonHeistMCP** | Agent interface. 18 tools that call through TheFence so AI agents can run the job natively |

## Quick Start

### 1. Embed TheInsideJob in Your iOS App

Link the framework in your iOS target and import it. ObjC `+load` handles the rest — no setup code.

```swift
import SwiftUI
import TheInsideJob

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Add the required Info.plist entries:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the element inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### 2. Connect with an AI Agent (MCP)

Build the MCP server and add it to your project's `.mcp.json`:

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

The agent discovers your app via Bonjour and can interact immediately:

```
Agent: "Let me see what's on screen"
→ get_screen → screenshot as inline image
→ get_interface → structured hierarchy with heistIds

Agent: "Tap the login button"
→ activate(heistId: "button_login")
→ result includes interface delta showing what changed

Agent: "Type credentials and submit"
→ run_batch(steps: [
    {command: "type_text", identifier: "emailField", text: "user@example.com"},
    {command: "type_text", identifier: "passwordField", text: "hunter2"},
    {command: "activate", identifier: "submitButton", expect: "screen_changed"}
  ])
→ 3 steps in one round trip, per-step results, short-circuits on failure
```

### Pair with XcodeBuildMCP for Full Agent Workflows

For the best agent experience, run Button Heist alongside [**XcodeBuildMCP**](https://github.com/getsentry/XcodeBuildMCP) — it handles build, install, launch, terminate, and simulator lifecycle. Together they cover the full loop: XcodeBuildMCP builds and deploys, Button Heist drives the UI.

```json
{
  "mcpServers": {
    "xcodebuild": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    },
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

### 3. Connect with the CLI

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
BH=./ButtonHeistCLI/.build/release/buttonheist

$BH list                                                  # Discover devices (WiFi + USB)
$BH session                                               # Interactive REPL
$BH activate --identifier loginButton                     # Activate an element
$BH touch one_finger_tap --x 100 --y 200                 # Coordinate tap
$BH type --text "Hello" --identifier nameField            # Type into a field
$BH scroll --direction down --identifier scrollView       # Scroll one page
$BH scroll_to_visible --identifier targetElement          # Scroll until visible
$BH screenshot --output screen.png                        # Capture screenshot
$BH record --output demo.mp4 --fps 8 --scale 0.5         # Record with touch overlay
```

The session REPL accepts both JSON and shorthand: `tap loginButton`, `type "hello"`, `scroll down list`, `screen`.

### 4. USB Devices

USB devices appear alongside WiFi in `buttonheist list` — no extra configuration. Button Heist discovers them via CoreDevice IPv6 tunnels.

```bash
$BH list
# [0] a1b2c3d4  BH Demo  (WiFi)
# [1] usb-iPhone  iPhone (USB)
```

See [USB Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) for the deep dive.

## The Trade-Off

Button Heist runs inside your app. You link a framework into the debug build — the same pattern as [Reveal](https://revealapp.com) or [FLEX](https://github.com/FLEXTool/FLEX). This is the trade-off: it doesn't work with apps you can't modify.

For apps you don't control, [mobile-mcp](https://github.com/mobile-next/mobile-mcp) or [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp) work without integration. For apps you're building — where you can embed the framework and where 2-3x efficiency, batching, expectations, and real device support matter — Button Heist is the tool.

The embedding requirement is also why everything above works. Live object access, real touch injection, animation detection, interface deltas, and direct accessibility actions are only possible from inside the app process. No external tool can replicate them.

## Development

### Prerequisites

- Xcode with Swift 6 package support
- iOS 17+ / macOS 14+
- `git submodule update --init --recursive`
- [Tuist](https://tuist.io)

### Building

```bash
git submodule update --init --recursive
tuist generate
open ButtonHeist.xcworkspace
```

### Project Structure

```
ButtonHeist/
├── ButtonHeist/Sources/          # Core frameworks (TheScore, TheInsideJob, ButtonHeist)
├── ButtonHeistMCP/               # MCP server (Swift Package)
├── ButtonHeistCLI/               # CLI tool (Swift Package)
├── TestApp/                      # SwiftUI + UIKit test applications
├── AccessibilitySnapshot/        # Git submodule (hierarchy parsing)
├── docs/                         # Architecture, API, protocol, auth, USB docs
│   └── dossiers/                 # Per-module technical documentation
└── ai-fuzzer/                    # Git submodule: autonomous AI app fuzzer
```

### ai-fuzzer

An autonomous iOS app fuzzer built entirely with prompt engineering on top of Button Heist — 6,000+ lines of markdown, zero traditional code. Included as a Git submodule.

```bash
git submodule update --init --recursive   # Initialize
git submodule update --remote ai-fuzzer   # Update later
```

## Troubleshooting

### Device not appearing (WiFi)

1. Both devices on the same network
2. TheInsideJob framework linked to your target
3. Info.plist has the `_buttonheist._tcp` Bonjour service entry
4. iOS local network permission accepted

### USB connection refused

1. Device connected: `xcrun devicectl list devices`
2. App running on device
3. IPv6 tunnel visible: `lsof -i -P -n | grep CoreDev`

### Empty hierarchy

- App has visible UI on screen
- Root view is accessible to UIAccessibility

## Documentation

**Frameworks and tools:**
- [ButtonHeist Frameworks](ButtonHeist/) — TheScore, TheInsideJob, ButtonHeist client
- [MCP Server](ButtonHeistMCP/) — 18-tool AI agent integration
- [CLI Reference](ButtonHeistCLI/) — Full command-line documentation
- [Test Apps](TestApp/) — Sample iOS applications

**Technical docs:**
- [Architecture](docs/ARCHITECTURE.md) — System design and data flow
- [API Reference](docs/API.md) — Complete API for all modules
- [Wire Protocol](docs/WIRE-PROTOCOL.md) — Protocol v6.3 specification
- [Authentication](docs/AUTH.md) — Token auth, session locking, UI approval
- [USB Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) — CoreDevice tunnel deep dive
- [Versioning](docs/VERSIONING.md) — SemVer strategy and release workflow
- [Bonjour Troubleshooting](docs/BONJOUR_TROUBLESHOOTING.md) — MDM stealth mode workarounds
- [Reviewer's Guide](docs/REVIEWERS-GUIDE.md) — Quick orientation for new reviewers
- [Competitive Landscape](docs/competitive-landscape.md) — How Button Heist compares
- [Differentiators](docs/DIFFERENTIATORS.md) — 20 optimizations ranked by measured impact
- [The Argument](docs/the-argument.md) — Why this approach, why now
- Benchmark Data — Raw results in `benchmarks/results/`
- [Crew Dossiers](docs/dossiers/) — Per-crew-member technical deep dives

**Project:**
- [AI Fuzzer](ai-fuzzer/) — Autonomous iOS app fuzzer built on Button Heist

## License

Apache License 2.0 — see `LICENSE`.

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF) — TheSafecracker's touch synthesis is built on KIF's pioneering work in programmatic iOS UI interaction.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) — Used for parsing UIKit accessibility hierarchies.

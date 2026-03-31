<img width="1536" height="1024" alt="ChatGPT Image Mar 3, 2026, 01_47_05 PM" src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

# Interface out. Agents in. Clean escape.

There's a second interface running underneath every iOS app. The accessibility layer — built for VoiceOver and the millions of blind and low-vision people who depend on it — quietly describes every control, every action, every state. A complete semantic map of the app, maintained by the developer, ignored by almost everyone else.

Button Heist slips AI agents through that door. Link one framework into your debug build, and the agent works the interface from the inside: `activate(heistId: "button_login")` instead of `tap(x: 187, y: 340)`. It calls `increment` on a stepper, triggers a "Delete" custom action by name, knows a button's activation point is offset from center — because the accessibility layer already says so.

When the agent understands the interface it's working with, everything else follows — better results, more reliably, faster.

<!-- TODO: terminal GIF showing run_batch with delta response -->

## Features

### Interaction

- **Accessibility-first activation** — `activate` calls `accessibilityActivate()` first, falls back to synthetic tap. Works on custom controls that swallow raw touch events
- **Full gesture suite** — tap, long press, swipe, drag, pinch, rotate, two-finger tap, draw arbitrary paths and bezier curves
- **Text input** — type characters, delete, clear fields, read back values — works with software and hardware keyboard modes. Edit actions: copy, paste, cut, select, selectAll. Pasteboard read/write without triggering the iOS "Allow Paste" dialog
- **Scroll semantics** — `scroll` (one page by direction), `scroll_to_visible` (bidirectional search for element matching label/identifier/value/traits predicate), `scroll_to_edge` (jump to top/bottom/left/right). All action commands accept flat matcher fields (`label`, `value`, `traits`, `excludeTraits`) alongside `heistId` for unified targeting
- **Accessibility actions** — increment/decrement on adjustable elements, trigger named custom actions, dismiss keyboard

### Inspection

- **Structured UI hierarchy** — full accessibility tree with labels, values, traits (18 named mappings including private `backButton`), frames, activation points, custom content, and available actions
- **heistId stable identifiers** — developer `accessibilityIdentifier` takes priority; otherwise synthesized from trait + label (e.g., `button_login`, `header_settings`). Disambiguated with `_1`, `_2` suffixes when duplicated
- **Interface deltas** — four delta kinds: `screenChanged` (new view controller), `elementsChanged` (added/removed), `valuesChanged` (text updates), `noChange`. Returned after every action
- **Screenshots** — PNG capture, inline base64 or saved to file
- **Animation idle detection** — blocks until CALayer animations settle, no guessing

### Recording

- **H.264/MP4 screen recording** — configurable FPS (1–15), resolution scale (0.25–1.0)
- **Auto-stop** — on inactivity timeout (default 5s) or max duration (default 60s)
- **Touch overlay** — finger position indicators baked into the video via TheFingerprints
- **Interaction log** — timestamped JSON of all actions during a recording session

### Agent Integration

- **18 MCP tools** — purpose-built for AI agents. Video data stripped from context window (metadata only unless output path given)
- **Batch execution** — `run_batch` sends ordered steps in one call. Per-step expectations, `stop_on_error` or `continue_on_error` policy, aggregated timing
- **Session state** — `get_session_state` returns connection status, device identity, recording state, last-action summary
- **Outcome expectations** — `expect` on any action: `"screen_changed"`, `"elements_changed"`, or `{"elementUpdated": {…}}`. Framework reports; caller decides

### Security

- **TLS 1.2+** — self-signed ECDSA certificates generated at runtime, verified via SHA-256 fingerprint pinning through Bonjour TXT records
- **Token auth** — auto-generated or configured secrets. On-device Allow/Deny approval UI for new connections
- **Session locking** — one driver at a time. Additional connections get `sessionLocked` with context

### Connectivity

- **WiFi** — Bonjour auto-discovery on `_buttonheist._tcp`
- **USB** — CoreDevice IPv6 tunnel discovery via `xcrun devicectl` + `lsof`. Same API as WiFi
- **Multi-device** — run many instances on many simulators. `buttonheist list` verifies each candidate with a status probe before reporting
- **Auto-reconnect** — session mode reconnects automatically on connection drop

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

### 1. Get the crew inside

Link TheInsideJob to your debug target. It auto-starts via ObjC `+load` — no setup code, no initialization call.

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

Same embed pattern as [Reveal](https://revealapp.com) or [FLEX](https://github.com/FLEXTool/FLEX). Add the Info.plist entries so Bonjour can advertise:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the element inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### 2. Give the agent eyes and hands

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

The agent discovers your app via Bonjour. From here, every interaction returns what changed — not just "ok":

```
→ activate(heistId: "button_login")
← delta: login screen dismissed, dashboard appeared — 3 new elements
  {"kind": "elementsChanged", "removed": ["button_login", ...], "added": [...]}

→ run_batch(steps: [type email, type password, tap submit])
← 3 steps, 3 deltas, 1 round trip. Stopped early? Here's which step failed and why.
```

No screenshots to parse. No coordinates to compute. The agent reads the interface, not the pixels.

### 3. Or drive it yourself

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
BH=./ButtonHeistCLI/.build/release/buttonheist

$BH list                                                  # Discover devices (WiFi + USB)
$BH session                                               # Interactive REPL
$BH activate --identifier loginButton                     # Activate an element
$BH action --name "Delete" --identifier cell_row_3        # Named custom action
$BH type --text "Hello" --identifier nameField            # Type into a field
$BH scroll --direction down --identifier scrollView       # Scroll one page
$BH scroll_to_visible --identifier targetElement          # Scroll until visible
$BH screenshot --output screen.png                        # Capture screenshot
$BH record --output demo.mp4 --fps 8 --scale 0.5         # Record with touch overlay
```

The session REPL accepts both JSON and shorthand: `tap loginButton`, `type "hello"`, `scroll down list`, `screen`.

### 4. USB devices

USB devices appear alongside WiFi in `buttonheist list` — no extra configuration. Zero-config CoreDevice tunnel discovery.

```bash
$BH list
# [0] a1b2c3d4  BH Demo  (WiFi)
# [1] usb-iPhone  iPhone (USB)
```

See [USB Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) for the deep dive.

## What It Can Do

### Interact

- **Accessibility-first activation** — `activate` calls `accessibilityActivate()` first, falls back to synthetic tap. Works on custom controls that swallow raw touch events
- **Full gesture suite** — long press, swipe, drag, pinch, rotate, two-finger tap, bezier paths via IOHIDEvent
- **Text input** — type, delete, clear, read back values. Edit actions: copy, paste, cut, select, selectAll. Pasteboard read/write without triggering the system paste dialog
- **Scroll semantics** — `scroll` (one page), `scroll_to_visible` (find element), `scroll_to_edge` (jump to boundary)
- **Accessibility actions** — increment/decrement, named custom actions, dismiss keyboard

### Inspect

- **Full accessibility tree** — labels, values, 18 named traits, frames, activation points, custom content, available actions
- **Stable identifiers** — `heistId` derived from trait + label (`button_login`, `header_settings`), developer identifier takes priority
- **Interface deltas** — three kinds: `screenChanged`, `elementsChanged`, `noChange`. Returned after every action
- **Screenshots** — PNG capture, inline base64 or saved to file
- **Animation idle detection** — blocks until `CALayer` animations settle

### Record

- **H.264/MP4 screen recording** — configurable FPS (1-15), resolution scale (0.25-1.0)
- **Touch overlay** — finger position indicators baked into the video
- **Auto-stop** — on inactivity timeout or max duration
- **Interaction log** — timestamped JSON of all actions during the session

### Connect

- **WiFi** — Bonjour auto-discovery on `_buttonheist._tcp`
- **USB** — CoreDevice IPv6 tunnel discovery. Same API as WiFi
- **Security** — TLS 1.2+ with SHA-256 fingerprint pinning. Token auth with on-device Allow/Deny
- **Multi-device** — many instances, many simulators. Session locking (one driver at a time)

## How It Works

Button Heist runs **inside your app**, not across a process boundary. The agent gets the real accessibility interface — the same one VoiceOver uses — instead of a lossy translation through XPC.

This means three things that compound:

### 1. Every action tells the agent what changed

After every command, Button Heist returns an **interface delta** — a structured diff of what happened. Tap "Login" and the response carries exactly which elements disappeared and which appeared:

```json
{
  "success": true,
  "method": "activate",
  "interfaceDelta": {
    "kind": "elementsChanged",
    "elementCount": 14,
    "removed": ["button_login", "textfield_password", "textfield_email"],
    "added": [
      {"heistId": "header_dashboard", "label": "Dashboard", "traits": ["header"]},
      {"heistId": "button_settings", "label": "Settings", "traits": ["button"]}
    ]
  }
}
```

Login screen gone, dashboard appeared, new elements ready to target. No screenshot, no re-fetch, no guessing.

When the change is a value update — typing into a field, toggling a switch — the delta carries the property change:

```json
"updated": [{"heistId": "switch_darkmode", "changes": [{"property": "value", "old": "0", "new": "1"}]}]
```

When a new view controller appears, the delta includes the complete new interface. When nothing changes, it says `"noChange"` — the agent knows immediately and can try something else.

### 2. Every action can verify itself

Each command can carry an `expect` — a declaration of what *should* happen. The framework checks the delta against the expectation and reports pass/fail:

```json
{
  "command": "activate",
  "target": {"heistId": "button_login"},
  "expect": "screen_changed"
}
```

```json
{
  "expectation": {"met": true, "expectation": "screenChanged"}
}
```

Three tiers: `screen_changed` (new view controller), `elements_changed` (anything in the hierarchy shifted), or `element_updated` with specific property checks. When an expectation fails, the response says what *actually* happened — so the agent can reason about the mismatch without re-reading anything.

This is what makes everything else possible. Without inline verification, the agent has to stop after every action, re-read the screen, and decide if it worked. That's exactly what external tools do — and it's where half the turns go.

### 3. Expectations unlock batching

Because every step verifies itself, `run_batch` can send an ordered sequence in a single round trip. Each step gets its own delta and expectation check. If a step fails, the batch stops — the agent never pushes forward with bad state:

```json
{
  "command": "run_batch",
  "steps": [
    {"command": "type_text", "target": {"heistId": "textfield_email"}, "text": "user@example.com",
     "expect": {"element_updated": {"heistId": "textfield_email", "property": "value", "newValue": "user@example.com"}}},
    {"command": "type_text", "target": {"heistId": "textfield_password"}, "text": "hunter2",
     "expect": {"element_updated": {"heistId": "textfield_password", "property": "value"}}},
    {"command": "activate", "target": {"heistId": "button_submit"}, "expect": "screen_changed"}
  ]
}
```

Three actions. Three assertions. One round trip. If the password field doesn't update, the batch stops at step 2 — it never taps submit with bad state.

Every interaction is also an implicit accessibility audit. If the agent can't find a control, neither can VoiceOver. The same investment that makes your app agent-ready makes it accessible — and vice versa.

For the full breakdown — benchmarks, per-task comparisons, and the compounding math — see [The Argument](docs/the-argument.md).

## Meet the Crew

Every heist needs a team.

### The Score

| Name | Role |
|------|------|
| **TheScore** | The shared playbook. Wire protocol types, messages, and constants — the contract both sides speak |

### The Inside Team (iOS)

| Name | Role |
|------|------|
| **TheInsideJob** | The whole operation. Runs in your app: TCP server, Bonjour, accessibility hierarchy, command dispatch to the crew |
| **TheSafecracker** | Cracks the UI. Taps, swipes, drags, pinch, rotate, text entry, edit actions — gets past any control via IOHIDEvent |
| **TheBagman** | Handles the goods. Element cache, hierarchy capture, heistId assignment, delta computation. Live view pointers never leave TheBagman |
| **TheMuscle** | Keeps the door. Token validation, Allow/Deny UI, session lock — only one driver at a time |
| **TheStakeout** | The lookout. H.264 screen recording with frame timing and inactivity detection |
| **TheFingerprints** | Evidence. Touch indicators on screen during gestures — visible live and baked into TheStakeout's recordings |
| **TheTripwire** | Timing coordinator. Gates all "is the UI ready?" decisions — animation detection, presentation layer fingerprinting, settle waits |
| **ThePlant** | Runs the advance. ObjC `+load` hook boots TheInsideJob before any Swift runs — link the framework, no app code |

### The Outside Team (macOS)

| Name | Role |
|------|------|
| **TheFence** | Runs the show. 35 commands dispatched from CLI and MCP, request-response correlation, async waits |
| **TheHandoff** | Gets everyone in position. Bonjour + USB discovery, TLS connection, session state, injectable closures for testing |

### The Legitimate Front

| Name | Role |
|------|------|
| **ButtonHeistCLI** | Your orders. `list`, `session`, `activate`, `touch`, `type`, `screenshot`, `record`, and more |
| **ButtonHeistMCP** | Agent interface. 22 tools that call through TheFence so AI agents can run the job natively |

## Architecture

```mermaid
%% If you can read this, the diagram isn't rendering. Try github.com in a browser.
graph TD
    AI["AI Agent<br/>(Claude, or any MCP client)"]
    HUMAN["A Human<br/>(You even)"]
    MCP["buttonheist-mcp<br/>22 tools"]
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
| **ButtonHeistMCP** | macOS | MCP server: 22 tools dispatching through TheFence, including `run_batch` and `get_session_state` |
| **buttonheist** | macOS | CLI: 15 subcommands + interactive session REPL with auto-reconnect and three output formats (human/json/compact) |

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
- Run `buttonheist get_interface` and check the element count

## Documentation

**Integrating into your app?** Start with the [API Reference](docs/API.md) and [Quick Start above](#quick-start).

**Connecting an agent?** See the [Wire Protocol](docs/WIRE-PROTOCOL.md) and [MCP Server](ButtonHeistMCP/).

**Understanding the architecture?** Read [Architecture](docs/ARCHITECTURE.md) and [Crew Dossiers](docs/dossiers/).

All docs:
- [ButtonHeist Frameworks](ButtonHeist/) — TheScore, TheInsideJob, ButtonHeist client
- [MCP Server](ButtonHeistMCP/) — 22-tool AI agent integration
- [CLI Reference](ButtonHeistCLI/) — Full command-line documentation
- [Test Apps](TestApp/) — Sample iOS applications
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
- [Crew Dossiers](docs/dossiers/) — Per-crew-member technical deep dives

## License

Apache License 2.0 — see `LICENSE`.

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF) — TheSafecracker's touch synthesis is built on KIF's pioneering work in programmatic iOS UI interaction.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) — Used for parsing UIKit accessibility hierarchies.

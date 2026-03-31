<img width="1536" height="1024" alt="ChatGPT Image Mar 3, 2026, 01_47_05 PM" src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

# Interface out. Agents in. Clean escape.

There's a second interface running underneath every iOS app. The accessibility layer — built for VoiceOver and the millions of blind and low-vision people who depend on it — quietly describes every control, every action, every state. A complete semantic map of the app, maintained by the developer, ignored by almost everyone else.

Button Heist slips AI agents through that door. Link one framework into your debug build, and the agent works the interface from the inside: `activate(heistId: "button_login")` instead of `tap(x: 187, y: 340)`. It calls `increment` on a stepper, triggers a "Delete" custom action by name, knows a button's activation point is offset from center — because the accessibility layer already says so.

Once the agent can read the room, everything else follows — better results, more reliably, faster.

<!-- TODO: terminal GIF showing run_batch with delta response -->

## Quick Start

### 1. Get the crew inside

Link TheInsideJob in your iOS target and import it. ThePlant's ObjC `+load` hook handles the rest — no setup code.

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

### 2. Connect an AI agent (MCP)

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

### 3. Connect with the CLI

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

USB devices appear alongside WiFi in `buttonheist list` — no extra configuration.

```bash
$BH list
# [0] a1b2c3d4  BH Demo  (WiFi)
# [1] usb-iPhone  iPhone (USB)
```

See [USB Connectivity](docs/USB_DEVICE_CONNECTIVITY.md) for the deep dive.

## How It Works

Button Heist runs **inside your app**, not across a process boundary. This means four things:

- **Full fidelity** — the agent reads live `UIAccessibility` objects directly. Activation points, custom content, custom rotors, available actions — nothing lost in serialization. When a control is a stepper, the agent calls `increment`. When a row has a "Delete" custom action, the agent calls it by name.
- **Deltas after every action** — tap a button, get back exactly what changed. No re-fetching the full tree.
- **Animation-aware idle** — `wait_for_idle` watches `CALayer` animations. `wait_for` watches for a specific element. No fixed sleeps.
- **Inline expectations** — every action can carry an `expect` declaring what should happen. The framework checks the delta and reports pass/fail with diagnostics. This is what makes batching possible — because every step verifies itself, the agent can fire a sequence without stopping to look after each one.
- **Batch execution** — `run_batch` sends multiple commands in one round trip. Each step gets its own delta and expectation check. Stops on first failure so the agent never pushes forward with bad state.

### Interface deltas

Every action returns an `interfaceDelta` — a structured diff of what changed in the hierarchy. Three kinds:

**`elementsChanged`** — elements were added, removed, or updated. The delta carries exactly which ones:

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
      {"heistId": "button_settings", "label": "Settings", "traits": ["button"]},
      {"heistId": "text_welcome", "label": "Welcome back", "traits": ["staticText"]}
    ]
  },
  "screenName": "Dashboard"
}
```

The agent reads this and knows: login screen dismissed, dashboard appeared, three new elements to work with. No screenshot, no re-fetch.

**`valuesChanged`** — something updated in place. Typing into a field:

```json
{
  "success": true,
  "method": "typeText",
  "interfaceDelta": {
    "kind": "elementsChanged",
    "elementCount": 14,
    "updated": [
      {
        "heistId": "textfield_email",
        "changes": [
          {"property": "value", "old": "", "new": "user@example.com"}
        ]
      }
    ]
  },
  "value": "user@example.com"
}
```

The agent sees the value change confirmed in the delta *and* in the `value` field. No need to read it back.

**`screenChanged`** — a new view controller appeared. The delta includes the full new interface:

```json
{
  "success": true,
  "method": "activate",
  "interfaceDelta": {
    "kind": "screenChanged",
    "elementCount": 8,
    "newInterface": {
      "elements": [
        {"heistId": "header_settings", "label": "Settings", "traits": ["header"]},
        {"heistId": "switch_darkmode", "label": "Dark Mode", "value": "0", "traits": ["button"]},
        {"heistId": "button_back", "label": "Back", "traits": ["button", "backButton"]}
      ]
    }
  },
  "screenName": "Settings"
}
```

Complete new screen in the same response as the action. Zero additional calls.

**`noChange`** — nothing moved. The agent knows immediately and can try something else.

### Expectations

Expectations are what make everything else work. Without them, the agent has to stop after every action, re-read the screen, and decide if it worked — which is exactly what external tools do. With them, each action verifies itself. The agent declares what *should* happen, the framework checks the delta, and the result comes back pass/fail with diagnostics. This is what unlocks batching: because every step carries its own assertion, the agent can send a whole sequence without stopping to look.

Three tiers, from broad to precise:

**`screen_changed`** — assert that a new view controller appeared:

```json
{
  "command": "activate",
  "target": {"heistId": "button_login"},
  "expect": "screen_changed"
}
```

```json
{
  "success": true,
  "interfaceDelta": {"kind": "screenChanged", "elementCount": 12, "newInterface": {"elements": ["..."]}},
  "expectation": {"met": true, "expectation": "screenChanged"}
}
```

The agent asked "should this navigate?" and the framework answered yes, with the new screen already in hand.

**`elements_changed`** — assert that *something* in the hierarchy changed (met by either `elementsChanged` or `screenChanged`):

```json
{
  "command": "activate",
  "target": {"heistId": "button_add_row"},
  "expect": "elements_changed"
}
```

```json
{
  "success": true,
  "interfaceDelta": {
    "kind": "elementsChanged",
    "elementCount": 15,
    "added": [{"heistId": "cell_row_3", "label": "New Item", "traits": ["staticText"]}]
  },
  "expectation": {"met": true, "expectation": "elementsChanged"}
}
```

**`element_updated`** — assert a specific property change on a specific element. Say what you know, omit what you don't:

```json
{
  "command": "activate",
  "target": {"heistId": "switch_darkmode"},
  "expect": {"element_updated": {"heistId": "switch_darkmode", "property": "value", "newValue": "1"}}
}
```

```json
{
  "success": true,
  "interfaceDelta": {
    "kind": "elementsChanged",
    "elementCount": 14,
    "updated": [
      {"heistId": "switch_darkmode", "changes": [{"property": "value", "old": "0", "new": "1"}]}
    ]
  },
  "expectation": {"met": true, "expectation": {"element_updated": {"heistId": "switch_darkmode", "property": "value", "newValue": "1"}}}
}
```

Toggle dark mode, assert the value flipped to "1". The framework scans `updated` for a match — if the heistId, property, and value all line up, it's met.

When an expectation fails, the framework reports what it actually observed:

```json
{
  "expectation": {
    "met": false,
    "expectation": "screenChanged",
    "actual": "elementsChanged"
  }
}
```

The agent asked for a screen change but only got element updates — maybe a validation error appeared instead of navigating. The agent has the delta, the failed expectation, and the actual outcome. It can reason about what went wrong without re-fetching anything.

### Batching: what expectations unlock

Because every step verifies itself, the agent doesn't need to stop and look between actions. `run_batch` sends an ordered sequence in a single round trip — each step gets its own delta, its own expectation check, and the batch stops on the first failure (`stop_on_error` policy). The agent never pushes forward with bad state:

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

Three actions. Three assertions. One round trip. If typing into the password field doesn't update the value, the batch stops at step 2 — it never taps submit with bad state.

This is why external tools can't batch. Without inline verification, each action is fire-and-forget: do something, screenshot, stare at pixels, decide if it worked, then plan the next step. Batching requires knowing each step succeeded *before the response comes back to the agent*. Expectations make that possible — every action is an assertion, and the test suite is woven into the interaction itself.

And because agents operate through the accessibility interface, every interaction is an implicit accessibility audit. If the agent can't find a control, neither can VoiceOver. The same investment that makes your app agent-ready makes it accessible — and vice versa.

For the full breakdown — benchmarks, per-task comparisons, and the compounding math — see [The Argument](docs/the-argument.md).

## What It Can Do

### Interact

- **Accessibility-first activation** — `activate` calls `accessibilityActivate()` first, falls back to synthetic tap
- **Full gesture suite** — long press, swipe, drag, pinch, rotate, two-finger tap, bezier paths via IOHIDEvent
- **Text input** — type, delete, clear, read back values. Edit actions: copy, paste, cut, select, selectAll. Pasteboard read/write without triggering the system paste dialog
- **Scroll semantics** — `scroll` (one page), `scroll_to_visible` (find element), `scroll_to_edge` (jump to boundary)
- **Accessibility actions** — increment/decrement, named custom actions, dismiss keyboard

### Inspect

- **Full accessibility tree** — labels, values, 18 named traits, frames, activation points, custom content, available actions
- **Stable identifiers** — `heistId` derived from trait + label (`button_login`, `header_settings`), developer identifier takes priority
- **Interface deltas** — four kinds: `screenChanged`, `elementsChanged`, `valuesChanged`, `noChange`
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

## Documentation

**Frameworks and tools:**
- [ButtonHeist Frameworks](ButtonHeist/) — TheScore, TheInsideJob, ButtonHeist client
- [MCP Server](ButtonHeistMCP/) — 22-tool AI agent integration
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
- [Crew Dossiers](docs/dossiers/) — Per-crew-member technical deep dives

## License

Apache License 2.0 — see `LICENSE`.

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF) — TheSafecracker's touch synthesis is built on KIF's pioneering work in programmatic iOS UI interaction.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot) — Used for parsing UIKit accessibility hierarchies.

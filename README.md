<img width="1536" height="1024" alt="Noir-style heist planning board with an iPhone at center labeled The Vault, connected by red string to crew member dossiers: The Inside Job, The Safecracker, The Mastermind, The Fence, and The Bagman. A whiskey glass and desk lamp sit in the foreground." src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

[![CI](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RoyalPineapple/TheButtonHeist?label=release)](https://github.com/RoyalPineapple/TheButtonHeist/releases/latest)
[![License](https://img.shields.io/github/license/RoyalPineapple/TheButtonHeist)](LICENSE)

# Interface out. Agents in. Clean escape.

Every iOS app has a second interface.

Not the one you see. The one VoiceOver uses.

It describes the app in the language users depend on: labels, roles, values, states, actions. That interface is a contract: if users can do something visually, the app should expose it semantically.

Button Heist turns that contract into an inside route for agents: a control surface built from meaning, not pixels.

Link one framework into a debug build, connect over MCP or CLI, and the agent operates the app by meaning. No coordinate math. No screenshot parsing loops. No blind taps.

Every job leaves evidence: deltas, expectations, recordings, and a replayable test trail.

## The difference

A coordinate-based tool can tell the agent that a tap landed:

```
→ tap(x: 201, y: 456)
← "Tapped successfully"
```

Button Heist tells the agent what the tap did:

```
→ activate(label: "Login", traits: ["button"])
← screen changed
  - textfield_email
  - textfield_password
  - button_login
  + header_dashboard "Dashboard" header
  + button_settings "Settings" button
```

The first tool says the tap landed.

Button Heist brings back evidence. The agent starts the next step from the new state, not from another full-screen read.

## Quick Start

### 1. Add TheInsideJob

Link `TheInsideJob` to your debug target. It starts a local TCP server via ObjC `+load`; no app setup code is required. Release builds leave the server behind.

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

By default the server accepts simulator loopback and USB-scoped connections, but
does not publish Bonjour on the LAN. If you opt into network scope with
`INSIDEJOB_SCOPE=simulator,usb,network` or `InsideJobScope`, add the
Info.plist entries that allow Bonjour advertisement:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app uses local network to communicate with the element inspector.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

### 2. Install the agent tools

Install the CLI and MCP server:

```bash
brew install RoyalPineapple/tap/buttonheist
```

Add the MCP server to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "buttonheist-mcp",
      "args": []
    }
  }
}
```

The MCP adapter projects its tools from the Fence command contract; the
generated [MCP Tool Reference](docs/reference/mcp-tools.md) is the current tool
surface. Agents typically start with `get_interface`, then act with semantic
commands such as `activate`, `type_text`, and `run_batch`. Default connections
use loopback, USB, named targets, or direct `host:port` targets; Bonjour
discovery is available only when the app opts into network scope:

```
Agent: "I need to log the user in"

→ get_interface
  textfield_email, textfield_password, button_login (12 elements)

→ run_batch([type_text into textfield_email, activate button_login])
  step 1: value → "user@example.com" ✓
  step 2: screen changed: login gone, dashboard appeared ✓
```

The agent can work in terms of UI intent instead of coordinates.

### 3. Use the CLI directly

```bash
cd ButtonHeistCLI && swift build -c release && cd ..
BH=./ButtonHeistCLI/.build/release/buttonheist

$BH list_devices
$BH get_interface
$BH activate --identifier loginButton
$BH type_text "Hello" --identifier nameField
$BH get_screen --output screen.png
```

The session REPL accepts canonical command names with `key=value` arguments or canonical machine JSON.

For the complete generated CLI command surface, see the
[Command Reference](docs/reference/commands.md). For workflow context, see the
[CLI README](ButtonHeistCLI/README.md).

## How the Job Runs

Coordinate-based tools turn intent into geometry: read the tree, extract frames, tap a point, read again.

Button Heist keeps the live accessibility hierarchy in reach. It resolves semantic targets, performs actions, and returns the UI change that followed.

That changes the loop. Every action goes through the contract. Every result comes back as evidence.

### 1. Results: trace-backed evidence after every action

After every command, Button Heist returns one typed result payload. Accessibility
traces are the source receipt; deltas are compact projections used for
expectations and formatting. Tap "Login" and the response carries the capture
chain plus derived screen context, not a second stored delta truth.

The agent does not need to re-read the screen to understand the result. Value updates include the element, property, old value, and new value. When nothing changes, the delta projection says `"noChange"`.

When the screen changes while the agent is thinking, the next response uses the same capture/delta contract to report that background change before any stale action runs.

### 2. Expectations: assertions on the contract

Commands whose Fence contract includes `expect` can declare what should happen.
Button Heist checks the delta projection against that expectation and reports
pass/fail inline:

```json
{
  "command": "activate",
  "target": {"heistId": "button_login"},
  "expect": {"type": "screen_changed"}
}
```

Response: `{"expectation": {"met": true, "expectation": "screenChanged"}}`.

Expectations can check for `screen_changed`, `elements_changed`, or a specific `element_updated` result. When an expectation fails, the response still includes what actually happened.

The agent says what it expects. Button Heist says whether it happened.

### 3. Batching: fewer round trips

`run_batch` sends ordered steps in one round trip. Each step gets its own delta and expectation check. If a step fails, the batch stops at that point:

```json
{
  "command": "run_batch",
  "steps": [
    {
      "command": "type_text",
      "target": {"heistId": "textfield_email"},
      "text": "user@example.com",
      "expect": {
        "type": "element_updated",
        "heistId": "textfield_email",
        "property": "value",
        "newValue": "user@example.com"
      }
    },
    {"command": "activate", "target": {"heistId": "button_submit"}, "expect": {"type": "screen_changed"}}
  ]
}
```

Two actions, two assertions, one round trip. If the email field does not update, the submit step never runs.

### 4. Replay: the contract in CI

Button Heist can record an agent session as a replayable `.heist` file. Each step is stored as a semantic matcher: label, traits, and stable identifiers. `heistId` is a current-capture handle and recording clue, not durable replay identity.

Replay uses the same action path as live automation. If a label changes, a trait disappears, or a custom action is removed, the replay fails and surfaces the broken contract. JUnit XML output (`--junit`) puts those failures into CI.

Because recordings are semantic, the same flow can run across device sizes and orientations. Coordinate recordings break when layout moves. Semantic recordings fail when the app's accessible interface changes, which is exactly the contract agents and VoiceOver users depend on.

The job does not disappear into tool-call history. It comes back as a replayable test.

## The Accessibility Contract

Button Heist does not treat accessibility as metadata to scrape and discard. It makes the Accessibility Contract the control surface.

That matters. A coordinate tool can tap a button with no label and report success. Button Heist cannot pretend the app is accessible when the semantic interface is missing or wrong. If an agent cannot find the control by label, trait, value, or action, that is signal.

One contract. Three payoffs: agents move faster, tests get stronger, VoiceOver users get the interface they were promised.

## Benchmarks

That contract shows up in the numbers. Button Heist was tested against a coordinate-based MCP server using the same model, app, tasks, and hardware. The suite covers 96 trials across 16 UI automation tasks: forms, navigation, lists, settings, custom actions, and long workflows.

Agents spend less time casing the screen, less time doing geometry, and more time acting through the contract.

|  | Button Heist | Coordinate-based |
|---|---|---|
| **Avg wall time** | 134s | 235s |
| **Avg turns** | 14 | 43 |
| **Avg cost** | $0.46 | $1.42 |
| **Tasks completed** | 16/16 | 16/16 |

Average result: **2.4x faster, 3.1x fewer turns, 3.1x lower cost.** The gap grows as workflows get longer:

| Task type | Advantage | Why |
|---|---|---|
| Scroll + select | **4–6x** | Semantic find vs read-tree-compute-tap loops |
| Custom actions (order, complete, delete) | **3–5x** | Direct invocation vs visual menu navigation |
| Multi-screen workflows | **2–3x** | Deltas eliminate redundant tree reads |
| Scale (50+ actions) | **2.6x** | Per-action overhead compounds with task length |
| Simple taps | ~1x | Both approaches handle simple buttons well |

The gap comes from the loop shape. Every action without a delta often means another full tree read. Over a 50-action workflow, that becomes 50 extra round trips and a lot of context spent on observation instead of progress. In the longest benchmark, Button Heist finished in under 8 minutes; the coordinate-based tool needed 20.

Full methodology and per-task data: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Meet the Crew

Button Heist is a distributed system: an iOS framework inside the app, a macOS client outside it, and CLI/MCP fronts for humans and agents.

### The Inside Team (iOS)

| Name | Role |
|------|------|
| **TheInsideJob** | iOS framework embedded in the app. Hosts the TLS TCP server, optional Bonjour advertisement, accessibility hierarchy, and command dispatch |
| **TheSafecracker** | Touch, gesture, text-entry, and edit-action execution through synthetic events |
| **TheStash** | Current element state, target resolution, `heistId` assignment, and wire conversion. Live view pointers stay inside |
| **TheBurglar** | Accessibility hierarchy parsing, topology detection, and scroll-container discovery |
| **TheBrains** | Action execution, scroll orchestration, delta generation, waits, and exploration |
| **TheGetaway** | Message dispatch, encoding/decoding, transport wiring, response state, and interaction recording |
| **TheMuscle** | Token validation, approval UI, and session locking |
| **TheStakeout** | H.264 screen recording with frame timing and inactivity detection |
| **TheFingerprints** | Touch indicators for live interaction and recorded output |
| **TheTripwire** | UI readiness checks: animation detection, presentation-layer fingerprints, and settle waits |
| **ThePlant** | ObjC `+load` hook that starts TheInsideJob when the framework loads |

### The Outside Team (macOS)

| Name | Role |
|------|------|
| **TheFence** | Command dispatch for CLI and MCP, request-response correlation, and async waits |
| **TheHandoff** | Scoped discovery, named/direct targets, TLS connection handling, session state, and testable connection hooks |
| **TheBookKeeper** | Session logs, artifact storage, heist recording, and replay |

### Interfaces

| Name | Role |
|------|------|
| **ButtonHeistCLI** | Command-line adapter over TheFence; generated command surface lives in [Command Reference](docs/reference/commands.md) |
| **ButtonHeistMCP** | MCP adapter over TheFence; generated tool surface lives in [MCP Tool Reference](docs/reference/mcp-tools.md) |

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
├── AccessibilitySnapshotBH/      # Git submodule (hierarchy parsing)
├── docs/                         # Architecture, API, protocol, auth, connectivity docs
```

## Troubleshooting

### Device not appearing

1. TheInsideJob framework linked to your target
2. App running in the foreground
3. For Bonjour/LAN discovery only: Info.plist has the `_buttonheist._tcp` service entry
4. Scope allows the connection path. Defaults are simulator and USB; LAN exposure requires explicit network scope.

### USB connection refused

1. Device connected: `xcrun devicectl list devices`
2. App running on device
3. IPv6 tunnel visible: `lsof -i -P -n | grep CoreDev`

### Empty hierarchy

- App has visible UI on screen
- Root view is accessible to UIAccessibility
- Run `buttonheist get_interface` and check the element count

## Documentation

| Path | Start here |
|---|---|
| **iOS engineer** (instrument app + run locally) | [Quick Start](#quick-start) + [API](docs/API.md) |
| **QA / automation engineer** (record + replay in CI) | [Benchmarks](docs/BENCHMARKS.md) + [Heist Format](docs/HEIST-FORMAT.md) |
| **Agent builder** (MCP tools for Codex/Claude/Cursor) | [ButtonHeistMCP](ButtonHeistMCP/) + [MCP Tool Reference](docs/reference/mcp-tools.md) |

**Integrating into an app?** Start with the [Quick Start](#quick-start) and [API Reference](docs/API.md).

**Connecting an agent?** See [ButtonHeistMCP](ButtonHeistMCP/) and the [MCP Tool Reference](docs/reference/mcp-tools.md).

**Understanding the internals?** Read [Architecture](docs/ARCHITECTURE.md).

All docs: [API](docs/API.md) ・ [Command Reference](docs/reference/commands.md) ・ [MCP Tool Reference](docs/reference/mcp-tools.md) ・ [Architecture](docs/ARCHITECTURE.md) ・ [Wire Protocol](docs/WIRE-PROTOCOL.md) ・ [Auth](docs/AUTH.md) ・ [USB](docs/USB_DEVICE_CONNECTIVITY.md) ・ [Bonjour Troubleshooting](docs/BONJOUR_TROUBLESHOOTING.md) ・ [Reviewer's Guide](docs/REVIEWERS-GUIDE.md)

## License

Apache License 2.0. See `LICENSE`.

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF). TheSafecracker's touch synthesis is built on KIF's pioneering work in programmatic iOS UI interaction.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot). Used for parsing UIKit accessibility hierarchies (via our fork [AccessibilitySnapshotBH](https://github.com/RoyalPineapple/AccessibilitySnapshotBH)).

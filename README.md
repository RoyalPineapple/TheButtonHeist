<img width="1536" height="1024" alt="Noir-style heist planning board with an iPhone at center labeled The Vault, connected by red string to crew member dossiers: The Inside Job, The Safecracker, The Mastermind, The Fence, and The Bagman. A whiskey glass and desk lamp sit in the foreground." src="https://github.com/user-attachments/assets/ab62f18f-a3bd-480e-906d-3167b90c1d77" />

[![CI](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/RoyalPineapple/TheButtonHeist/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RoyalPineapple/TheButtonHeist?label=release)](https://github.com/RoyalPineapple/TheButtonHeist/releases/latest)
[![License](https://img.shields.io/github/license/RoyalPineapple/TheButtonHeist)](LICENSE)

# Interface out. Agents in. Clean escape.

There's a second interface running underneath every iOS app. Built for VoiceOver and the millions who depend on it, the accessibility layer is the plumbing beneath the UI. Every control, every action, every state, described in a semantic map we keep up to date under the pixel polish.

In practice, coverage varies. VoiceOver users notice the gaps.

Button Heist lets AI agents in through those pipes, and gives them full control. Link one framework into your debug build and the agent works the interface from the inside. No coordinate math, no screenshot parsing. The exact same APIs VoiceOver uses. It activates a login button by name, calls `increment` on a stepper, triggers a "Delete" custom action directly.

Every interaction doubles as an accessibility audit: if the agent can't find a control, neither can VoiceOver.

The heist works because the infrastructure was already in place. A language interface built for people to navigate apps by meaning. Turns out agents thrive there too.

## Quick Start

### 1. Get the crew inside

Link TheInsideJob to your debug target. It starts a local TCP server via ObjC `+load`. No setup code. DEBUG only, stripped from release builds.

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

Install the CLI and MCP server:

```bash
brew install RoyalPineapple/tap/buttonheist
```

Then add the MCP server to your project's `.mcp.json`:

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

This exposes 23 tools to your agent: `get_interface`, `activate`, `type_text`, `run_batch`, `get_screen`, and more. The agent discovers your app via Bonjour automatically:

```
Agent: "I need to log the user in"

→ get_interface
  textfield_email, textfield_password, button_login (12 elements)

→ run_batch([type_text into textfield_email, activate button_login])
  step 1: value → "user@example.com" ✓
  step 2: screen changed: login gone, dashboard appeared ✓
```

The agent stays focused on the task, not on driving the app.

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

But wait, there's more: gestures, recording, pasteboard, scroll modes, multi-device. See the [API Reference](docs/API.md).

## How It Works

The coordinate-based approach reads the accessibility tree, extracts element frames, and throws the rest away. The agent works with geometry, not meaning. Every action requires re-reading the full tree to know what happened.

Button Heist works from the inside, the same position VoiceOver occupies. The framework lives in your app. It doesn't snapshot the hierarchy and discard it. It holds the live tree and sees every change as it happens.

Three things follow from being inside:

### 1. Every action tells the agent what changed

After every command, Button Heist diffs the accessibility hierarchy and returns what moved: an **interface delta**. Tap "Login" and the response carries exactly which elements disappeared and which appeared:

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

Login screen gone, dashboard appeared, new elements ready to target. Value updates carry the property change inline: old value, new value, which element. When nothing changes, the delta says `"noChange"` and the agent pivots immediately.

The agent doesn't need to re-read the screen. The next decision starts from where the last one landed.

The crew inside keeps watch between jobs too. Every response carries a **background delta**: what changed in the UI while the agent was thinking. Content loaded, a dialog appeared, an animation settled. No stale intel.

### 2. Every action can verify itself

Each command can carry an `expect`, a declaration of what *should* happen. The framework checks the delta against the expectation and reports pass/fail inline:

```json
{
  "command": "activate",
  "target": {"heistId": "button_login"},
  "expect": "screen_changed"
}
```

Response: `{"expectation": {"met": true, "expectation": "screenChanged"}}`.

Three tiers: `screen_changed` (new view controller), `elements_changed` (anything in the hierarchy shifted), or `element_updated` with specific property checks. When an expectation fails, the response carries what *actually* happened.

The agent says what it expects. The framework says whether that happened.

### 3. Confidence unlocks batching

An agent that trusts its feedback loop can commit to a whole sequence at once. `run_batch` sends ordered steps in a single round trip. Each one gets its own delta and expectation check. If a step fails, the batch stops. The agent never pushes forward with bad state:

```json
{
  "command": "run_batch",
  "steps": [
    {"command": "type_text", "target": {"heistId": "textfield_email"}, "text": "user@example.com",
     "expect": {"element_updated": {"heistId": "textfield_email", "property": "value", "newValue": "user@example.com"}}},
    {"command": "activate", "target": {"heistId": "button_submit"}, "expect": "screen_changed"}
  ]
}
```

Two actions, two assertions, one round trip. If the email field doesn't update, the batch stops there.

Deltas, expectations, and batching, each one enabling the next. That's the compound advantage.

### 4. Every workflow writes its own regression test

Because every action carries a semantic target and a structured result, Button Heist can record an agent's session as a replayable `.heist` file. Each step is captured as a semantic matcher — label, traits, identifier — not coordinates or ephemeral IDs. The matcher targets the accessibility contract, not transient UI state, so it stays stable across runs.

Replay re-executes each step through the same dispatch path. If an element can no longer be found by its accessibility properties, the test fails. That failure means one thing: an accessibility contract broke. The label changed, a trait disappeared, a custom action was removed. JUnit XML output (`--junit`) puts these into CI.

The agent did its job. The test suite wrote itself. And because matchers are semantic, the same recording works on any device, any screen size, any orientation. A coordinate-based recording breaks the moment the layout shifts. A semantic recording breaks only when the accessibility interface breaks.

But the deepest advantage isn't speed. The agent and a VoiceOver user navigate the same hierarchy, interacting with the exact same elements. A coordinate-based tool can tap a button with broken accessibility and never notice. Button Heist can't. If VoiceOver can't see a control, neither can the agent. Every session is an accessibility audit, whether you asked for one or not.

Accessibility bugs stick around because the people who report them rarely have the leverage to get them prioritized. When an agent hits the same bug, it blocks automation and gets fixed. VoiceOver users benefit.

Agents already write our code. When they inspect what they've built, they see it through the accessibility layer. Make it good for them, and you've made it good for everyone.

## Benchmarks

Tested against a coordinate-based MCP server using the same model, same app, same tasks. 96 trials across 16 UI automation tasks. Both tools ran against the same app using standard iOS design patterns: forms, navigation, lists, controls.

|  | Button Heist | Coordinate-based |
|---|---|---|
| **Avg wall time** | 134s | 235s |
| **Avg turns** | 14 | 43 |
| **Avg cost** | $0.46 | $1.42 |
| **Tasks completed** | 16/16 | 16/16 |

**2.4x faster, 3.1x fewer turns, 3.1x cheaper.** The gap scales with complexity:

| Task type | Advantage | Why |
|---|---|---|
| Scroll + select | **4–6x** | Semantic find vs read-tree-compute-tap loops |
| Custom actions (order, complete, delete) | **3–5x** | Direct invocation vs visual menu navigation |
| Multi-screen workflows | **2–3x** | Deltas eliminate redundant tree reads |
| Scale (50+ actions) | **2.6x** | Per-action overhead compounds with task length |
| Simple taps | ~1x | Both approaches handle simple buttons well |

The difference is in what the agent gets back. A coordinate-based tap:

```
→ tap(x: 201, y: 456)
← "Tapped successfully"
```

The same action through Button Heist:

```
→ activate(heistId: "large_button")
← elements changed
  + text_size_large_staticText "Text Size, Large"
  - text_size_medium_staticText
  ~ large_button: traits "button" → "button, selected"
  ~ medium_button: traits "button, selected" → "button"
```

"Tapped successfully." That's the whole response. The agent has to re-read the entire screen to find out what happened. The delta reveals it all: which properties changed, which elements appeared and disappeared, the entirety of the new state. No follow-up needed.

That difference compounds. Every action without a delta costs a full tree read. Over a 50-action workflow, that's 50 extra round trips filling the context window. On our longest benchmark, Button Heist finished in under 8 minutes. The coordinate-based tool needed 20.

Full methodology and per-task data: [docs/BENCHMARKS.md](docs/BENCHMARKS.md)

---

*That's the job. What follows is the crew, the blueprints, and the fine print.*

---

## Meet the Crew

Every heist needs a team.

### The Score

| Name | Role |
|------|------|
| **TheScore** | The shared playbook. Wire protocol types, messages, and constants. The contract both sides speak |

### The Inside Team (iOS)

| Name | Role |
|------|------|
| **TheInsideJob** | The whole operation. Runs in your app: TCP server, Bonjour, accessibility hierarchy, command dispatch to the crew |
| **TheSafecracker** | Cracks the UI. Taps, swipes, drags, pinch, rotate, text entry, edit actions. Gets past any control via IOHIDEvent |
| **TheBagman** | Handles the goods. Element cache, hierarchy capture, heistId assignment, delta computation. Live view pointers never leave TheBagman |
| **TheMuscle** | Keeps the door. Token validation, Allow/Deny UI, session lock. Only one driver at a time |
| **TheStakeout** | The lookout. H.264 screen recording with frame timing and inactivity detection |
| **TheFingerprints** | Evidence. Touch indicators on screen during gestures, visible live and baked into TheStakeout's recordings |
| **TheTripwire** | Timing coordinator. Gates all "is the UI ready?" decisions: animation detection, presentation layer fingerprinting, settle waits |
| **ThePlant** | Runs the advance. ObjC `+load` hook boots TheInsideJob before any Swift runs. Link the framework, no app code |

### The Outside Team (macOS)

| Name | Role |
|------|------|
| **TheFence** | Runs the show. 42 commands dispatched from CLI and MCP, request-response correlation, async waits |
| **TheHandoff** | Gets everyone in position. Bonjour + USB discovery, TLS 1.3 connection, session state, injectable closures for testing |
| **TheBookKeeper** | The accountant. Session logs, artifact storage, heist recording and replay. Turns agent sessions into portable `.heist` files with semantic matchers |

### The Legitimate Front

| Name | Role |
|------|------|
| **ButtonHeistCLI** | Your orders. `list`, `session`, `activate`, `touch`, `type`, `screenshot`, `record`, and more |
| **ButtonHeistMCP** | Agent interface. 23 tools that call through TheFence so AI agents can run the job natively |

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

All docs: [API](docs/API.md) ・ [Architecture](docs/ARCHITECTURE.md) ・ [Wire Protocol](docs/WIRE-PROTOCOL.md) ・ [Auth](docs/AUTH.md) ・ [USB](docs/USB_DEVICE_CONNECTIVITY.md) ・ [Bonjour Troubleshooting](docs/BONJOUR_TROUBLESHOOTING.md) ・ [Reviewer's Guide](docs/REVIEWERS-GUIDE.md) ・ [Crew Dossiers](docs/dossiers/)

## License

Apache License 2.0. See `LICENSE`.

## Acknowledgments

- [KIF (Keep It Functional)](https://github.com/kif-framework/KIF). TheSafecracker's touch synthesis is built on KIF's pioneering work in programmatic iOS UI interaction.
- [AccessibilitySnapshot](https://github.com/cashapp/AccessibilitySnapshot). Used for parsing UIKit accessibility hierarchies (via our fork [AccessibilitySnapshotBH](https://github.com/RoyalPineapple/AccessibilitySnapshotBH)).

# What Makes Button Heist Different

Every iOS app already describes itself through the accessibility layer — the same semantic interface that millions of VoiceOver users depend on. Button Heist gives AI agents that interface directly, by running inside the app. When the agent understands the interface it's working with, everything else follows — better results, more reliably, faster.

## The Core Difference: In-Process

Button Heist runs **inside** the app. The framework is linked into the debug build. It reads live `UIAccessibility` objects directly and injects real `IOHIDEvent` touches through the hardware input pipeline. This gives the agent full access to the semantic interface the app already provides.

External tools operate **outside** the app process — shelling out to `idb`, `simctl`, Appium, or XCUITest. They get serialized snapshots through XPC, coordinate-based taps, and no feedback on what happened. The agent gets a lossy translation instead of the real thing.

### What in-process gives you

| Capability | Button Heist (in-process) | External tools |
|---|---|---|
| **Element activation** | Calls `accessibilityActivate()` on the live object — same as VoiceOver double-tap | Computes screen coordinates and synthesizes a tap at that point |
| **Interface deltas** | After every action, returns what changed: elements added, removed, values updated | Must re-read the entire tree and diff client-side |
| **Animation awareness** | Watches `CALayer` animations and reports when the UI has settled | Fixed sleep timers or polling |
| **Activation points** | Reads the element's actual `activationPoint` — correct even for custom hit-test areas | Computes center of frame — wrong for elements with custom hit regions |
| **Custom actions** | Calls `accessibilityPerformCustomAction` by name | Not accessible through external APIs |
| **Custom content** | Reads `accessibilityCustomContent` (AX custom descriptions) | Lost at the XPC boundary |
| **Touch fidelity** | Real `IOHIDEvent` objects through the full responder chain | Coordinate-only synthetic events through the simulator |
| **Multi-touch** | Pinch, rotate, two-finger tap, bezier paths, arbitrary polylines | Single-point taps, maybe swipe |
| **Idle detection** | Watches the actual `CALayer` animation tree | Guesses with `sleep()` |

## Ranked by Impact

Every optimization below reduces agent turns, tokens, or wall time. Ranked by measured impact from benchmarks (13-task suite, 60 trials at 100% accuracy excluding T3 known bug, April 2026).

### Tier 1: Fundamental (2-6x efficiency gain)

These are why the benchmark shows 4-15 turns where idb needs 19-60. You can't replicate them externally.

| # | Optimization | What it saves | External alternative |
|---|---|---|---|
| 1 | **Interface deltas on every action** | Eliminates `get_interface` after every action. Agents read the delta, not the whole tree. Saves 1 tool call per action. Benchmark: BH uses 2-6x fewer turns than idb across all 13 tasks. | Re-fetch full tree, diff client-side. 2x the calls, 10x the tokens. |
| 2 | **Batch execution with expectations** | 10 actions in 1 MCP call, 2-4 seconds total. Each step has pass/fail expectations. Short-circuits on failure. Benchmark: batching saves 10-34% of turns with zero accuracy cost. | 10 separate MCP round-trips. 10x the latency, 10x the call overhead. |
| 3 | **Stable heistId targeting** | Copy ID from `get_interface`, paste into `activate`. Never breaks across value changes. One field, zero ambiguity. | Coordinate math from frame + offset. Breaks when layout shifts. |
| 4 | **Accessibility-first activation** | `activate` calls `accessibilityActivate()` — works on every control VoiceOver can reach, including custom components that ignore coordinate taps. | Tap at computed center point. Fails on custom hit-test areas, overlapping elements, and controls behind other views. |

### Tier 2: Major (save 30-50% of remaining turns)

| # | Optimization | What it saves | External alternative |
|---|---|---|---|
| 5 | **scroll_to_visible with element matching** | One call to find an element in a 100+ item list. Returns scroll count, coverage percentage, exhaustive confirmation. | Manual scroll loop: `scroll` → `get_interface` → check → repeat. 6-10 calls for what BH does in 1. |
| 6 | **get_interface(full: true) / explore** | One call returns every element on the screen, including off-screen content in scroll views. 126 elements in the Market Catalog. | Impossible externally. You'd have to scroll manually and merge snapshots. |
| 7 | **Animation-aware idle detection** | `wait_for_idle` watches real CALayer animations. `wait_for` waits for a specific element predicate. No wasted polls. | `sleep(2)` and hope. Or poll: `get_tree` → check → sleep → repeat. |
| 8 | **Unified targeting (heistId OR matcher)** | Target by ID when stable, by label+traits when dynamic. Same flat fields on every command. | External tools have one targeting mode (usually coordinates). No predicate matching. |

### Tier 3: Quality of Life (save 5-15 minutes per session)

| # | Optimization | What it saves | External alternative |
|---|---|---|---|
| 9 | **Progressive error diagnostics** | "3 elements match: label='Modals'" / "near miss: matched all except label" / full element dump. Agent self-corrects. | "Element not found." Agent retries blind. |
| 10 | **Unit-point swipe** | `start: (0.9, 0.5), end: (0.2, 0.5)` — device-independent, element-relative. No coordinate math. | Absolute pixel coordinates. Must `get_screen` first to compute. Breaks across device sizes. |
| 11 | **Matcher filtering on get_interface** | `get_interface(traits: ["adjustable"])` returns just the sliders. Agent asks questions about the screen without parsing 100+ elements. | Get full tree, filter client-side. Wastes tokens on irrelevant elements. |
| 12 | **Pasteboard without system dialog** | `set_pasteboard` + paste bypasses the iOS "Allow Paste" dialog. Enables keyboard-free text entry workflows. | Paste triggers system dialog that blocks automation. Must use keyboard character-by-character. |
| 13 | **Disabled element blocking** | "Element is disabled (has 'notEnabled' trait)" — prevents wasted actions. | Tap at coordinates, get no feedback, wonder why nothing happened. |
| 14 | **connect at runtime** | Switch between sim and device mid-session. No MCP restart. | Restart the MCP server with new config. Lose session state. |
| 15 | **Screen recording with touch overlay** | H.264/MP4 with fingerprint indicators. Evidence capture for bug reports. | Screenshot-only, no video. Manual screen recording via simctl (no touch overlay). |

### Tier 4: Impossible Externally

These capabilities don't have external alternatives at any cost.

| # | Capability | Why it's impossible externally |
|---|---|---|
| 16 | **Real IOHIDEvent multi-touch** | External tools can't inject hardware-level touch events. They use XCUITest synthetics which don't go through the full responder chain. |
| 17 | **Custom accessibility actions** | `accessibilityCustomActions` are in-memory closures on live objects. They don't serialize across XPC. |
| 18 | **Custom accessibility content** | `accessibilityCustomContent` (AX custom descriptions) is lost at the process boundary. |
| 19 | **Activation point fidelity** | Some elements override `accessibilityActivationPoint` to point at a different location than their frame center. External tools never see this. |
| 20 | **The accessibility feedback loop** | Agents and VoiceOver users share a dependency — the same interface. Agent failures surface accessibility bugs. External tools bypass this interface entirely. |

## Against Specific Alternatives

### vs. XCUITest / Appium / WebDriverAgent

XCUITest is Apple's UI testing framework. Appium and WebDriverAgent wrap it for remote control. They operate from a **separate test runner process** that talks to the app through XPC.

**What they lose at the process boundary:**
- `accessibilityCustomContent` — gone
- `accessibilityCustomRotors` — gone
- `respondsToUserInteraction` — gone
- `accessibilityActivationPoint` — serialized but sometimes stale
- Custom actions — partially available but unreliable on combined elements
- Interface deltas — not available, must re-snapshot and diff
- Animation state — not observable, must poll or sleep

**What Button Heist adds:**
- Semantic deltas after every action (no re-fetch)
- `wait_for` with predicate matching (no polling loops)
- Batch execution with per-step expectations (no round-trip per action)
- Stable element identifiers that survive value changes
- Real IOHIDEvent multi-touch gestures

### vs. ios-simulator-mcp (joshuayoes)

The most widely used iOS MCP tool. Architecture: Node.js → idb CLI → gRPC → idb_companion → AXPTranslator → CoreSimulator XPC → Simulator. Six layers of indirection.

| | ios-simulator-mcp | Button Heist |
|---|---|---|
| Integration | Zero — works with any app | Embed one framework |
| Element targeting | Coordinate-based only | HeistId + matcher (label, traits, identifier) |
| Action feedback | None — re-read tree | Semantic delta on every action |
| Animation handling | `sleep()` | CALayer animation watching |
| Multi-touch | No | Full suite (pinch, rotate, bezier, polyline) |
| Accessibility actions | No | Increment, decrement, custom actions |
| Device support | Simulator only | Simulator + USB devices |
| Benchmark: turns | 54 (full workflow), 60 (controls) | **14** (full workflow), **9** with batching |
| Benchmark: accuracy | 11/12 (failed marathon) | **60/60** (100%)\* |

### vs. XcodeBuildMCP (Sentry)

The largest iOS MCP tool by stars. Focused on the full Apple development workflow — building, testing, project management. UI automation is one workflow among many.

**Complementary, not competitive.** XcodeBuildMCP handles the build/deploy lifecycle. Button Heist handles the app interaction. They work well together — use XcodeBuildMCP to build and install, Button Heist to drive the app.

| | XcodeBuildMCP | Button Heist |
|---|---|---|
| Build/deploy | Full xcodebuild integration | Not its job |
| UI interaction | Coordinate-based via simctl | Accessibility-first, element-level |
| Accessibility data | Basic (via simctl accessibility audit) | Full tree with custom content/actions |
| Deltas | No | Yes, every action |
| Device support | Sim + device | Sim + device |

### vs. Vision-based tools (Midscene, etc.)

Vision tools screenshot the screen, send it to a VLM, and get back coordinates to tap. No accessibility tree at all.

**Fundamental limitation:** The VLM can't see what VoiceOver can. Disabled states, custom actions, adjustable ranges, trait information, accessibility values — all invisible in pixels. The agent is guessing where to tap based on what things look like, not what they are.

Give the agent the accessibility interface and it knows an element is a disabled adjustable stepper with value "3" and an increment action. It can reason about state, call actions by name, and confirm outcomes — because the app already describes itself.

## The Accessibility Feedback Loop

Agents and VoiceOver users share a dependency: the accessibility interface. When the agent navigates your app, it's using the same paths that millions of blind and low-vision people rely on every day.

That shared dependency creates a feedback loop. If the agent can't find a control, neither can VoiceOver. If a stepper exposes `adjustable` when it's disabled, the agent sees that — and so does every VoiceOver user. Accessibility bugs surface as agent failures. Fixing them improves the experience for both.

No external tool creates this loop. They operate outside the accessibility interface, so they can interact with controls that VoiceOver users can't reach — and they'll never surface the gap.

## The Trade-Off

In-process access means linking one framework into your debug build. For production apps with CI/CD, add `TheInsideJob` as a debug-only dependency — it's stripped from release builds, and the integration is two lines in your build config. For apps you don't control, use an external tool.

That's the trade: embed the framework and the agent gets the full semantic interface. Skip it and the agent gets a lossy translation. Everything that makes Button Heist faster — deltas, expectations, batching, semantic activation — follows from being inside the app.

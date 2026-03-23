# Button Heist

I've been experimenting with this for the last couple of months. It's very much 0.0.1, but it pulls together a few threads I've been thinking about for a long time.

## Where This Comes From

Part of it goes back to the mobile test engineering days with Dimitris and jmartin, and to my time working on KIF — including the predicate system and the building-block API.

I've always had pretty strong feelings about KIF. It got some really important things right. It used the real `UIAccessibility` interface, so it was implicitly validating the accessibility surface of the app, and because it ran in-process it gave us a useful kind of grey-box testing when we needed to get our hands dirty.

But KIF was also brittle as hell. The touch injection was never really the problem. The problem was the architecture around search: building predicates with things like `usingLabel(...)` and `usingTraits(...)`, recursively walking the hierarchy, and then failing either to find the right view or to prove that it was tappable enough to safely interact with. That search stage is where a huge amount of KIF flake came from.

At the same time, I've never been satisfied with the alternatives. XCUITest gives you a more reliable test model in some ways, but I keep running into the limits of its abstraction — especially as I've been adding more advanced accessibility support to our design system. It obscures the real accessibility surface, including actual accessibility values, and it has no support for things like custom actions.

More recently, on the UI systems side, I've been working on the accessibility parser in AccessibilitySnapshot. One of the things I helped push there was separating the parser from the snapshot renderer so it could produce a structured, codable graph of the accessibility tree — not just a snapshot-oriented view model.

Button Heist is the connection between those two ideas. Instead of the old KIF flow where the test searches for elements from the outside, parse the `UIAccessibility` tree up front and hand that structured interface to the agent directly. Then keep the good parts of KIF: in-process interaction, touch injection, and the ability to get your fingers dirty when needed. With a little extra plumbing, it mirrors the VoiceOver pattern too: try `accessibilityActivate()` first, then fall back to tapping the correct activation point if that fails.

## The Core Idea: Inside-Out, Not Outside-In

For folks who've used [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp), the difference I care about is that Button Heist is an **inside-out** model — structured `UIAccessibility` data plus in-process interaction — rather than an **outside-in** loop over screenshots and coordinates.

That means less output for the agent to chew through, much less dependence on machine vision, and the ability to return structured diffs after actions instead of forcing the agent to re-parse the whole screen every time. Because it's living in-process, it can also proactively push screen changes instead of making the agent poll for everything.

Agents are blind. Unless you spend tokens on machine vision for every interaction (slow, expensive, non-deterministic), an agent interacting with an iOS app cannot see the screen. It's in exactly the same position as a VoiceOver user. Apple solved this decades ago with `UIAccessibility` — a full-fidelity interface designed for users who navigate without vision. Agents should get the same interface. Not a translation of it. Not a screenshot of it. The real thing.

ios-simulator-mcp doesn't give agents the real thing. It provides the accessibility tree *after* it's been translated through `AXPTranslator` into macOS accessibility vocabulary and serialized across five process boundaries. iOS-specific properties that have no macOS equivalent — activation points, custom content, custom rotors, `respondsToUserInteraction` — are dropped. What the agent receives is a degraded hybrid with the most useful iOS-native properties missing.

Button Heist reads `UIAccessibility` objects directly, in-process, with full fidelity. The agent gets the same data VoiceOver gets. Every property, every action, every traversal hint — nothing lost in translation. It doesn't matter whether the app uses UIKit, SwiftUI, or both — they're all `UIAccessibility` objects at the accessibility layer.

## What ios-simulator-mcp Actually Does

ios-simulator-mcp is a Node.js MCP server that wraps Facebook's `idb` CLI. When an agent calls a tool, the chain is:

```
Agent → Node.js MCP Server → idb CLI (Python) → gRPC → idb_companion (Swift/ObjC) → AXPTranslator → CoreSimulator XPC → Simulator
```

Five layers of indirection between the agent and the app. At each boundary, data is serialized and filtered. By the time the accessibility tree reaches the agent, it's been translated from iOS accessibility into macOS accessibility vocabulary (via `AXPTranslator`), losing iOS-specific properties that have no macOS equivalent.

When the agent taps, coordinates are sent back through the same chain in reverse. The Simulator runtime synthesizes a touch event on the agent's behalf.

## What Gets Lost

This isn't theoretical. Here's what ios-simulator-mcp can't give an agent, and why it matters in practice.

### The agent can't tell what's tappable

ios-simulator-mcp doesn't return `respondsToUserInteraction`. The agent gets a flat list of elements with frames and labels, but can't distinguish a tappable button from a decorative icon. It has to guess — or tap everything and see what happens.

I return `respondsToUserInteraction` for every element. The agent knows before it acts.

### The agent taps the wrong spot

iOS elements declare an `activationPoint` — the coordinate where they want to receive taps. For standard buttons this is the frame center, but for irregularly shaped controls, grouped elements, or custom hit-test regions, it's not. `activationPoint` doesn't survive the XPC serialization through `AXPTranslator`. ios-simulator-mcp never sees it.

ios-simulator-mcp computes the frame center and sends `idb ui tap X Y`. Sometimes it misses. The agent doesn't know why.

I read `activationPoint` directly from the live `UIAccessibility` object and tap there. Or I call `accessibilityActivate()` on the object itself — the method Apple designed for exactly this purpose. No coordinate guessing. This works the same whether the app uses UIKit, SwiftUI, or both — they're all `UIAccessibility` objects at the accessibility layer.

### The agent can't tell what changed

After every action, ios-simulator-mcp requires the agent to re-fetch the entire accessibility tree and diff it mentally to understand what happened. For a complex UI with hundreds of elements, that's a lot of tokens spent on "find the difference" instead of making progress.

I return **interface deltas** after every action: elements added, removed, and changed. The agent sees: "tapped Login → pushed SettingsViewController, 14 elements added, 3 removed." No re-fetching, no diffing, no wasted tokens.

ios-simulator-mcp can't offer this. Deltas require comparing live object state across snapshots, which requires being in the app process.

### The agent can't tell when the UI is ready

After a tap triggers a navigation transition, how long should the agent wait before reading the new screen? ios-simulator-mcp has no answer. The agent either:
- Sleeps for a fixed duration (1-2 seconds, fragile — breaks on slow animations, wastes time on fast ones)
- Screenshots repeatedly and checks if things changed (adds latency + VLM cost per check)

I watch CALayer animations directly and report when the UI has settled. `wait_for_idle` tells the agent exactly when the transition is done. No guessing, no polling.

### The agent can't scroll properly

ios-simulator-mcp exposes `idb ui swipe`, which drags from one coordinate to another. Want to scroll a list? Compute start/end coordinates and swipe. Want to scroll to a specific element? Keep swiping and re-checking the tree. Want to scroll to the bottom? Keep swiping until nothing changes.

I call `UIScrollView.setContentOffset` directly. `scroll` scrolls one page. `scroll_to_visible` scrolls until a target element is on screen. `scroll_to_edge` scrolls to the top or bottom instantly. The agent says what it wants; I handle the mechanics.

### The agent can't use accessibility actions

iOS accessibility defines semantic actions: `accessibilityActivate()`, `accessibilityIncrement()`, `accessibilityDecrement()`, custom actions. These are the correct way to interact with controls — they're what VoiceOver uses.

ios-simulator-mcp can't call these. It doesn't have the objects. The idb companion *does* have element-level APIs internally (`tapWithError:`, `scrollWithDirection:error:`, `setValue:error:`), but these aren't exposed through the `idb` CLI. ios-simulator-mcp has no way to reach them.

I call these methods directly on the live `UIAccessibility` objects. "Increment the stepper" calls `accessibilityIncrement()`. "Perform the Delete custom action" calls it by name. No coordinate approximations. UIKit and SwiftUI both surface the same `UIAccessibility` protocol — I don't care which framework built the view.

### The agent can't do multi-touch

Pinch to zoom. Two-finger rotate. Long press. Bezier path traces. None of these are possible through ios-simulator-mcp. `idb ui` supports `tap`, `swipe`, and `text` — single-finger, single-gesture.

I synthesize multi-finger `IOHIDEvent` sequences. Pinch, rotate, two-finger tap, arbitrary polyline gestures. These touches are indistinguishable from hardware input — they go through `hitTest(_:with:)` and the full responder chain.

### The agent gets a worse accessibility tree

Side-by-side comparison of what the agent receives per element:

| Property | ios-simulator-mcp (via idb) | Button Heist |
|---|---|---|
| Label | `AXLabel` | `label` |
| Value | `AXValue` | `value` |
| Identifier | `AXUniqueId` | `identifier` |
| Hint | — | `hint` |
| VoiceOver description | — | `description` |
| Frame | `AXFrame` (string) + `frame` (dict, redundant) | `frame` (CGRect) |
| Activation point | — | `activationPoint` |
| Traits | Bitmask → strings | Bitmask → strings |
| Responds to interaction | — | `respondsToUserInteraction` |
| Custom actions | Names only | Names + images |
| Custom content | — | Label/value/importance |
| Custom rotors | — | Names + result markers |
| Traversal order | Implicit (array position) | Explicit index |
| Container types | macOS AX role strings | Typed enum (group, list, landmark, tabBar, dataTable) |

The left column is what macOS Accessibility sees after `AXPTranslator` converts iOS accessibility. The right column is what VoiceOver sees natively. For an agent trying to understand an iOS UI, the native data is strictly more useful.

### The agent is stuck in the simulator

ios-simulator-mcp only works with the iOS Simulator. It's in the name. There's no path to physical devices — the entire stack (idb, CoreSimulator XPC, AXPTranslator) is simulator infrastructure.

Button Heist connects to real devices over USB via `xcrun devicectl`. Same embedded framework, same `UIAccessibility` data, same touch injection. The app doesn't know or care whether it's running on a simulator or a phone.

This matters because we don't ship simulator builds. We ship to real hardware — real iPhones connected to real Square readers. An agent that can only interact with the simulator can never verify that a payment flow works end-to-end with actual hardware. It can't test Bluetooth pairing with a reader, NFC tap behavior, or any of the device-specific paths that only exist on physical hardware. Button Heist can. Same agent, same tools, pointed at a real device with real Square hardware attached.

### idb is deprecated

Facebook has archived `idb`. The community is maintaining it, but without official support. ios-simulator-mcp's entire stack depends on it. Every `idb` bug or incompatibility with a new Xcode version is now a community problem, not a Facebook problem.

Button Heist has no external dependency on deprecated tooling. The embedded framework operates on `UIAccessibility` objects — the same protocol that UIKit and SwiftUI both conform to.

## The Cost of Switching

I know what you're thinking: ios-simulator-mcp works with any app, zero setup. Button Heist requires linking TheInsideJob into the app's debug build.

That's real, but it's a familiar cost. We already embed debug frameworks:

- **Reveal** ($179/year) embeds `RevealServer.xcframework` for runtime UI inspection. Same pattern — framework linked in debug, auto-initializes, no code required.
- **FLEX** (14,600 GitHub stars) embeds an in-app debug overlay. View hierarchy, heap scanning, network monitor. Widely adopted.

Linking TheInsideJob is the same one-time, five-minute task. Add the framework to the debug configuration, build, done. It's the standard debug-tool integration that every iOS developer has done before.

**The deeper point**: Reveal embeds for the same reason I do. The data you need — live objects, activation points, custom content, animation state — only exists inside the app process. Reveal couldn't build its accessibility inspector or constraint editor from outside. I can't build interface deltas or real touch injection from outside. The architecture demands it.

ios-simulator-mcp's zero-setup advantage is real for testing apps you don't own. For apps you're building — where you have the source, control the build, and are already embedding debug tools — the integration cost is negligible.

## What ios-simulator-mcp Does Better

I'm not going to pretend there aren't trade-offs:

1. **Zero integration.** Works with any app. No project changes. If you want to poke at a third-party app, ios-simulator-mcp just works.

2. **`npx` install.** `npx ios-simulator-mcp` and you're running. Button Heist requires cloning and building from source. I need to close this gap.

3. **App install and launch.** `idb install` and `idb launch` are built in. Button Heist requires manual `xcrun simctl install` / `simctl launch`. Solvable — just haven't wired it up yet.

4. **Simulator lifecycle.** They can open and manage Simulator.app. I don't manage the simulator at all.

5. **Anthropic blog mention.** ios-simulator-mcp was featured in Anthropic's engineering blog. That matters for discoverability and trust.

Items 2-4 are gaps I can close without architectural changes. Items 1 and 5 are structural — Button Heist will never be zero-integration (and shouldn't try to be), and discoverability requires going public.

## Why This Matters for Your Workflow

Forget the abstract argument. Here's what happens in daily development.

**An agent using ios-simulator-mcp** taps a button, waits an arbitrary duration, re-fetches the entire accessibility tree, parses hundreds of elements to figure out what changed, sometimes taps the wrong spot because it computed the frame center instead of the activation point, can't scroll to a specific element without a retry loop, and can't interact with steppers, sliders, or custom controls without coordinate hacks.

**An agent using Button Heist** taps a button by calling `accessibilityActivate()`, gets back a delta showing exactly what changed, knows the UI is settled because `wait_for_idle` told it so, scrolls to any element with `scroll_to_visible`, and interacts with any control using the semantic action Apple designed for it.

The second agent is faster, more reliable, wastes fewer tokens, and can do things the first agent literally cannot (multi-touch, accessibility actions, animation-aware waiting). That difference compounds with every interaction.

## Head-to-Head: Agent vs Agent

Micro-benchmarks are interesting. What actually matters is: how does a real agent perform, doing a real task, using each tool? I gave the same Claude Sonnet agent the same 11-step workflow — navigate to a todo list, add three items, complete one, demonstrate filtering, then navigate to a calculator, multiply two three-digit numbers, divide by a two-digit number, and return to the root screen — and measured everything.

### Methodology

- **Model**: Claude Sonnet 4.6, via `claude -p` (Claude Code CLI)
- **App**: AccessibilityTestApp running on iPhone 16 Pro Simulator (iOS 26.1)
- **Task**: 11-step workflow — todo CRUD, filtering, calculator arithmetic, navigation
- **Trials**: 3 per tool, app reset between each trial
- **Measurement**: Token usage, cost, wall time, and turn count reported by Claude Code's JSON output

### Results

| Metric | ios-simulator-mcp | Button Heist |
|---|--:|--:|
| **Turns (avg)** | 40 | **33** |
| **Wall time (avg)** | 171s | **127s** |
| **API time (avg)** | 163s | **113s** |
| **Context consumed (avg)** | 1,569,558 | **1,258,173** |
| **Output tokens (avg)** | 6,668 | **3,657** |
| **Cost (avg)** | $0.72 | **$0.57** |

Both tools completed all tasks in all trials. Button Heist was **21% cheaper, 26% faster, and used 20% less context**.

### Individual Trials

| Trial | Turns | Wall | Cost | Context | Output |
|---|--:|--:|--:|--:|--:|
| idb #1 | 41 | 174s | $0.7422 | 1,622,523 | 6,677 |
| idb #2 | 40 | 169s | $0.7124 | 1,545,347 | 6,702 |
| idb #3 | 40 | 169s | $0.7110 | 1,540,806 | 6,626 |
| BH #1 | 34 | 137s | $0.6205 | 1,320,673 | 3,684 |
| BH #2 | 32 | 117s | $0.5411 | 1,212,757 | 3,445 |
| BH #3 | 33 | 126s | $0.5542 | 1,241,091 | 3,843 |

The idb results are tight: 40-41 turns, $0.71-0.74, 169-174s. Button Heist is tighter: 32-34 turns, $0.54-0.62, 117-137s.

### Why Button Heist Uses Fewer Turns

The turn count difference (40 → 33) is the most important metric. Every turn means the agent re-reads its full context window, reasons about it, and generates a response. Fewer turns = less time, less cost, less context pressure.

**ios-simulator-mcp** requires a separate `ui_describe_all` call after every tap to see what happened. Tap a button? That's two turns: one for the tap, one for the re-read. The idb agent can't skip this — without deltas, it's flying blind after each action.

**Button Heist** returns a delta with every action. The agent sees what changed inline. It still calls `get_interface` when it needs the full picture (navigating to a new screen, verifying final state), but it doesn't need to after every single tap.

### Why the Output Token Difference Matters

The idb agent generated 6,668 output tokens vs Button Heist's 3,657 — **82% more reasoning**. The agent had to work harder: computing frame centers for coordinates, diffing accessibility trees to understand state changes, and reasoning about whether taps landed correctly. With Button Heist, the agent spent less time on mechanics and more on the actual task.

### What the Agent Sees Per Element

**ios-simulator-mcp** returns the raw idb JSON per element:

```json
{
  "AXFrame": "{{16.0, 120.7}, {326.3, 39.7}}",
  "AXUniqueId": null,
  "frame": {"y": 120.7, "x": 16.0, "width": 326.3, "height": 39.7},
  "role_description": "heading",
  "AXLabel": "ButtonHeist Test App",
  "content_required": false,
  "type": "Heading",
  "title": null,
  "help": null,
  "custom_actions": [],
  "AXValue": null,
  "enabled": true,
  "role": "AXHeading",
  "children": [],
  "subrole": null
}
```

15 fields. 5 are null. `AXFrame` and `frame` are redundant. `role`, `role_description`, `subrole` are macOS AX concepts. `content_required` is a macOS assistive tech flag. **47% noise.**

**Button Heist** returns:

```json
{
  "actions": ["activate"],
  "activationPointX": 201,
  "activationPointY": 193.5,
  "description": "Controls Demo. Button.",
  "frameHeight": 51,
  "frameWidth": 370,
  "frameX": 16,
  "frameY": 168,
  "label": "Controls Demo",
  "order": 0,
  "respondsToUserInteraction": true,
  "traits": ["button"]
}
```

12 fields. No nulls. No redundancy. **100% signal.** Every field tells the agent what it needs: what the element is, where to tap it, whether it's tappable, and what actions are available.

### The Idle Detection Gap

ios-simulator-mcp has no animation detection. After a tap triggers a navigation transition, the idb tool returns immediately with no indication of whether the UI has settled. The agent has to immediately call `ui_describe_all` and hope the transition is complete. If it reads too early, it gets a stale or mid-animation tree and has to retry.

Button Heist watches CALayer animations directly. `wait_for_idle` tells the agent exactly when the transition is done. Actions that trigger navigation automatically wait for idle before returning the delta. No guessing, no retrying, no stale reads.

### Text Input

| Tool | Median | Method |
|---|---|---|
| idb text | **218ms** | Bulk string injection |
| Button Heist | **1,012ms** | Per-key via `UIKeyboardImpl` |

**idb is 5x faster for text input.** This is a real trade-off. idb injects the string as a single operation. I simulate individual key presses through the keyboard input system, which is slower but higher fidelity — it triggers `textFieldDidChange`, autocorrect, and input validation the same way a real user would. For agents typing search queries, the speed difference rarely matters. For testing form validation or input masking, the fidelity difference does.

## Batching: And Then It Gets Better

The base results above show Button Heist is 21% cheaper and 26% faster. But I haven't shown the biggest lever yet: `run_batch`.

`run_batch` lets the agent send multiple actions in a single MCP call. Instead of one turn per tap, the agent batches an entire sequence — calculator digits, form fill workflows, navigation chains — into one round trip. ios-simulator-mcp has no equivalent. Every action is its own MCP call, every call is its own turn, and every turn re-reads the full context window.

### What Batching Looks Like

Adding a todo item without batching (3 turns):
1. `activate` — tap text field
2. `type_text` — type "Buy groceries"
3. `activate` — tap Add button

With batching (1 turn):
```json
{
  "steps": [
    {"command": "activate", "identifier": "buttonheist.todo.newItemField"},
    {"command": "type_text", "text": "Buy groceries"},
    {"command": "activate", "identifier": "buttonheist.todo.addButton"}
  ]
}
```

The calculator sequence `456×789=` without batching is 8 turns. With batching, it's 1.

### Batching Benchmark

Same methodology, same task, 3 additional trials with `run_batch` available.

| Metric | ios-simulator-mcp | Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Turns (avg)** | 40 | 33 | **13** |
| **Wall time (avg)** | 171s | 127s | **82s** |
| **Context consumed (avg)** | 1,569,558 | 1,258,173 | **432,652** |
| **Cost (avg)** | $0.72 | $0.57 | **$0.30** |

| Trial | Turns | Wall | Cost | Context | Output |
|---|--:|--:|--:|--:|--:|
| BH+batch #1 | 14 | 84s | $0.2974 | 471,491 | 2,832 |
| BH+batch #2 | 14 | 82s | $0.3544 | 454,634 | 2,694 |
| BH+batch #3 | 11 | 80s | $0.2542 | 371,832 | 2,780 |

### Savings vs ios-simulator-mcp

| | Button Heist | BH + Batching |
|---|--:|--:|
| Cost reduction | 21% | **58%** |
| Wall time reduction | 26% | **52%** |
| Context reduction | 20% | **72%** |
| Turn reduction | 18% | **68%** |

Batching cuts turns from 40 to 13, wall time from 171s to 82s, and context usage by 72%. The cost drops from $0.72 to $0.30 — **58% cheaper** than ios-simulator-mcp for the same work.

### Projected Cost at Scale

| | ios-simulator-mcp | Button Heist | BH + Batching |
|---|--:|--:|--:|
| 100 runs/day | $72/day | $57/day | **$30/day** |
| Annual (250 workdays) | $18,046 | $14,298 | **$7,550** |
| Annual savings vs idb | — | $3,748 | **$10,496** |

## Try It

ios-simulator-mcp got us started. It's fine for basic agent interaction — tap, screenshot, read the tree.

Button Heist is what comes next. Agents that reliably navigate complex UIs, interact with custom controls, understand what changed after each action, don't waste tokens re-fetching the world after every tap, and work on real devices with real Square hardware.

The embedding cost is the same cost we already pay for Reveal. The capabilities it unlocks — deltas, idle detection, real touches, semantic actions, full-fidelity `UIAccessibility` data — aren't missing features in ios-simulator-mcp. They're architectural impossibilities for any tool running outside the app process.

Give it a shot. I think you'll see the difference immediately.

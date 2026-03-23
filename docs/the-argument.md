# The Button Heist

I've been experimenting with this for the last couple of months. It's very much 0.0.1, but it pulls together a few threads I've been thinking about for a long time.

## Where This Comes From

Part of it goes back to the mobile test engineering days and to my time working on KIF — including the predicate system and the building-block API.

I've always had pretty strong feelings about KIF. It got some really important things right. It used the real `UIAccessibility` interface, so it was implicitly validating the accessibility surface of the app, and because it ran in-process it gave us a useful kind of grey-box testing when we needed to get our hands dirty.

But KIF was also brittle as hell. The touch injection was never really the problem. The problem was the architecture around search: building predicates with things like `usingLabel(...)` and `usingTraits(...)`, recursively walking the hierarchy, and then failing either to find the right view or to prove that it was tappable enough to safely interact with. That search stage is where a huge amount of KIF flake came from.

At the same time, I've never been satisfied with the alternatives. XCUITest gives you a more reliable test model in some ways, but I keep running into the limits of its abstraction — especially as I've been adding more advanced accessibility support to our design system. It obscures the real accessibility surface, including actual accessibility values, and it has no support for things like custom actions.

The missing piece was always structured data. KIF had the right architecture — in-process, real `UIAccessibility` objects, real touches — but it never had a way to parse the accessibility tree into something a consumer could reason about holistically. It only knew how to search for one element at a time.

That's what my more recent work on the accessibility parser in AccessibilitySnapshot was building toward. Separating the parser from the snapshot renderer so it could produce a structured, codable graph of the full accessibility tree — not just a snapshot-oriented view model, but typed elements with containers, traversal order, activation points, custom actions, and custom content. The complete picture of what VoiceOver sees, as data.

The Button Heist is the connection between those two threads. Take the parser's structured output and hand it to an agent as the interface. Keep the good parts of KIF: in-process interaction, touch injection, and the ability to get your fingers dirty when needed. Mirror the VoiceOver interaction pattern: try `accessibilityActivate()` first, then fall back to tapping the correct activation point if that fails.

KIF proved that `UIAccessibility` has the right shape for programmatic UI interaction — and that in-process access is what gives you the fingers to actually use it. The parser turns that into structured data an agent can consume. The Button Heist connects them and replaces the part that broke: instead of brittle predicate-based search, parse the whole tree proactively and let the agent decide what to do with it.

## The Core Idea: Accessibility Is the Agent Interface

Agents are blind. Unless you spend tokens on machine vision for every interaction (slow, expensive, non-deterministic), an agent interacting with an iOS app cannot see the screen. It's in exactly the same position as a VoiceOver user.

The accessibility interface is the best interface for this problem. Not because it's a convenient hack, but because it was *designed* for exactly this: structured, semantic data that lets you reason about an app without seeing it. Labels describe purpose. Traits describe behavior. Actions describe capability. Activation points tell you where to interact. Traversal order tells you how the pieces relate. No visual noise, no pixel interpretation, no guessing — just the information you need to understand and operate the UI.

A VoiceOver user doesn't read a manual for each app. The accessibility interface is the consistent interaction model across every app on iOS. An agent using The Button Heist gets the same thing. It already knows what "button" means and what "activate" does, the same way a person develops an intuition for using VoiceOver. You don't have to teach the agent how to interact with *your* app — you just have to make sure your app's accessibility is good.

This is something KIF gave us too, by design. When KIF tests broke, it was often because the accessibility surface was wrong — labels missing, traits incorrect, elements not reachable. KIF enforced accessibility quality as a side effect of using `UIAccessibility` as the interaction layer. The Button Heist carries that forward: if the agent can't navigate your app, a VoiceOver user can't either. The quality of the agent's experience *is* the quality of your accessibility.

For folks who've used [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp), the difference I care about is that The Button Heist is an **inside-out** model — structured `UIAccessibility` data plus in-process interaction — rather than an **outside-in** loop over screenshots and coordinates. The agent doesn't need to be taught how to compute tap targets from frame coordinates. It doesn't need a prompt full of tool-specific instructions. The interface itself is enough.

ios-simulator-mcp doesn't give agents the real accessibility interface. It provides the tree *after* it's been translated through `AXPTranslator` into macOS accessibility vocabulary and serialized across five process boundaries. iOS-specific properties that have no macOS equivalent — activation points, custom content, custom rotors, `respondsToUserInteraction` — are dropped. What the agent receives is a degraded hybrid with the most useful iOS-native properties missing.

The Button Heist reads `UIAccessibility` objects directly, in-process, with full fidelity. The agent gets the same data VoiceOver gets. Every property, every action, every traversal hint — nothing lost in translation. It doesn't matter whether the app uses UIKit, SwiftUI, or both — they're all `UIAccessibility` objects at the accessibility layer.

That means less output for the agent to chew through, much less dependence on machine vision, and the ability to return structured diffs after actions instead of forcing the agent to re-parse the whole screen every time. Because it's living in-process, it can also proactively push screen changes instead of making the agent poll for everything.

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

| Property | ios-simulator-mcp (via idb) | The Button Heist |
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

The Button Heist connects to real devices over USB via `xcrun devicectl`. Same embedded framework, same `UIAccessibility` data, same touch injection. The app doesn't know or care whether it's running on a simulator or a phone.

This matters because we don't ship simulator builds. We ship to real hardware — real iPhones connected to real Square readers. An agent that can only interact with the simulator can never verify that a payment flow works end-to-end with actual hardware. It can't test Bluetooth pairing with a reader, NFC tap behavior, or any of the device-specific paths that only exist on physical hardware. The Button Heist can. Same agent, same tools, pointed at a real device with real Square hardware attached.

### idb is deprecated

Facebook has archived `idb`. The community is maintaining it, but without official support. ios-simulator-mcp's entire stack depends on it. Every `idb` bug or incompatibility with a new Xcode version is now a community problem, not a Facebook problem.

The Button Heist has no external dependency on deprecated tooling. The embedded framework operates on `UIAccessibility` objects — the same protocol that UIKit and SwiftUI both conform to.

## The Cost of Switching

I know what you're thinking: ios-simulator-mcp works with any app, zero setup. The Button Heist requires linking TheInsideJob into the app's debug build.

That's real, but it's a familiar cost. We already embed debug frameworks:

- **Reveal** ($179/year) embeds `RevealServer.xcframework` for runtime UI inspection. Same pattern — framework linked in debug, auto-initializes, no code required.
- **FLEX** (14,600 GitHub stars) embeds an in-app debug overlay. View hierarchy, heap scanning, network monitor. Widely adopted.

Linking TheInsideJob is the same one-time, five-minute task. Add the framework to the debug configuration, build, done. It's the standard debug-tool integration that every iOS developer has done before.

**The deeper point**: Reveal embeds for the same reason I do. The data you need — live objects, activation points, custom content, animation state — only exists inside the app process. Reveal couldn't build its accessibility inspector or constraint editor from outside. I can't build interface deltas or real touch injection from outside. The architecture demands it.

ios-simulator-mcp's zero-setup advantage is real for testing apps you don't own. For apps you're building — where you have the source, control the build, and are already embedding debug tools — the integration cost is negligible.

## What ios-simulator-mcp Does Better

I'm not going to pretend there aren't trade-offs:

1. **Zero integration.** Works with any app. No project changes. If you want to poke at a third-party app, ios-simulator-mcp just works.

2. **`npx` install.** `npx ios-simulator-mcp` and you're running. The Button Heist requires cloning and building from source. I need to close this gap.

3. **App install and launch.** `idb install` and `idb launch` are built in. The Button Heist requires manual `xcrun simctl install` / `simctl launch`. Solvable — just haven't wired it up yet.

4. **Simulator lifecycle.** They can open and manage Simulator.app. I don't manage the simulator at all.

5. **Anthropic blog mention.** ios-simulator-mcp was featured in Anthropic's engineering blog. That matters for discoverability and trust.

Items 2-4 are gaps I can close without architectural changes. Items 1 and 5 are structural — The Button Heist will never be zero-integration (and shouldn't try to be), and discoverability requires going public.

## Why This Matters for Your Workflow

Forget the abstract argument. Here's what happens in daily development.

**An agent using ios-simulator-mcp** taps a button, waits an arbitrary duration, re-fetches the entire accessibility tree, parses hundreds of elements to figure out what changed, sometimes taps the wrong spot because it computed the frame center instead of the activation point, can't scroll to a specific element without a retry loop, and can't interact with steppers, sliders, or custom controls without coordinate hacks.

**An agent using The Button Heist** taps a button by calling `accessibilityActivate()`, gets back a delta showing exactly what changed, knows the UI is settled because `wait_for_idle` told it so, scrolls to any element with `scroll_to_visible`, and interacts with any control using the semantic action Apple designed for it.

The second agent is faster, more reliable, wastes fewer tokens, and can do things the first agent literally cannot (multi-touch, accessibility actions, animation-aware waiting). That difference compounds with every interaction.

## Head-to-Head: Agent vs Agent

Micro-benchmarks are interesting. What actually matters is: how does a real agent perform, doing a real task, using each tool? I gave the same Claude Sonnet agent the same 11-step workflow — navigate to a todo list, add three items, complete one, demonstrate filtering, then navigate to a calculator, multiply two three-digit numbers, divide by a two-digit number, and return to the root screen — and measured everything.

### Methodology

- **Models**: Claude Sonnet 4.6 and Claude Haiku 4.5, via `claude -p` (Claude Code CLI)
- **App**: AccessibilityTestApp running on iPhone 16 Pro Simulator (iOS 26.1)
- **Task**: 11-step workflow — todo CRUD, filtering, calculator arithmetic, navigation
- **Trials**: 6 per configuration for Sonnet (interleaved, app reset between each). 3 per configuration for Haiku.
- **Measurement**: Token usage, cost, wall time, and turn count reported by Claude Code's JSON output
- **Outliers**: One BH Sonnet trial hit a retry loop (64 turns, $1.59) and was excluded and replaced. One Haiku BH trial completed the task but didn't produce the expected summary keywords — marked as incomplete.

### Sonnet Results (n=6 each)

| Metric | ios-simulator-mcp | The Button Heist |
|---|--:|--:|
| **Turns** | 41 ± 1.4 | **31 ± 4.0** |
| **Wall time** | 175s ± 11 | **123s ± 12** |
| **Context consumed** | 1,550,475 ± 67,840 | **1,137,241 ± 203,119** |
| **Output tokens** | 6,678 ± 115 | **3,644 ± 268** |
| **Cost** | $0.73 ± $0.02 | **$0.55 ± $0.06** |

All 12 Sonnet trials completed all tasks. The Button Heist was **25% cheaper, 29% faster, and used 26% less context**.

### Haiku Results

| Metric | ios-simulator-mcp (n=3) | The Button Heist (n=3) |
|---|--:|--:|
| **Turns** | 44 ± 0.6 | **35 ± 4.0** |
| **Wall time** | 132s ± 7 | **126s ± 31** |
| **Context consumed** | 2,482,405 ± 51,841 | **1,983,693 ± 337,833** |
| **Output tokens** | 10,184 ± 784 | **7,774 ± 1,279** |
| **Cost** | $0.37 ± $0.02 | **$0.30 ± $0.07** |

Haiku uses more context tokens than Sonnet — it reasons less efficiently — but costs less per token. The savings pattern holds: **17% cheaper, 20% less context**. idb completed 3/3, BH completed 2/3 (one trial completed the task but failed the summary check).

### Individual Sonnet Trials

| Trial | Turns | Wall | Cost | Context | Output |
|---|--:|--:|--:|--:|--:|
| idb #1 | 41 | 174s | $0.7422 | 1,622,523 | 6,677 |
| idb #2 | 40 | 169s | $0.7124 | 1,545,347 | 6,702 |
| idb #3 | 40 | 169s | $0.7110 | 1,540,806 | 6,626 |
| idb #4 | 41 | 197s | $0.7678 | 1,542,727 | 6,733 |
| idb #5 | 39 | 167s | $0.7287 | 1,435,126 | 6,492 |
| idb #6 | 43 | 175s | $0.7385 | 1,616,322 | 6,839 |
| BH #1 | 34 | 137s | $0.6205 | 1,320,673 | 3,684 |
| BH #2 | 32 | 117s | $0.5411 | 1,212,757 | 3,445 |
| BH #3 | 33 | 126s | $0.5542 | 1,241,091 | 3,843 |
| BH #4 | 31 | 129s | $0.5672 | 1,112,095 | 3,661 |
| BH #5 | 23 | 101s | $0.4517 | 746,473 | 3,244 |
| BH #6 | 32 | 126s | $0.5637 | 1,190,362 | 3,989 |

The idb results are tight: 39-43 turns, $0.71-0.77, 167-197s. The Button Heist ranges wider (23-34 turns) because the agent sometimes finds efficient paths through the task — that variability is a feature, not noise. The floor is lower because the tools give the agent room to be clever.

### Why The Button Heist Uses Fewer Turns

The turn count difference (40 → 33) is the most important metric. Every turn means the agent re-reads its full context window, reasons about it, and generates a response. Fewer turns = less time, less cost, less context pressure.

**ios-simulator-mcp** requires a separate `ui_describe_all` call after every tap to see what happened. Tap a button? That's two turns: one for the tap, one for the re-read. The idb agent can't skip this — without deltas, it's flying blind after each action.

**The Button Heist** returns a delta with every action. The agent sees what changed inline. It still calls `get_interface` when it needs the full picture (navigating to a new screen, verifying final state), but it doesn't need to after every single tap.

### Why the Output Token Difference Matters

The idb agent generated 6,668 output tokens vs The Button Heist's 3,657 — **82% more reasoning**. The agent had to work harder: computing frame centers for coordinates, diffing accessibility trees to understand state changes, and reasoning about whether taps landed correctly. With The Button Heist, the agent spent less time on mechanics and more on the actual task.

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

**The Button Heist** returns:

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

The Button Heist watches CALayer animations directly. `wait_for_idle` tells the agent exactly when the transition is done. Actions that trigger navigation automatically wait for idle before returning the delta. No guessing, no retrying, no stale reads.

`run_batch` lets the agent combine multiple actions into a single MCP call. Adding a todo item (tap field, type text, tap Add) goes from 3 round trips to 1. Each step can carry an `expect` field — `"screen_changed"`, `"layout_changed"`, or `{"valueChanged": {"newValue": "5"}}` — and the response reports whether each expectation was met:

### Text Input

| Tool | Median | Method |
|---|---|---|
| idb text | **218ms** | Bulk string injection |
| The Button Heist | **1,012ms** | Per-key via `UIKeyboardImpl` |

**idb is 5x faster for text input.** This is a real trade-off. idb injects the string as a single operation. I simulate individual key presses through the keyboard input system, which is slower but higher fidelity — it triggers `textFieldDidChange`, autocorrect, and input validation the same way a real user would. For agents typing search queries, the speed difference rarely matters. For testing form validation or input masking, the fidelity difference does.

## Batching: And Then It Gets Better

The base results above show The Button Heist is 25% cheaper and 31% faster. But I haven't shown the biggest lever yet: `run_batch`.

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

Same methodology, same task. Sonnet: 6 trials. Haiku: 3 trials.

**Sonnet:**

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching (n=6) |
|---|--:|--:|--:|
| **Turns** | 41 | 31 | **12 ± 1.6** |
| **Wall time** | 175s | 123s | **83s ± 4** |
| **Context consumed** | 1,550,475 | 1,137,241 | **409,017 ± 58,807** |
| **Cost** | $0.73 | $0.55 | **$0.30 ± $0.04** |

**Haiku:**

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching (n=3) |
|---|--:|--:|--:|
| **Turns** | 44 | 35 | **18 ± 1.5** |
| **Wall time** | 132s | 126s | **78s ± 4** |
| **Context consumed** | 2,482,405 | 1,983,693 | **911,397 ± 100,464** |
| **Cost** | $0.37 | $0.30 | **$0.16 ± $0.02** |

| Trial | Turns | Wall | Cost | Context | Output |
|---|--:|--:|--:|--:|--:|
| Sonnet batch #1 | 14 | 84s | $0.2974 | 471,491 | 2,832 |
| Sonnet batch #2 | 14 | 82s | $0.3544 | 454,634 | 2,694 |
| Sonnet batch #3 | 11 | 80s | $0.2542 | 371,832 | 2,780 |
| Sonnet batch #4 | 14 | 88s | $0.2915 | 458,993 | 2,801 |
| Sonnet batch #5 | 11 | 86s | $0.3390 | 340,775 | 3,050 |
| Sonnet batch #6 | 11 | 78s | $0.2740 | 356,380 | 2,484 |
| Haiku batch #1 | 17 | 73s | $0.1479 | 811,557 | 4,793 |
| Haiku batch #2 | 18 | 80s | $0.1626 | 910,161 | 4,818 |
| Haiku batch #3 | 20 | 81s | $0.1780 | 1,012,475 | 5,312 |

### Savings vs ios-simulator-mcp

| | The Button Heist | BH + Batching |
|---|--:|--:|
| **Sonnet** | | |
| Cost reduction | 25% | **58%** |
| Wall time reduction | 29% | **52%** |
| Context reduction | 26% | **73%** |
| Turn reduction | 24% | **69%** |
| **Haiku** | | |
| Cost reduction | 17% | **55%** |
| Wall time reduction | 4% | **40%** |
| Context reduction | 20% | **63%** |
| Turn reduction | 19% | **58%** |

With batching, Sonnet drops from $0.73 to $0.30 — **58% cheaper** for the same work. Haiku drops from $0.37 to $0.16 — **55% cheaper**. The savings are consistent across models.

### Projected Cost at Scale

| | ios-simulator-mcp | The Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Sonnet** | | | |
| Per run | $0.73 | $0.55 | **$0.30** |
| 100 runs/day | $73/day | $55/day | **$30/day** |
| Annual (250 workdays) | $18,300 | $13,700 | **$7,500** |
| **Haiku** | | | |
| Per run | $0.37 | $0.30 | **$0.16** |
| 100 runs/day | $37/day | $30/day | **$16/day** |
| Annual (250 workdays) | $9,163 | $7,590 | **$4,070** |

These projections extrapolate from one workflow type. Your actual savings will depend on task complexity, screen density, and how much of the work is sequential taps vs reads. The per-run advantage is structural — it'll hold across tasks — but the exact multiplier will vary.

## Try It

ios-simulator-mcp got us started. It's fine for basic agent interaction — tap, screenshot, read the tree.

The Button Heist is what comes next. Agents that reliably navigate complex UIs, interact with custom controls, understand what changed after each action, don't waste tokens re-fetching the world after every tap, and work on real devices with real Square hardware.

The embedding cost is the same cost we already pay for Reveal. The capabilities it unlocks — deltas, idle detection, real touches, semantic actions, full-fidelity `UIAccessibility` data — aren't missing features in ios-simulator-mcp. They're architectural impossibilities for any tool running outside the app process.

Give it a shot. I think you'll see the difference immediately.

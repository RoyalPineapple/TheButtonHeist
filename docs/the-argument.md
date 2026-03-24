# The Button Heist

I've been experimenting with this for the last couple of months. It's very much 0.0.1, but it pulls together a few threads I've been thinking about for a long time.

## Where This Comes From

Two open-source libraries from Block matter here, both in production use for years — over a decade in KIF's case. I've worked in both of them.

[**KIF**](https://github.com/kif-framework/KIF) (Keep It Functional) is an iOS UI testing framework that's been around since 2011. It runs in-process, uses `UIAccessibility` to find elements, and synthesizes real touches through `IOHIDEvent`. Because it operates on the actual accessibility interface, KIF tests implicitly validate the app's accessibility surface. The downside: KIF is brittle. The touch injection was never the problem — the problem was the search architecture. Building predicates, recursively walking the hierarchy, failing to find the right view or to prove it was tappable. That's where the flake came from.

[**AccessibilitySnapshot**](https://github.com/cashapp/AccessibilitySnapshot) is a snapshot testing library from Cash App that renders the accessibility tree of a view into a visual snapshot. I've been working on separating its parser from the snapshot renderer so it can produce a structured, codable graph of the full accessibility tree — typed elements with containers, traversal order, activation points, custom actions, and custom content. Not just a snapshot view model, but the complete picture of what VoiceOver sees, as data.

The Button Heist connects the two. The parser's structured output becomes the agent's interface. KIF's in-process interaction and touch injection become the agent's hands. Instead of brittle predicate-based search, parse the whole tree proactively and let the agent decide what to do with it.

## The Core Idea: Accessibility Is the Agent Interface

Agents can't see the screen. Unless you spend tokens on machine vision for every interaction, an agent interacting with an iOS app is in the same position as a VoiceOver user.

Accessibility was designed for this — structured, semantic data that lets you reason about an app without seeing it. Labels describe purpose. Traits describe behavior. Actions describe capability. Activation points tell you where to interact. Traversal order tells you how the pieces relate.

A VoiceOver user doesn't read a manual for each app. The accessibility interface is the consistent interaction model across every app on iOS. An agent using The Button Heist gets the same thing. It already knows what "button" means and what "activate" does. You don't have to teach the agent how to interact with your app — you just have to make sure your app's accessibility is good.

KIF gave us this too, by design. When KIF tests broke, it was often because the accessibility surface was wrong — labels missing, traits incorrect, elements not reachable. The Button Heist carries that forward: if the agent can't navigate your app, a VoiceOver user probably can't either.

## How It Works

The Button Heist is an MCP server backed by an embedded framework (TheInsideJob) that runs inside the app's debug build. The framework connects to the MCP server over TCP, and the agent talks to the MCP server using standard tools.

### What the agent gets

When the agent calls `get_interface`, it receives the full accessibility tree as structured JSON:

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

This is the same structured output the accessibility parser already produces for our snapshot tests — the same parser, the same data, just handed to an agent instead of a snapshot renderer. UIKit, SwiftUI, it doesn't matter — they're all `UIAccessibility` objects at the parser level. These are the tools we've been using to validate our apps for decades, just with an agent in charge instead of a test script.

### How the agent interacts

The interaction model is KIF's, cleaned up. The agent calls `activate` with an element's order index or identifier. Under the hood, The Button Heist tries `accessibilityActivate()` on the live object first, then falls back to a synthetic tap at the element's `activationPoint` — the same escalation path KIF used, minus the predicate search that made KIF brittle.

The same pattern extends to richer controls: `accessibilityIncrement()` and `accessibilityDecrement()` for steppers and sliders, named custom actions for context menus and swipe actions, `scroll_to_visible` to scroll until a target element is on screen, `scroll_to_edge` to jump to the top or bottom.

Touch injection uses `IOHIDEvent` objects through `hitTest(_:with:)` and the full responder chain — the same technique KIF used, including multi-touch gestures (pinch, rotate, two-finger tap, bezier paths).

### Deltas

After every action, The Button Heist returns an interface delta — elements added, removed, and changed. The agent sees what happened without re-fetching the entire tree.

This requires running in-process. The framework holds live references to the accessibility objects and can diff state across snapshots.

### Idle detection

After a tap triggers a navigation transition, The Button Heist watches `CALayer` animations and reports when the UI has settled. `wait_for_idle` tells the agent when the transition is done.

### Batching

`run_batch` lets the agent send multiple actions in a single MCP call. Adding a todo item (tap field, type text, tap Add) goes from 3 turns to 1. The calculator sequence `456×789=` goes from 8 turns to 1. Fewer turns means the agent re-reads its context window less often.

### Real devices

The Button Heist works on physical devices, not just the simulator. Same framework, same data, same touch injection. That means an agent can test the full stack including hardware — an iPad connected to a Square Stand, for example.

## Head-to-Head: Agent vs Agent

I ran the same Claude agent through the same 11-step workflow — todo CRUD, filtering, calculator arithmetic, navigation — using each tool. Same model, same app, same task. Full data in [benchmark-data.md](./benchmark-data.md).

### Sonnet (n=6 each, all trials completed)

| Metric | ios-simulator-mcp | The Button Heist |
|---|--:|--:|
| Turns | 41 ± 1 | 31 ± 4 |
| Wall time | 175s | 123s |
| Output tokens | 6,678 | 3,644 |
| Context consumed | 1,550,475 | 1,137,241 |

The ios-simulator-mcp agent needed extra prompt instructions explaining how to compute tap coordinates from frame data. The Button Heist agent didn't — the accessibility data is self-describing.

### With batching (n=6 Sonnet, n=3 Haiku)

| | ios-simulator-mcp | BH | BH + Batching |
|---|--:|--:|--:|
| Sonnet context | 1,550K | 1,137K | 409K |
| Sonnet wall | 175s | 123s | 83s |
| Sonnet turns | 41 | 31 | 12 |
| Haiku context | 2,482K | 1,984K | 911K |
| Haiku turns | 44 | 35 | 18 |

ios-simulator-mcp has no batching equivalent. Every action is its own turn, and every turn re-reads the full context window.

## vs ios-simulator-mcp

For folks who've used [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp), the architectural difference matters.

ios-simulator-mcp is a Node.js MCP server wrapping Facebook's `idb` CLI:

```
Agent → Node.js → idb (Python) → gRPC → idb_companion → AXPTranslator → CoreSimulator XPC → Simulator
```

The Button Heist reads `UIAccessibility` objects in-process:

```
Agent → MCP Server → Embedded Framework (in-app) → UIAccessibility objects
```

The accessibility tree that ios-simulator-mcp returns has been translated from iOS into macOS vocabulary via `AXPTranslator`. Properties that don't have macOS equivalents get dropped:

| Property | ios-simulator-mcp | The Button Heist |
|---|---|---|
| Activation point | Dropped | Present |
| `respondsToUserInteraction` | Dropped | Present |
| Hint | Dropped | Present |
| VoiceOver description | Dropped | Present |
| Custom content (`AXCustomContent`) | Dropped | Present |
| Custom rotors | Dropped | Present |
| Available actions | Not exposed | Per-element |
| Traversal order | Implicit | Explicit index |
| Frame | Redundant (string + dict) | Single CGRect |
| Interaction model | Coordinate-based | Element-based |

Other differences:

- **Deltas**: ios-simulator-mcp doesn't have them. Every tap requires a full tree re-read.
- **Idle detection**: not available. The agent guesses when animations finish.
- **Accessibility actions**: can't call `accessibilityIncrement()`, `accessibilityDecrement()`, or custom actions.
- **Multi-touch**: single-finger tap and swipe only.
- **Batching**: not available.
- **Physical devices**: simulator only.
- **idb**: Facebook has archived it. Community-maintained without official support.

## The Cost of Switching

ios-simulator-mcp works with any app, zero setup. The Button Heist requires linking TheInsideJob into the app's debug build.

That's a real difference, but it's a familiar one. We already embed Reveal and FLEX in debug builds. Linking TheInsideJob is the same kind of integration — add the framework, build, done.

The reason it requires embedding is the same reason Reveal embeds: the data you need only exists inside the app process. Activation points, custom content, animation state, live object references — none of that crosses process boundaries. Reveal couldn't build its accessibility inspector from outside. The Button Heist can't build deltas or real touch injection from outside.

For apps you don't own, ios-simulator-mcp is the right choice. For apps you're building, the integration cost is five minutes.

## What ios-simulator-mcp Does Better

There are real trade-offs:

1. **Zero integration.** Works with any app, no project changes.
2. **`npx` install.** The Button Heist requires building from source. I need to close this gap.
3. **App install and launch.** Built into idb. The Button Heist requires manual `xcrun simctl` commands.
4. **Simulator lifecycle management.** I don't manage the simulator at all.
5. **Anthropic blog feature.** That matters for discoverability.

Items 2-4 are solvable without architectural changes. Items 1 and 5 are structural.

## Try It

I've got demo videos showing the agent navigating the app from natural-language instructions, and one showing the full loop — agent finds a bug, fixes it, reloads the app, verifies the fix.

If you're using ios-simulator-mcp now, The Button Heist is worth trying on the same workflow. The setup is a few minutes and the difference is pretty obvious once you see the agent working with deltas instead of re-reading the whole tree after every tap.

# The Button Heist

The accessibility tree is the right interface for AI agents on iOS. It gives agents the autonomy to interact with apps confidently — understanding what each control is, how to interact with it, and whether the interaction worked — without needing to be taught per-app mechanics or second-guess every tap. In benchmarks, that confidence translates to fewer turns, less wasted context, and faster task completion.

The Button Heist is an MCP server backed by an embedded framework that runs inside the app's debug build. It reads `UIAccessibility` objects in-process via the AccessibilitySnapshot parser and interacts with the app using KIF-style touch injection. It works on simulators and real devices.

## Why Accessibility

Agents can't see the screen. An agent interacting with an iOS app is in the same position as a VoiceOver user — it needs structured, semantic data to reason about the UI without seeing it.

The `UIAccessibility` interface already provides this: labels, traits, actions, activation points, traversal order. A well-structured accessibility surface hands the agent everything it needs to interact with a switch row, an increment action, or a delete action without any discovery step. The agent doesn't need per-app instructions — it just needs the app's accessibility to be good.

That creates a useful loop. Using The Button Heist to test your app implicitly validates the accessibility surface, because the agent navigates through the same interface VoiceOver users depend on. If the agent can't find a control or activate it, a VoiceOver user can't either. That was a design goal of KIF's predicate API, and The Button Heist carries it forward.

## How It Works

The agent calls `get_interface` and receives the full accessibility tree as structured JSON — the same output the AccessibilitySnapshot parser produces for our snapshot tests, just handed to an agent instead of a snapshot renderer:

```json
{
  "actions": ["activate"],
  "activationPointX": 201,
  "activationPointY": 193.5,
  "label": "Controls Demo",
  "order": 0,
  "respondsToUserInteraction": true,
  "traits": ["button"]
}
```

UIKit, SwiftUI — it doesn't matter. They're all `UIAccessibility` objects at the parser level.

The agent interacts by calling `activate` with an element's order index or identifier. Under the hood, The Button Heist tries `accessibilityActivate()` first, then falls back to a synthetic tap at the element's `activationPoint`. The same pattern extends to `accessibilityIncrement()` / `accessibilityDecrement()` for steppers, named custom actions for context menus, and `scroll_to_visible` / `scroll_to_edge` for scroll views. Touch injection uses real `IOHIDEvent` objects through the full responder chain, including multi-touch gestures.

Every action returns an interface delta — elements added, removed, and changed — so the agent sees what happened without re-fetching the entire tree. `wait_for_idle` watches `CALayer` animations and reports when the UI has settled after a transition.

`run_batch` lets the agent combine multiple actions into a single MCP call. Adding a todo item (tap field, type text, tap Add) goes from 3 round trips to 1. Each step can carry an `expect` field — `"screen_changed"`, `"layout_changed"`, or `{"value": "expected text"}` — and the response reports whether each expectation was met:

```json
{
  "completedSteps": 3,
  "expectations": {"checked": 3, "met": 3, "allMet": true}
}
```

If an expectation isn't met, the batch stops with diagnostics. The agent doesn't have to re-read the tree to verify outcomes — the tool reports them directly.

The Button Heist also works on physical devices. Same framework, same tools, pointed at real hardware instead of a simulator — an iPad connected to a Square Stand, for example.

## Benchmarks

I ran the same Claude Sonnet agent through four tasks — a multi-screen workflow, calculator arithmetic, todo list CRUD, and a settings round-trip — using each tool. Same model, same app, randomized inputs, n=3 per cell. Full trial data in [benchmark-data.md](./benchmark-data.md).

**Turns (mean, n=3 per cell):**

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **Full workflow** (11 steps) | 50 | 25 | **10** | **10** |
| **Calculator** | 23 | 15 | **5** | **5** |
| **Todo CRUD** | 37 | 14 | **7** | **8** |
| **Settings** | 31 | 11 | **10** | **13** |

Each column gives the agent more autonomy:

- **BH base**: The agent gets richer data per element — activation points, available actions, interaction flags — so it understands the interface without extra reasoning. It doesn't need prompt instructions explaining how to compute tap coordinates. The accessibility data already tells it how to interact with each element. **35–65% fewer turns.**
- **Batching**: The agent can express a multi-step intention in a single call and get back what happened at each step. It doesn't have to wait for a round trip between every tap. **68–81% fewer turns.**
- **Expectations**: The agent can state what it expects to happen and get structured confirmation. It doesn't have to re-read the tree and reason about whether a tap worked — the tool tells it directly. **58–80% fewer turns.**

Batching and expectations both depend on running in-process — batching needs inline deltas between steps, and expectations need the framework to detect screen changes, layout mutations, and value updates without a full tree re-read.

The per-task breakdown shows where each advantage applies. Calculator and todo CRUD collapse to 5–7 turns with batching — these are heavily sequential tasks where combining actions eliminates round trips. Settings shows a smaller improvement because the task is more interactive (picker selections) with less opportunity to batch.

## How It Compares to ios-simulator-mcp

ios-simulator-mcp reads the accessibility tree through Apple's `AXPTranslator`, which bridges iOS accessibility into macOS accessibility concepts. Properties without macOS equivalents — activation points, `respondsToUserInteraction`, hints, custom content, custom rotors, available actions — get dropped in translation.

The Button Heist reads `UIAccessibility` objects directly inside the app process, so none of that is lost.

Other differences: ios-simulator-mcp doesn't have deltas (every tap requires a full tree re-read), idle detection (the agent guesses when animations finish), accessibility actions (`increment`, `decrement`, custom actions), multi-touch, batching, expectations, or physical device support. Its dependency on Facebook's `idb` is also a consideration — idb has been archived and is community-maintained.

The detailed field-by-field comparison is in [ios-simulator-mcp-comparison.md](./ios-simulator-mcp-comparison.md).

## Trade-offs

ios-simulator-mcp has real advantages:

1. **Zero integration.** Works with any app, no project changes. The Button Heist requires linking a framework into the debug build — the same pattern as Reveal or FLEX, but still a step.
2. **`npx` install.** The Button Heist currently requires building from source.
3. **App install, launch, and simulator lifecycle.** Built into idb. The Button Heist doesn't manage any of this.
4. **Maturity.** The Button Heist is 0.0.1. ios-simulator-mcp has a larger user base and was featured on Anthropic's blog.

For apps you don't control, ios-simulator-mcp is the right tool. For apps you're building — where you can embed the framework and where richer accessibility data, deltas, batching, expectations, and real device support matter — The Button Heist is worth trying.

## Background

Two open-source libraries from Block come together here.

[**KIF**](https://github.com/kif-framework/KIF) is an iOS UI testing framework that's been in production use for over a decade. It runs in-process, uses `UIAccessibility` to find elements, and synthesizes real touches through `IOHIDEvent`. I worked on KIF's predicate-based API. KIF got the architecture right — in-process, accessibility-driven, real touch injection — but the search layer that built predicates and walked the hierarchy was where the brittleness came from.

[**AccessibilitySnapshot**](https://github.com/cashapp/AccessibilitySnapshot) is a snapshot testing library from Cash App. I've been working on separating its parser from the snapshot renderer so it produces a structured, codable graph of the full accessibility tree — typed elements with containers, traversal order, activation points, custom actions, and custom content.

The Button Heist connects the two. The parser's structured output becomes the agent's interface. KIF's interaction model and touch injection become the agent's hands. Instead of brittle predicate-based search, parse the whole tree proactively and hand it to the agent directly.

## Demos

Two demo videos:
- Agent navigating the app from natural-language instructions
- Full loop — agent finds a bug, fixes it, reloads the app, verifies the fix

Happy to walk anyone through the setup.

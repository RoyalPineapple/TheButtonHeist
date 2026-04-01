# The Button Heist

Every iOS app already describes itself. The accessibility layer tells VoiceOver — and the millions of blind and low-vision people who depend on it — what every control is, what it does, what state it's in, and how to interact with it. Give an AI agent that same interface and it understands controls by name, interacts with them semantically, and confirms whether each interaction worked. When the agent understands the interface it's working with, everything else follows — better results, more reliably, faster.

Button Heist is an MCP server backed by an embedded framework that runs inside the app's debug build. It reads `UIAccessibility` objects in-process via the AccessibilitySnapshot parser and interacts with the app using KIF-style touch injection. It works on simulators and real devices.

## Why Accessibility

Every iOS app already has a complete semantic interface. The `UIAccessibility` layer provides labels, traits, actions, activation points, and traversal order — everything a non-visual intelligence needs to operate the app. Blind and low-vision users depend on this interface every day through VoiceOver. It's proven, it's comprehensive, and it's already built into every well-made iOS app.

Give an agent that same interface and it can interact with a switch row, call an increment action, or trigger a delete action by name — without any discovery step. The agent doesn't need per-app instructions. It just needs the app's accessibility to be good. And when it is, everything else follows.

Agents and VoiceOver users share this dependency. When the agent navigates through the accessibility interface, it's using the same paths that millions of people rely on. If the agent can't find a control or activate it, neither can VoiceOver. Fixing one fixes both. That was a design goal of KIF's predicate API, and Button Heist carries it forward.

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

`run_batch` lets the agent combine multiple actions into a single MCP call. Adding a todo item (tap field, type text, tap Add) goes from 3 round trips to 1. Each step can carry an `expect` field, and the response reports whether each expectation was met:

```json
{
  "completedSteps": 3,
  "expectations": {"checked": 3, "met": 3, "allMet": true}
}
```

If an expectation isn't met, the batch stops with diagnostics. The agent doesn't have to re-read the tree to verify outcomes — the tool reports them directly.

Expectations follow a "say what you know" design. The agent expresses what it cares about and omits what it doesn't:

- `"screen_changed"` — did the view controller change?
- `"layout_changed"` — were elements added or removed?
- `{"value": "5"}` — does the target element's value match exactly?
- `{"valueChanged": {"newValue": "5"}}` — did any element's value change to "5"?
- `{"valueChanged": {"heistId": "counter", "oldValue": "3", "newValue": "5"}}` — did this specific element transition from "3" to "5"?
- `{"valueChanged": {}}` — did any value change at all?

Every field in `valueChanged` is optional. Provide more to tighten the check, fewer to loosen it. The same mechanism scales from "did anything change?" to "did this exact element transition from 3 to 5?" — the agent says as much or as little as it knows. The framework scans the interface delta for any match and reports what actually happened on miss, so the agent gets diagnostics without needing a follow-up call.

This composes with batching. A 5-step batch where each step carries a targeted expectation becomes a verification chain in a single MCP call. If step 3 expected `{"valueChanged": {"newValue": "5"}}` but the value went to "4", the batch stops there with diagnostics — no ambiguity about which action failed or why.

The Button Heist also works on physical devices. Same framework, same tools, pointed at real hardware instead of a simulator — an iPad connected to a Square Stand, for example.

## Benchmarks

Three MCP servers — Button Heist, mobile-mcp, and ios-simulator-mcp (idb) — tested against the same 13-task suite. Same model (Claude Sonnet 4.6), same app, same simulator, 3 trials per task per config. Full data in `benchmarks/results/`.

All three tools achieve high accuracy on most tasks. The differentiation is efficiency.

**Turns (mean per cell, rounded — 13 tasks, n=2–3 trials each):**

| Task | idb | mobile-mcp | BH |
|---|--:|--:|--:|
| **Full workflow** (11 steps) | 49 | 61 | **25** |
| **Calculator** | 24 | 20 | **15** |
| **Todo CRUD** | 40 | 43 | **14** |
| **Settings roundtrip** | 31 | 17 | **11** |
| **Notes workflow** | 55 | 42 | **13** |
| **Controls gauntlet** | 67 | timeout | **26** |
| **Scroll hunt** | 39 | 56 | **19** |
| **Bug verification** | 68 | 56 | **23** |
| **Marathon** (5 screens) | 124 | 172 | **75** |
| **Swipe actions** | 34 | 80 | **7** |
| **Scroll to find** | 28 | 47 | **15** |
| **Stepper increment** | 27 | **13** | 15 |
| **Search + tap** | 23 | **19** | 21 |

BH consistently shows 2-3x fewer turns across the suite, with the gap widening on gesture-heavy tasks (swipe actions: 7t vs 34t vs 80t). mobile-mcp wins on two simple tasks (stepper, search) where coordinate-based interaction has no overhead disadvantage — a useful control.

Specific capability differences:

- **Swipe actions** (T9): BH calls `perform_custom_action("Add to Order")` — one tool call per row. Coordinate-based tools must swipe to reveal the button, re-read elements, then tap. **7 turns vs 34 (idb) vs 80 (mobile-mcp).**
- **Controls gauntlet** (T5): BH completes mixed controls (toggles, steppers, sliders, pickers) in 26 turns. idb needs 67. mobile-mcp times out on all 3 trials.
- **Search + tap** (T12): Near parity across all configs — BH shows no meaningful advantage on tasks where the tools are equivalent. **19–23 turns.**

Each BH mode gives the agent more autonomy:

- **BH base**: Semantic addressing — the agent says *what* to interact with, not *where*. No coordinate math, no frame parsing.
- **Batching**: Multi-step intentions in a single call. Calculator collapses from 15 turns to 5. Each step returns what changed. Coordinate-based tools can't batch because each tap depends on seeing the screen after the previous action.
- **Expectations**: Inline outcome verification. The agent doesn't re-read the tree — the tool reports whether the action worked.

Batching is the big win. Expectations help on verification-heavy tasks but add overhead where the agent doesn't need confirmation. Both depend on running in-process — batching needs inline deltas, expectations need the framework to detect state changes without a full tree re-read.

## How It Compares

### ios-simulator-mcp (idb)

Reads the accessibility tree through Apple's `AXPTranslator`, which bridges iOS accessibility into macOS accessibility concepts. Properties without macOS equivalents — activation points, `respondsToUserInteraction`, hints, custom content, custom rotors, available actions — get dropped in translation. The Button Heist reads `UIAccessibility` objects directly inside the app process, so none of that is lost.

idb is the stronger competitor on accuracy — it matches or beats BH's correctness on every task with three-way data. But it takes 2-3x more turns to get there. Doesn't have deltas, idle detection, accessibility actions, multi-touch, batching, inline outcome expectations (screen changes, layout mutations, value transitions), or device support. Its dependency on Facebook's `idb` (archived, community-maintained) is a consideration.

The detailed field-by-field comparison is in [ios-simulator-mcp-comparison.md](./ios-simulator-mcp-comparison.md).

### mobile-mcp

Coordinate-based via WebDriverAgent. Popular (~4k GitHub stars), easy to set up. Matches BH on accuracy for simple tasks but has the highest variance — four tasks had at least one timeout or spiral trial. Gesture-heavy tasks show the biggest gap (swipe actions: 80 turns vs BH's 7). Cannot batch actions because each tap depends on seeing the updated screen.

## Trade-offs

The coordinate-based tools have real advantages:

1. **Zero integration.** Work with any app, no project changes. The Button Heist requires linking a framework into the debug build — the same pattern as Reveal or FLEX, but still a step.
2. **Easy install.** `npx` for mobile-mcp, `npx` for idb. The Button Heist currently requires building from source.
3. **App install, launch, and simulator lifecycle.** Built into both competitors. The Button Heist pairs with XcodeBuildMCP for this — XcodeBuildMCP builds and deploys, Button Heist drives the UI. Different layers of the stack, same agent loop.
4. **Maturity.** The Button Heist is 0.0.1. mobile-mcp has ~4k stars and was featured on Anthropic's blog.

For apps you don't control, mobile-mcp or idb is the right tool. For apps you're building — where you can embed the framework and where the 2-3x efficiency gain, batching, expectations, and real device support matter — The Button Heist is worth trying.

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

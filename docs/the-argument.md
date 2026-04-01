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

Expectations say what the agent knows. Omit fields to loosen, add them to tighten:

- `"screen_changed"` — did the view controller change?
- `"layout_changed"` — were elements added or removed?
- `{"value": "5"}` — does the target element's value match exactly?
- `{"valueChanged": {}}` — did any value change at all?
- `{"valueChanged": {"newValue": "5"}}` — did any element's value change to "5"?
- `{"valueChanged": {"heistId": "counter", "oldValue": "3", "newValue": "5"}}` — did this specific element transition from "3" to "5"?

Each step in a batch can carry an expectation. If step 3 expected `{"valueChanged": {"newValue": "5"}}` but the value went to "4", the batch stops there with diagnostics at the exact point of divergence.

The Button Heist also works on physical devices. Same framework, same tools, pointed at real hardware instead of a simulator — an iPad connected to a Square Stand, for example.

## Benchmarks

Button Heist and ios-simulator-mcp (idb) tested against the same 13-task suite on April 1, 2026. Same model (Claude Sonnet 4.6), same app, same simulator. BH ran 5-8 trials per task in two configs: base and batching (74 + 78 trials). idb ran 2-4 trials per task (36 trials). Outliers from test-host issues (instant completions, stuck sessions) removed from both sides using the same filter. Full data in `.context/bh-infra/results/`.

Both tools achieve high accuracy on simple tasks. The differentiation is efficiency.

**Turns (mean per task, rounded):**

| Task | idb | BH | BH + batching |
|---|--:|--:|--:|
| **Full workflow** (11 steps) | 51 | 14 | **9** |
| **Calculator** | 23 | 4 | **4** |
| **Todo CRUD** | 24 | 9 | **7** |
| **Settings roundtrip** | 19 | 10 | **10** |
| **Notes workflow** | 27 | 12 | **10** |
| **Controls gauntlet** | 48 | 15 | **14** |
| **Scroll hunt** | 36 | 15 | **14** |
| **Bug verification** | 55 | 20 | **17** |
| **Marathon** (5 screens) | 81 (hit cap) | 71 | **62** |
| **Swipe actions** | 21 | 7 | **6** |
| **Scroll to find** | 22 | 9 | **8** |
| **Stepper increment** | 17 | 5 | **5** |
| **Search + filter** | 19 | 18 | **19** |

BH uses 2-6x fewer turns than idb on most tasks. The gap is largest on multi-step tasks where deltas compound — calculator (5.8x) and full workflow (5.7x). Settings roundtrip (1.9x) and search + filter (~1x) are the low end — simple tasks where semantic addressing has less room to help. Batching adds 10-36% reduction on tasks with sequential workflows. idb hit the 80-turn cap on all three marathon trials.

Where the architecture difference shows up most:

- **Swipe actions**: BH calls `perform_custom_action("Add to Order")` — one tool call per row. idb must compute swipe coordinates, reveal the button, re-read, then tap. **6 turns (batched) vs 21.**
- **Controls gauntlet**: Mixed controls (toggles, steppers, sliders, pickers). BH completes in 14 turns with batching. idb needs 48. Steppers and custom controls are where accessibility-first activation pays off most.
- **Marathon**: The endurance test — 5 screens, 40+ steps. BH completes reliably in ~62 batched turns. idb hit the 80-turn cap on every trial.

**What batching buys you:**

- **Full workflow**: 14 turns → 9. Tap-type-tap sequences batch naturally. 36% reduction.
- **Marathon**: 71 turns → 62. The biggest absolute savings on long tasks. 13% reduction.
- **Todo CRUD**: 9 turns → 7. Create-edit-delete sequences collapse. 22% reduction.
- **Notes workflow**: 12 turns → 10. Multi-field entry batches well. 17% reduction.

Batching saves 10-36% of turns on sequential workflows with predictable outcomes. It doesn't help on tasks where the agent needs to read the interface between steps — search + filter is actually 1 turn worse with batching. Both batching and expectations depend on running in-process: batching needs inline deltas, expectations need the framework to detect state changes without a full tree re-read.

**Why this matters beyond cost:**

At 4 turns to verify a fix in the app, checking the UI becomes a subroutine — the agent taps, reads the result, and gets back to the code. At 50 turns, it's the main event. The tool should disappear into the agent's workflow. When it does, fix-build-verify loops become practical. When it doesn't, the agent either hits the turn cap or burns through its context window before it gets back to the editor.

## The Competition

Two coordinate-based tools cover the same space: [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp) (~1.8k stars) and [mobile-mcp](https://github.com/anthropics/mobile-mcp) (~4k stars, featured on Anthropic's blog). Both are good tools — easy to install (`npx`), zero app integration, and they work with any app you can point them at.

**ios-simulator-mcp (idb)** reads the accessibility tree through Apple's `AXPTranslator`, which bridges iOS accessibility into macOS accessibility concepts. Properties without macOS equivalents — activation points, `respondsToUserInteraction`, hints, custom content, custom rotors, available actions — get dropped in translation. The Button Heist reads `UIAccessibility` objects directly inside the app process, so none of that is lost. idb achieves high accuracy on simple tasks but takes 2-6x more turns to get there. Doesn't have deltas, idle detection, accessibility actions, multi-touch, batching, or device support. Its dependency on Facebook's `idb` (archived, community-maintained) is a consideration. The detailed capability matrix and parsing deep dive are in the [ios-simulator-mcp section of competitive-landscape.md](./competitive-landscape.md#ios-simulator-mcp-joshuayoes).

**mobile-mcp** takes a different approach — coordinate-based interaction via WebDriverAgent. No accessibility parsing at all; the agent sees the screen and taps coordinates. Popular, well-maintained, easy to set up. Cannot batch actions because each tap depends on seeing the updated screen. We haven't run mobile-mcp through the benchmark suite yet.

**Where they win:**

1. **Zero integration.** Work with any app, no project changes. The Button Heist requires linking a framework into the debug build — the same pattern as Reveal or FLEX, but still a step.
2. **Easy install.** `npx` and you're running. The Button Heist currently requires building from source.
3. **App install, launch, and simulator lifecycle.** Built into both competitors. The Button Heist pairs with XcodeBuildMCP for this — XcodeBuildMCP builds and deploys, Button Heist drives the UI. Different layers of the stack, same agent loop.

For apps you don't control, mobile-mcp or idb is the right tool. For apps you're building — where you can embed the framework and where the efficiency gain, batching, expectations, and real device support matter — The Button Heist is worth trying.

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

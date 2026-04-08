# Button Heist: Benchmarks

## The Problem

AI agents need to operate iOS apps. The existing approach — read the screen's accessibility tree, compute pixel coordinates, tap at (x, y) — works on toy tasks but breaks down on real workflows. Every action requires re-reading the entire screen. Every tap requires coordinate math that varies by device. Every screen transition means starting over. The agent spends more time observing than acting, and the observation history fills the context window until the model drowns in its own notes.

## The Insight

VoiceOver users don't tap coordinates. They navigate a semantic interface: labels, values, traits, actions. "Tap the Sign In button" works on every device, every screen size, every orientation. The accessibility layer is already a stable, device-independent API for interacting with UI. Nobody was using it that way for agents.

## What Button Heist Does

Button Heist exposes the iOS accessibility layer as an MCP server. Agents interact with UI elements by identity — name, role, state — not by position. The server resolves targeting, handles activation, and reports what changed as a compact delta. The agent says what it wants ("activate the Dark button"), not how to get there ("tap at pixel 234, 456").

Three properties make this work:

**Semantic addressing.** Target elements by label, value, and traits — the same properties VoiceOver announces. No coordinate math, no screenshot parsing, no fragile pixel positions. One tool call, one element, zero ambiguity.

**Delta responses.** Every action returns exactly what changed: which elements appeared, disappeared, or updated. The agent doesn't need to re-read the entire screen after every tap. On a 50-action workflow, this eliminates 50 full-screen reads.

**Composable actions.** Because addressing is stable and deterministic, actions can be batched. Five steps in one call, each with an inline expectation that verifies the outcome. If step 3 fails, the batch stops there. Coordinate-based tools can't batch — each tap depends on reading the screen after the previous one.

## Side by Side

The difference is visible in a single action. Here's what it looks like to tap "Settings" in both tools — actual calls from the benchmark traces.

**Button Heist** — one call, semantic target, structured delta back:

```
→ activate(label: "Settings", traits: ["button"])

← appearance | activate: screen changed
  23 elements
  [0] appearance_header "Appearance" [header]
  [1] system_button "System" [button, selected]
  [2] dark_button "Dark" [button]
  [3] purple_button "Purple" [button]
  ...
```

The agent asked for "Settings" by name. The response tells it the screen changed and lists every element on the new screen with stable IDs, ready to target.

**ios-simulator-mcp** — read the full tree, compute coordinates, tap blind:

```
→ ui_describe_all(udid: "2159E2B8-...")

← [{"AXFrame":"{{0, 0}, {402, 874}}","AXLabel":"BH Demo",
    "type":"Application","role":"AXApplication",
    "children":[{"AXFrame":"{{16, 120.66}, {282, 39.66}}",
    ...hundreds of nested elements with frame geometry...
```

The agent gets a raw JSON tree with pixel coordinates for every element. It has to parse the tree, find the "Settings" button by label, extract its frame, compute the center point, then:

```
→ ui_tap(udid: "2159E2B8-...", x: 201, y: 856)

← "Tapped successfully"
```

"Tapped successfully" — but what happened? Did the setting actually change? The agent doesn't know. Compare that to what Button Heist returns for the same kind of action — tapping "Large" in the text size picker:

```
→ activate(heistId: "large_button")

← appearance | activate: elements changed
  + text_size_large_staticText "Text Size, Large"
  - text_size_medium_staticText
  ~ large_button: traits "button" → "button, selected"
  ~ medium_button: traits "button, selected" → "button"
```

The delta tells the agent exactly what happened: "Large" gained the `selected` trait, "Medium" lost it, the summary label updated from "Medium" to "Large". No ambiguity, no follow-up read needed.

ios-simulator-mcp has to call `ui_describe_all` again to learn what Button Heist already told it inline. That's two tool calls and two full tree reads for one tap. Multiply that by 50 actions and the context window difference is enormous.

## How Agents Think

The numbers tell you the tools are different. The agent reasoning tells you *why*. These are actual agent thoughts from the benchmark traces — same model (Claude Sonnet 4.6), same task, same app.

### Tapping "Dark" in Settings

Both agents need to change three settings: Color Scheme to Dark, Accent Color to Purple, Text Size to Large.

**Button Heist agent** thinks about the task:

> *"I need to activate 'Dark' button, 'Purple' button, 'Large' button, then read the current values."*

```
→ run_batch([
    activate(heistId: "dark_button"),
    activate(heistId: "purple_button"),
    activate(heistId: "large_button")
  ])
```

**ios-simulator-mcp agent** thinks about coordinates:

> *"Color Scheme: y=222.33, height=31, center y = 237.8. The row spans x=32 to x=370 (width=338). Dark is the 3rd segment at approximately x=314."*

```
→ ui_tap(x: 314, y: 237)
```

The BH agent names what it wants. The idb agent does division to figure out which third of a segmented control to tap. Both get the job done — one spends its reasoning tokens on the task, the other on arithmetic.

### Calculator: entering (344 × 289) ÷ 99

Both agents need to press 13 buttons in sequence.

**Button Heist agent** plans the sequence and sends it:

> *"Clear the display, enter 344, press multiply, enter 289, press equals, press divide, enter 99, press equals. Let me batch all these steps together."*

```
→ run_batch (13 steps)
    activate(all_clear_button)
    activate(3_button), activate(4_button), activate(4_button)
    activate(multiply_button)
    activate(2_button), activate(8_button), activate(9_button)
    activate(equals_button)
    activate(divide_button)
    activate(9_button), activate(9_button)
    activate(equals_button)
```

**ios-simulator-mcp agent** maps out a coordinate grid first:

> *"'all clear': x=39, y=420, size 72x72 → center (75, 456). '×': x=291, y=504, size 72x72 → center (327, 540). '÷': x=291, y=420 → center (327, 456). 'equals': x=318, y=756 → center (354, 792)."*

```
→ ui_tap(x: 75, y: 456)    # all clear
→ ui_tap(x: 159, y: 540)   # 3
→ ui_tap(x: 159, y: 588)   # 4
  ...one call per button
```

Same 13 buttons. BH sends them in one call by name. The idb agent computes center coordinates for each button from its frame geometry, then taps them one at a time — 13 tool calls instead of 1.

## The Numbers

Tested against [ios-simulator-mcp](https://github.com/nichochar/ios-simulator-mcp), a lightweight MCP wrapper around Meta's [idb (iOS Development Bridge)](https://github.com/facebook/idb). ios-simulator-mcp represents the coordinate-based approach that most iOS automation tools use today — read the accessibility tree for element positions, then tap by coordinate. It's well-built, minimal, and easy to set up. We chose it as the baseline because it's the most accessible entry point for agents that need to drive iOS. Same model (Claude Sonnet 4.6), same app, same tasks, same hardware.

### Standard tasks (14 UI automation tasks)

|  | Button Heist | ios-simulator-mcp |
|---|---|---|
| Wall time | 17 minutes | 36 minutes |
| Tokens | 9.2M | 22.9M |
| Tasks completed | 14/14 | 12/14 |

**2x faster, 2.5x fewer tokens, completes tasks ios-simulator-mcp can't finish.**

### At scale (T14: 50-action, 8-screen workflow)

|  | Button Heist | ios-simulator-mcp |
|---|---|---|
| Wall time | 7 minutes | Timed out at 20 minutes |
| Turns | 50 | 293 (incomplete) |
| Tokens | 2.5M | — (didn't finish) |
| Parts completed | 8/8 | 4/8 |

ios-simulator-mcp burned 293 turns — 70 taps and 60 full-screen reads — and still couldn't finish. It was mid-task when the timeout killed it. Button Heist finished the same workflow in 50 turns and 2.5M tokens.

This isn't a benchmark artifact. The gap is structural. Coordinate-based tools pay a constant per-action tax: read the full screen, find the element, compute coordinates, tap, read the full screen again. That tax is tolerable at 5 actions. At 50 actions, it's 100 full-screen reads filling the context window. At 100 actions, the model can't keep up.

Button Heist's per-action cost is near-zero: pass a name, read a delta. Turn 50 costs the same as turn 5.

### Where the gap comes from

| Task type | BH advantage | Why |
|---|---|---|
| Simple (toggle, tap) | 1.5–2x | Less overhead per action |
| Multi-step (forms, CRUD) | 3–4x | Fewer turns to verify state |
| Complex (multi-screen) | 5–10x | Deltas eliminate redundant reads |
| Scale (50+ actions) | **Cannot compare** | ios-simulator-mcp can't finish |

## Why It Matters

Agent workflows are getting longer. Today's agents fill forms and check settings. Tomorrow's will run end-to-end test suites, perform accessibility audits, and navigate unfamiliar apps exploratorily. The number of actions per session will grow from dozens to hundreds.

A tool that's 2x slower at 10 actions is 5x slower at 50 and hits a wall at 100. At some point the question shifts from "which is faster?" to "which can finish the job?"

We built Button Heist because we think the accessibility layer is the right abstraction for agent-driven UI. The benchmarks suggest that bet is paying off — especially as workflows get longer.

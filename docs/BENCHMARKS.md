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

Tested against [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp), a lightweight MCP wrapper around Meta's [idb (iOS Development Bridge)](https://github.com/facebook/idb). ios-simulator-mcp represents the coordinate-based approach that most iOS automation tools use today — read the accessibility tree for element positions, then tap by coordinate. It's well-built, minimal, and easy to set up. We chose it as the baseline because it's the most accessible entry point for agents that need to drive iOS. Same model (Claude Sonnet 4.6), same app, same tasks, same hardware.

### Full suite (16 tasks, N=3, fair prompts)

Task prompts describe *what* the agent should achieve, not *how* to use the tools. Neither agent gets mechanism-specific hints — both discover how to interact from their tool surface alone. 96 trials total.

|  | Button Heist | ios-simulator-mcp |
|---|---|---|
| Avg wall time | 134s | 235s |
| Avg turns | 14 | 43 |
| Avg cost | $0.46 | $1.42 |
| Tasks completed | 16/16 | 16/16 |

**2.4x faster, 3.1x fewer turns, 3.1x cheaper.**

### Per-task breakdown (averages over 3 trials)

| Task | BH | ios-simulator-mcp | Speedup |
|---|---|---|---|
| T9-swipe-order | 29s / 5t | 179s / 26t | **6.1x** |
| T15-todo-deep | 221s / 16t | 734s / 88t | **3.3x** |
| T10-scroll-find | 25s / 4t | 113s / 24t | **4.5x** |
| T7-bug-verify | 66s / 9t | 213s / 34t | **3.2x** |
| T12-search-filter | 26s / 5t | 79s / 16t | **3.0x** |
| T6-scroll-hunt | 69s / 10t | 201s / 41t | **2.9x** |
| T2-todo-crud | 76s / 7t | 213s / 38t | **2.8x** |
| T8-marathon | 227s / 29t | 609s / 107t | **2.7x** |
| T14-mega-workflow | 466s / 48t | 1192s / 196t | **2.6x** |
| T5-controls-gauntlet | 134s / 9t | 251s / 42t | **1.9x** |
| T0-full-workflow | 144s / 11t | 259s / 49t | **1.8x** |
| T13-menu-order | 435s / 38t | 743s / 92t | **1.7x** |
| T4-notes-workflow | 66s / 11t | 101s / 23t | **1.5x** |
| T3-settings-roundtrip | 46s / 7t | 64s / 13t | **1.4x** |
| T1-calculator | 50s / 6t | 49s / 16t | 1.0x |
| T11-increment | 55s / 5t | 40s / 12t | 0.7x |

### Less instruction, better results

An earlier benchmark round used prescriptive prompts — "increment the stepper 5 times", "use the Add to Order action." These happened to map directly to BH's tool vocabulary. We rewrote every task to describe outcomes only: "raise the stepper to 5", "add the first 3 items to the order." Neither agent gets told how to do it.

The fair prompts *widened* the gap (2.2x → 2.4x). The prescriptive instructions were actually helping the coordinate-based agent more than BH — they told both agents what to do, but the coordinate agent needed that hand-holding more because its tool surface doesn't reveal what controls can do. BH agents discover `increment`, `Mark complete`, and `Add to Order` from the accessibility interface itself.

### Where the gap comes from

| Task type | BH advantage | Why |
|---|---|---|
| Scroll + select | **4–6x** | Semantic find vs read-tree-compute-tap loops |
| Custom actions (order, complete, delete) | **3–5x** | Direct invocation vs visual menu navigation |
| Multi-screen workflows | **2–3x** | Deltas eliminate redundant tree reads |
| Simple taps | ~1x | Both approaches handle simple buttons well |
| Scale (50+ actions) | **2.6x** | Per-action overhead compounds with task length |

## Why It Matters

Agent workflows are getting longer. Today's agents fill forms and check settings. Tomorrow's will run end-to-end test suites, perform accessibility audits, and navigate unfamiliar apps exploratorily. The number of actions per session will grow from dozens to hundreds.

A tool that's 2x slower at 10 actions is 5x slower at 50 and hits a wall at 100. At some point the question shifts from "which is faster?" to "which can finish the job?"

We built Button Heist because we think the accessibility layer is the right abstraction for agent-driven UI. The benchmarks suggest that bet is paying off — especially as workflows get longer.

# The Button Heist benchmarks

## The problem

AI agents need to operate iOS apps. A common approach is to read an accessibility snapshot, compute a screen coordinate, tap that point, then read again to see what happened. That can work, but it gets expensive as workflows grow: the agent spends turns on coordinate math, repeated full-screen reads, and viewport bookkeeping instead of the product task.

## The insight

Assistive technologies do not operate an app by calculating tap points. They depend on the settled accessibility interface: labels, values, traits, state, and actions. When an app exposes that contract well, "activate the Sign In button" is a more durable instruction than "tap this coordinate."

## What The Button Heist does

The Button Heist makes the settled accessibility interface executable. Agents interact with UI elements by identity, role, state, and declared action. The runtime resolves the target, acts through the accessibility contract, waits for settlement, and reports what changed as a compact delta.

Three properties make this work:

**Contract-based addressing.** Target elements by label, identifier, value, traits, and action. Coordinates and screenshots remain available when pixels or spatial gestures are the subject, but ordinary controls can be addressed through the contract the app already exposes.

**Delta responses.** Actions return what changed: which elements appeared, disappeared, or updated. When the delta answers the next question, the agent can keep moving without a full-screen read after every action.

**Composable actions.** Heists compose declared actions with expectations. Five steps can run with inline checks that verify the outcome. If step 3 cannot satisfy the contract, the heist stops there with the receipt that explains why.

## Side by side

The difference is visible in a single action. Here's what it looks like to activate "Settings" in both tools — actual calls from the benchmark traces.

**The Button Heist** — one call, semantic target, structured delta back:

```
→ activate(label: "Settings", traits: ["button"])

← appearance | activate: screen changed
  23 elements
  [0] appearance_header "Appearance" header
  [1] system_button "System" button | selected
  [2] dark_button "Dark" button
  [3] purple_button "Purple" button
  ...
```

The agent asked for "Settings" by name. The response tells it the screen changed and lists every element on the new screen with labels, traits, and values ready for semantic targeting.

**ios-simulator-mcp** — read the full tree, compute coordinates, tap by point:

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

"Tapped successfully" confirms the event was delivered, but not what the interface became. Compare that to what The Button Heist returns for the same kind of action — tapping "Large" in the text size picker:

```
→ activate(label: "Large", traits: ["button"])

← appearance | activate: elements changed
  + text_size_large_staticText "Text Size, Large"
  - text_size_medium_staticText
  ~ large_button: traits "button" → "button, selected"
  ~ medium_button: traits "button, selected" → "button"
```

The delta names the relevant contract change: "Large" gained the `selected` trait, "Medium" lost it, and the summary label updated from "Medium" to "Large".

ios-simulator-mcp has to call `ui_describe_all` again to learn what The Button Heist already returned inline. That's two tool calls and two full tree reads for one tap. Multiply that by longer workflows and the context-window difference becomes material.

## How agents think

The numbers tell you the tools are different. The agent reasoning tells you *why*. These are actual agent thoughts from the benchmark traces — same model (Claude Sonnet 4.6), same task, same app.

### Tapping "Dark" in Settings

Both agents need to change three settings: Color Scheme to Dark, Accent Color to Purple, Text Size to Large.

**The Button Heist agent** thinks about the task:

> *"I need to activate 'Dark' button, 'Purple' button, 'Large' button, then read the current values."*

```
→ run_heist([
    activate(label: "Dark", traits: ["button"]),
    activate(label: "Purple", traits: ["button"]),
    activate(label: "Large", traits: ["button"])
  ])
```

**ios-simulator-mcp agent** thinks about coordinates:

> *"Color Scheme: y=222.33, height=31, center y = 237.8. The row spans x=32 to x=370 (width=338). Dark is the 3rd segment at approximately x=314."*

```
→ ui_tap(x: 314, y: 237)
```

The Button Heist agent names what it wants. The idb agent does division to figure out which third of a segmented control to tap. Both get the job done — one spends its reasoning tokens on the task, the other on arithmetic.

### Calculator: entering (344 × 289) ÷ 99

Both agents need to press 13 buttons in sequence.

**The Button Heist agent** plans the sequence and sends it:

> *"Clear the display, enter 344, press multiply, enter 289, press equals, press divide, enter 99, press equals. Let me send these as one typed heist."*

```
→ run_heist (13 steps)
    activate(label: "All Clear", traits: ["button"])
    activate(label: "3", traits: ["button"]), activate(label: "4", traits: ["button"]), activate(label: "4", traits: ["button"])
    activate(label: "Multiply", traits: ["button"])
    activate(label: "2", traits: ["button"]), activate(label: "8", traits: ["button"]), activate(label: "9", traits: ["button"])
    activate(label: "Equals", traits: ["button"])
    activate(label: "Divide", traits: ["button"])
    activate(label: "9", traits: ["button"]), activate(label: "9", traits: ["button"])
    activate(label: "Equals", traits: ["button"])
```

**ios-simulator-mcp agent** maps out a coordinate grid first:

> *"'all clear': x=39, y=420, size 72x72 → center (75, 456). '×': x=291, y=504, size 72x72 → center (327, 540). '÷': x=291, y=420 → center (327, 456). 'equals': x=318, y=756 → center (354, 792)."*

```
→ ui_tap(x: 75, y: 456)    # all clear
→ ui_tap(x: 159, y: 540)   # 3
→ ui_tap(x: 159, y: 588)   # 4
  ...one call per button
```

Same 13 buttons. The Button Heist sends them in one call by name. The idb agent computes center coordinates for each button from its frame geometry, then taps them one at a time — 13 tool calls instead of 1.

## The numbers

Tested against [ios-simulator-mcp](https://github.com/joshuayoes/ios-simulator-mcp), a lightweight MCP wrapper around Meta's [idb (iOS Development Bridge)](https://github.com/facebook/idb). ios-simulator-mcp represents the coordinate-based approach that most iOS automation tools use today — read the accessibility tree for element positions, then tap by coordinate. It's well-built, minimal, and easy to set up. We chose it as the baseline because it's the most accessible entry point for agents that need to drive iOS. Same model (Claude Sonnet 4.6), same app, same tasks, same hardware.

### Full suite (16 tasks, N=3, fair prompts)

Task prompts describe *what* the agent should achieve, not *how* to use the tools. Neither agent gets mechanism-specific hints — both discover how to interact from their tool surface alone. 96 trials total.

|  | The Button Heist | ios-simulator-mcp |
|---|---|---|
| Avg wall time | 134s | 235s |
| Avg turns | 14 | 43 |
| Avg cost | $0.46 | $1.42 |
| Tasks completed | 16/16 | 16/16 |

**2.4x faster, 3.1x fewer turns, 3.1x cheaper.**

### Per-task breakdown (averages over 3 trials)

| Task | The Button Heist | ios-simulator-mcp | Speedup |
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

An earlier benchmark round used prescriptive prompts — "increment the stepper 5 times", "use the Add to Order action." These happened to map directly to The Button Heist's tool vocabulary. We rewrote every task to describe outcomes only: "raise the stepper to 5", "add the first 3 items to the order." Neither agent gets told how to do it.

The fair prompts *widened* the gap (2.2x → 2.4x). The prescriptive instructions were actually helping the coordinate-based agent more than The Button Heist — they told both agents what to do, but the coordinate agent needed that hand-holding more because its tool surface doesn't reveal what controls can do. The Button Heist agents discover `increment`, `Mark complete`, and `Add to Order` from the accessibility interface itself.

### Where the gap comes from

| Task type | The Button Heist edge | Why |
|---|---|---|
| Scroll + select | **4–6x** | Semantic find vs read-tree-compute-tap loops |
| Custom actions (order, complete, delete) | **3–5x** | Direct invocation vs visual menu navigation |
| Multi-screen workflows | **2–3x** | Deltas eliminate redundant tree reads |
| Single taps | ~1x | Both approaches handle ordinary buttons well |
| Scale (50+ actions) | **2.6x** | Per-action overhead compounds with task length |

## Why it matters

Agent workflows are getting longer. Today's agents fill forms and check settings. Tomorrow's will run end-to-end test suites, perform accessibility audits, and navigate unfamiliar apps exploratorily. The number of actions per session will grow from dozens to hundreds.

A tool that's 2x slower at 10 actions is 5x slower at 50 and hits a wall at 100. At some point the question shifts from "which is faster?" to "which can finish the job?"

We built The Button Heist because we think the accessibility layer is the right abstraction for agent-driven UI. The benchmarks suggest that bet is paying off, especially as workflows get longer.

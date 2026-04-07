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

# Competitive Benchmark: iOS UI Automation MCP Servers

Three MCP servers tested against the same 13-task suite on iOS Simulator. Same model (Claude Sonnet 4.6), same app, same hardware (iPhone 16 Pro sim, iOS 26.1), 3 trials per task per config.

**The finding**: all three tools achieve high accuracy on most tasks. The differentiation is efficiency — Button Heist completes the same work in 2-3x fewer turns, 2-3x less time, and at half the cost.

## The Three Configs

- **Button Heist** — Semantic addressing. The agent says "tap Calculator" by label or identifier. The server resolves it to the right element. No coordinates, no screenshots needed for basic interaction.
- **mobile-mcp** — Coordinate-based via WebDriverAgent. The agent lists elements to get positions, then clicks at coordinates. Popular open-source project (~4k GitHub stars).
- **ios-simulator-mcp** — Coordinate-based via Meta's idb. Similar to mobile-mcp but different backing tool. Reads the accessibility tree through Apple's AXPTranslator.

Button Heist also has two advanced modes tested on a subset of tasks:

- **bh-batch** — Chain multiple actions in one call. Cuts turns roughly in half again.
- **bh-expect** — Inline assertions: the agent verifies correctness at each step without a separate interface read.

## Task Suite

| Task | What it tests | Complexity |
|------|---------------|------------|
| Multi-screen workflow | Calculator + todo + settings across screens | High — 11 steps, 2 screens |
| Sequential arithmetic | Tap digits, operators, verify display | Medium — ~15 button presses |
| Todo CRUD | Add items, complete one, filter, verify count | Medium — state mutations |
| Settings roundtrip | Change settings, navigate back, verify persistence | Medium — pickers |
| Notes workflow | Create notes, edit content, delete, verify | Medium — CRUD |
| Controls gauntlet | Toggles, steppers, sliders, pickers | High — many control types |
| Scroll and find | Scroll long list, find and select specific item | Medium — scroll + verify |
| Bug verification | Navigate, trigger condition, verify state | Medium — observation |
| Marathon | All 5 screens end-to-end | Very high — 1800s timeout |
| Swipe to order | Swipe gestures to add items from scrollable list | Medium — gestures |
| Scroll to select | Scroll to find and select a numbered item | Medium — scroll |
| Increment stepper | Navigate to controls, increment stepper 5 times | Low — repetitive |
| Search and filter | Search list, verify filtered count and selection | Low — control task |

**Scoring**: Each task has a grading function. 1 = fully correct, 0.5 = partial, 0 = wrong/incomplete, -1 = made things worse. Timeouts (600s wall clock, 1800s for marathon) score 0.

## Results

### Correctness

| Task | BH | idb | mobile-mcp |
|------|-----|-----|-----|
| Multi-screen workflow | 1.00 | 1.00 | 1.00 |
| Sequential arithmetic | 1.00 | 1.00 | ~1.00 (1) |
| Todo CRUD | 1.00 | 1.00 | 1.00 |
| Settings roundtrip | 0.67 | 1.00 | 1.00 |
| Notes workflow | 1.00 | — | 0.67 |
| Controls gauntlet | 1.00 (2) | 1.00 (2) | 0.00 (timeout) |
| Scroll and find | 0.00 (3) | — | 0.00 (3) |
| Bug verification | 1.00 (4) | 1.00 (4) | 1.00 (4) |
| Marathon | pending | pending | 0.67 |
| Swipe to order | 1.00 | 1.00 | 0.67 |
| Scroll to select | 1.00 | 1.00 | 1.00 |
| Increment stepper | 1.00 | 1.00 | 1.00 |
| Search and filter | 1.00 | 1.00 | 1.00 |

— = no data yet.

1. **Arithmetic (mobile-mcp)**: Harness bug — template variables weren't injected, agent improvised its own numbers and operated the calculator correctly. Scored 0 by the checker because there was no expected value. Agent likely correct but needs re-run to confirm.
2. **Controls gauntlet**: Originally scored -1 for all configs. The correctness checker had no expected values configured. Conversation logs show BH and idb completed the task correctly. mobile-mcp timed out.
3. **Scroll and find**: Grading function bug. Every config got "Achievement Unlocked:" but expected "Bottom Right". Stale expected value, not a tool failure.
4. **Bug verification**: Originally scored 0.5 across all configs. Every agent correctly identified that the app doesn't persist todo state across navigation. The expected answer was wrong — the agents found a real app bug.

### Efficiency (8 tasks with three-way data)

| Task | BH | idb | mobile-mcp | BH vs idb | BH vs mcp |
|------|-----|-----|-----|-----|-----|
| Multi-screen workflow | 20t / 85s / $0.38 | 49t / 188s / $0.84 | 61t / 311s / $0.99 | 2.4x | 3.0x |
| Sequential arithmetic | 16t / 52s / $0.25 | 24t / 87s / $0.39 | 20t / 95s / $0.30 | 1.5x | 1.2x |
| Todo CRUD | 14t / 52s / $0.23 | 40t / 175s / $0.63 | 43t / 210s / $0.62 | 2.9x | 3.1x |
| Settings roundtrip | 11t / 48s / $0.24 | 31t / 126s / $0.50 | 17t / 88s / $0.30 | 2.8x | 1.6x |
| Swipe to order | 7t / 33s / $0.16 | 24t / 194s / $0.60 | 80t / 648s / $2.20 | 3.4x | 11.4x |
| Scroll to select | 15t / 67s / $0.33 | 19t / 125s / $0.41 | 47t / 384s / $1.06 | 1.3x | 3.2x |
| Increment stepper | 15t / 102s / $0.32 | 27t / 235s / $0.59 | 13t / 69s / $0.22 | 1.8x | 0.9x |
| Search and filter | 15t / 107s / $0.38 | 23t / 116s / $0.37 | 19t / 95s / $0.32 | 1.5x | 0.8x |

Format: avg turns / avg wall-clock seconds / avg cost per trial. Ratio columns show turn multiplier (>1x = BH wins).

**Median ratios**: BH uses 2.1x fewer turns than idb and 2.1x fewer than mobile-mcp. Wall time: 2.3x faster vs idb, 2.8x faster vs mobile-mcp. Cost: 2.0x cheaper than both.

### Controls gauntlet (corrected data)

Originally mislabeled as a shared failure. BH and idb both complete this task; mobile-mcp times out.

| Config | Score | Avg Turns | Avg Wall(s) | Avg Cost |
|--------|-------|-----------|-------------|----------|
| BH | 1.00 | 26 | 133 | $0.54 |
| idb | 1.00 | 71 | 670 | $2.00 |
| mobile-mcp | 0.00 | — (timeout) | 601 | — |

BH completes the controls gauntlet in 2.7x fewer turns than idb. mobile-mcp can't finish within the 600s timeout.

### Where BH Doesn't Win on Efficiency

**Increment stepper**: mobile-mcp is slightly faster (69s vs 102s) and cheaper ($0.22 vs $0.32). Simple repetitive tapping is one area where semantic resolution overhead doesn't pay off.

**Search and filter**: All three are competitive. The task is simple enough that addressing strategy doesn't matter much.

### The Compounding Advantage: base → batch → expect

Each layer is only possible because the previous one exists. Coordinate-based tools cannot batch because each tap depends on seeing the screen after the previous action — without reliable addressing, actions aren't composable.

**All 5 configs on workflow tasks (turns, avg of 3 trials)**

| Task | idb | mobile-mcp | bh | bh-batch | bh-expect |
|------|-----|-----|-----|-----|-----|
| Multi-screen workflow | 49 | 61 | 25 | 10 | 10 |
| Sequential arithmetic | 24 | 20 | 15 | 5 | 5 |
| Todo CRUD | 40 | 43 | 14 | 7 | 8 |
| Settings roundtrip | 31 | 17 | 11 | 10 | 13 |

**Cost (USD, avg per trial)**

| Task | idb | mobile-mcp | bh | bh-batch | bh-expect |
|------|-----|-----|-----|-----|-----|
| Multi-screen workflow | 0.84 | 0.99 | 0.43 | 0.28 | 0.24 |
| Sequential arithmetic | 0.39 | 0.30 | 0.24 | 0.13 | 0.11 |
| Todo CRUD | 0.63 | 0.62 | 0.22 | 0.15 | 0.18 |
| Settings roundtrip | 0.50 | 0.30 | 0.21 | 0.20 | 0.23 |

**Sequential arithmetic end-to-end**

| Config | Turns | Wall(s) | Cost | Correct |
|--------|-------|---------|------|---------|
| mobile-mcp | 20 | 95 | $0.30 | ~100% (1) |
| idb | 24 | 87 | $0.39 | 100% |
| bh | 15 | 69 | $0.24 | 100% |
| bh-batch | 5 | 23 | $0.13 | 100% |
| bh-expect | 5 | 25 | $0.11 | 100% |

From idb to bh-expect: 4.7x fewer turns, 3.5x faster, 3.5x cheaper.

## Variance and Reliability

BH shows tight clustering on most tasks — identical turn counts across trials on several tasks. mobile-mcp has the highest variance: swipe-to-order ranged from 24 to 136 turns (plus one timeout), scroll-to-select from 22 to 95 turns. idb is in between — consistent but occasionally spikes.

mobile-mcp's variance is its biggest liability. When it works, it can be competitive on simple tasks. When it spirals, a single trial can consume $4 and 20 minutes.

> **Note**: BH shows suspiciously identical turn counts on some tasks (e.g. 7/7/7, 15/15/15). This could indicate deterministic execution paths from semantic addressing, or that trials weren't fully independent. A fresh 5-trial run would confirm.

## What We Can Say With Confidence

**All three tools can automate iOS UI tasks.** This is an efficiency comparison, not a capability one. On tasks with three-way data, BH and idb both achieve near-perfect accuracy.

**BH is 2-3x more efficient.** Median turn reduction of 2.1x, wall time reduction of 2.3x, cost reduction of 2.0x — consistent across simple and complex tasks.

**The efficiency advantage scales with gesture complexity.** Simple tasks (settings, increment, search): ~1-2x. Gesture-heavy tasks (controls, swipe, scroll): 3-11x.

**Batching compounds the advantage.** bh-batch cuts turns roughly in half again on top of the base semantic addressing advantage. This optimization path is unavailable to coordinate-based tools.

**mobile-mcp has the highest variance.** Four tasks had at least one timeout or spiral trial. BH and idb had zero timeouts across all runs.

## What We Cannot Say

- We don't have a complete three-way comparison. idb is missing some tasks; BH marathon is pending.
- One task is untestable until the grading function is fixed.
- Arithmetic mobile-mcp accuracy is unconfirmed — harness bug prevented proper scoring. Needs re-run with variable injection.
- These results are on a test app purpose-built for Button Heist. We don't know if they generalize to other apps, other models, or real-world task distributions.
- We cannot separate server efficiency from model fit. BH's tool interface may be inherently easier for Sonnet 4.6 to reason about. A different model might narrow or widen the gap.

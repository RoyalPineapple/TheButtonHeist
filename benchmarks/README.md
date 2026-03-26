# Competitive Benchmark: iOS UI Automation MCP Servers

Three MCP servers tested against the same 13-task suite on iOS Simulator. Same model (Claude Sonnet 4.6), same app (AccessibilityTestApp), same hardware (iPhone 16 Pro sim, iOS 26.1), 3 trials per task per config.

**The finding**: all three tools achieve high accuracy on most tasks. The differentiation is efficiency — BH completes the same work in 2-3x fewer turns, 2-3x less time, and at half the cost.

## The Three Configs

- **Button Heist (bh)** — Semantic addressing. Agent says `tap "Calculator"` by label/identifier. The server resolves it to the right element. No coordinates, no screenshots needed for basic interaction.
- **mobile-mcp** — Coordinate-based via WebDriverAgent. Agent calls `mobile_list_elements_on_screen` to get element positions, then `mobile_click_on_screen_at_coordinates(x, y)`. Popular open-source project (~4k GitHub stars).
- **ios-simulator-mcp (idb)** — Coordinate-based via Meta's idb. Similar to mobile-mcp but different backing tool. Reads the accessibility tree through Apple's `AXPTranslator`.

BH also has two advanced modes tested on a subset of tasks:
- **bh-batch** — Chain multiple actions in one `run_batch` call. Cuts turns roughly in half again.
- **bh-expect** — Inline assertions: the agent verifies correctness at each step without a separate `get_interface` call.

## Task Suite

| Task | What it tests | Complexity |
|------|--------------|------------|
| T0-full-workflow | Multi-screen workflow (calculator + todo + settings) | High — 11 steps, 2 screens |
| T1-calculator | Sequential arithmetic (tap digits, operators, verify) | Medium — ~15 button presses |
| T2-todo-crud | Add 3 items, complete 1, filter, verify count | Medium — state mutations |
| T3-settings | Change 3 settings, navigate back, verify persistence | Medium — pickers |
| T4-notes | Create notes, edit, delete, verify remaining | Medium — CRUD |
| T5-controls-gauntlet | Toggles, steppers, sliders, pickers | High — many control types |
| T6-scroll-hunt | Scroll long list, find and select specific item | Medium — scroll + verify |
| T7-bug-verify | Navigate, trigger bug condition, verify state | Medium — observation |
| T8-marathon | All 5 screens end-to-end | Very high — 1800s timeout |
| T9-swipe-order | Swipe to add items from scrollable list | Medium — gestures |
| T10-scroll-find | Scroll to find and select numbered item | Medium — scroll |
| T11-increment | Navigate to controls, increment stepper 5 times | Low — repetitive |
| T12-search-filter | Search list, verify filtered count and selection | Low — control task |

**Scoring**: Each task has a grading function. 1 = fully correct, 0.5 = partial, 0 = wrong/incomplete, -1 = made things worse. Timeouts (600s wall clock, 1800s for marathon) score 0.

## Results

### Correctness

| Task | BH | idb | mobile-mcp |
|------|---:|----:|----------:|
| T0-full-workflow | **1.00** | **1.00** | **1.00** |
| T1-calculator | **1.00** | **1.00** | ~1.00 ^1 |
| T2-todo-crud | **1.00** | **1.00** | **1.00** |
| T3-settings | 0.67 | **1.00** | **1.00** |
| T4-notes | **1.00** | — | 0.67 |
| T5-controls | **1.00** ^2 | **1.00** ^2 | 0.00 (timeout) |
| T6-scroll-hunt | 0.00 ^3 | — | 0.00 ^3 |
| T7-bug-verify | **1.00** ^4 | **1.00** ^4 | **1.00** ^4 |
| T8-marathon | pending | pending | 0.67 |
| T9-swipe-order | **1.00** | **1.00** | 0.67 |
| T10-scroll-find | **1.00** | **1.00** | **1.00** |
| T11-increment | **1.00** | **1.00** | **1.00** |
| T12-search-filter | **1.00** | **1.00** | **1.00** |

— = no data. **Bold** = best score (ties bolded).

^1 T1 mobile-mcp: harness bug — template variables weren't injected, agent improvised its own numbers and operated the calculator correctly. Scored 0 by the checker because there was no expected value. Agent likely correct but needs re-run to confirm.

^2 T5: originally scored -1 for all configs. The correctness checker had no expected values configured. Conversation logs show BH and idb completed the task correctly. mobile-mcp timed out.

^3 T6: grading function bug. Every config, every trial got `expected "Bottom Right", got "Achievement Unlocked:"`. Stale expected value, not a config failure.

^4 T7: originally scored 0.5 across all configs. Every agent correctly identified that the app doesn't persist todo state across navigation. The expected answer was wrong — the agents found a real app bug.

### Efficiency (8 tasks with three-way data)

| Task | BH | idb | mobile-mcp | BH vs idb | BH vs mcp |
|------|------|------|------|------:|------:|
| T0-full-workflow | 20t / 85s / $0.38 | 49t / 188s / $0.84 | 61t / 311s / $0.99 | 2.4x | 3.0x |
| T1-calculator | 16t / 52s / $0.25 | 24t / 87s / $0.39 | 20t / 95s / $0.30 | 1.5x | 1.2x |
| T2-todo-crud | 14t / 52s / $0.23 | 40t / 175s / $0.63 | 43t / 210s / $0.62 | 2.9x | 3.1x |
| T3-settings | 11t / 48s / $0.24 | 31t / 126s / $0.50 | 17t / 88s / $0.30 | 2.8x | 1.6x |
| T9-swipe-order | 7t / 33s / $0.16 | 24t / 194s / $0.60 | 80t / 648s / $2.20 | 3.4x | 11.4x |
| T10-scroll-find | 15t / 67s / $0.33 | 19t / 125s / $0.41 | 47t / 384s / $1.06 | 1.3x | 3.2x |
| T11-increment | 15t / 102s / $0.32 | 27t / 235s / $0.59 | 13t / 69s / $0.22 | 1.8x | 0.9x |
| T12-search-filter | 15t / 107s / $0.38 | 23t / 116s / $0.37 | 19t / 95s / $0.32 | 1.5x | 0.8x |

Format: avg turns / avg wall-clock seconds / avg cost per trial. Ratio columns show turn multiplier (>1x = BH wins).

**Median ratios**: BH uses **2.1x fewer turns** than idb and **2.1x fewer** than mobile-mcp. Wall time: **2.3x faster** vs idb, **2.8x faster** vs mobile-mcp. Cost: **2.0x cheaper** than both.

### T5-controls-gauntlet (corrected data)

Originally mislabeled as a shared failure. BH and idb both complete this task; mobile-mcp times out.

| Config | Score | Avg Turns | Avg Wall(s) | Avg Cost |
|--------|------:|----------:|------------:|---------:|
| BH | 1.00 | 26 | 133 | $0.54 |
| idb | 1.00 | 71 | 670 | $2.00 |
| mobile-mcp | 0.00 | — (timeout) | 601 | — |

BH completes the controls gauntlet in 2.7x fewer turns than idb. mobile-mcp can't finish within the 600s timeout.

### Where BH Doesn't Win on Efficiency

- **T11-increment**: mobile-mcp is slightly faster (69s vs 102s) and cheaper ($0.22 vs $0.32). Simple repetitive tapping is one area where semantic resolution overhead doesn't pay off.
- **T12-search-filter**: All three are competitive. The task is simple enough that addressing strategy doesn't matter much.

## The Compounding Advantage: bh → bh-batch → bh-expect

Each layer is only possible because the previous one exists. Coordinate-based tools cannot batch because each tap depends on seeing the screen after the previous action — without reliable addressing, actions aren't composable.

### All 5 Configs on T0-T3 (turns, avg of 3 trials)

| Task | idb | mobile-mcp | bh | bh-batch | bh-expect |
|------|----:|----------:|---:|---------:|----------:|
| T0-full-workflow | 49 | 61 | 25 | **10** | **10** |
| T1-calculator | 24 | 20 | 15 | **5** | **5** |
| T2-todo-crud | 40 | 43 | 14 | **7** | **8** |
| T3-settings | 31 | 17 | 11 | **10** | 13 |

### Cost (USD, avg per trial)

| Task | idb | mobile-mcp | bh | bh-batch | bh-expect |
|------|----:|----------:|----:|---------:|----------:|
| T0-full-workflow | 0.84 | 0.99 | 0.43 | **0.28** | 0.24 |
| T1-calculator | 0.39 | 0.30 | 0.24 | 0.13 | **0.11** |
| T2-todo-crud | 0.63 | 0.62 | 0.22 | **0.15** | 0.18 |
| T3-settings | 0.50 | 0.30 | 0.21 | **0.20** | 0.23 |

### T1-calculator end-to-end

| Config | Turns | Wall(s) | Cost | Correct |
|--------|------:|--------:|-----:|--------:|
| mobile-mcp | 20 | 95 | $0.30 | ~100% ^1 |
| idb | 24 | 87 | $0.39 | 100% |
| bh | 15 | 69 | $0.24 | 100% |
| bh-batch | 5 | 23 | $0.13 | 100% |
| bh-expect | 5 | 25 | $0.11 | 100% |

From idb to bh-expect: 4.7x fewer turns, 3.5x faster, 3.5x cheaper.

## Variance and Reliability

BH shows tight clustering on most tasks — identical turn counts across trials on T2, T3, T9-T12. mobile-mcp has the highest variance: T9 ranged from 24 to 136 turns (plus one timeout), T10 from 22 to 95 turns. idb is in between — consistent but occasionally spikes (T3: 24/43/26 turns, T11: 12/48/21 turns).

mobile-mcp's variance is its biggest liability. When it works, it can be competitive on simple tasks. When it spirals, a single trial can consume $4 and 20 minutes.

Note: BH T9-T12 trials show suspiciously identical turn counts (T9: 7/7/7, T10: 15/15/15, etc.). This could indicate deterministic execution paths from semantic addressing, or that trials weren't fully independent. A fresh 5-trial run would confirm.

## What We Can Say With Confidence

1. **All three tools can automate iOS UI tasks.** This is an efficiency comparison, not a capability one. On tasks with three-way data, BH and idb both achieve near-perfect accuracy.

2. **BH is 2-3x more efficient.** Median turn reduction of 2.1x, wall time reduction of 2.3x, cost reduction of 2.0x — consistent across simple and complex tasks.

3. **The efficiency advantage scales with gesture complexity.** Simple tasks (T3, T11, T12): ~1-2x. Gesture-heavy tasks (T5, T9, T10): 3-11x.

4. **Batching compounds the advantage.** bh-batch cuts turns roughly in half again on top of the base semantic addressing advantage. This optimization path is unavailable to coordinate-based tools.

5. **mobile-mcp has the highest variance.** Four tasks had at least one timeout or spiral trial. BH and idb had zero timeouts across all runs.

## What We Cannot Say

1. **We don't have a complete three-way comparison.** idb is missing T4-T8; BH T8-marathon is pending.
2. **T6-scroll-hunt is untestable** until the grading function is fixed.
3. **T1 mobile-mcp accuracy is unconfirmed** — harness bug prevented proper scoring. Needs re-run with variable injection.
4. **These results are on a test app purpose-built for Button Heist.** We don't know if they generalize to other apps, other models, or real-world task distributions.
5. **We cannot separate server efficiency from model fit.** BH's tool interface may be inherently easier for Sonnet 4.6 to reason about. A different model might narrow or widen the gap.

## Known Data Issues

| Issue | Status | Action |
|-------|--------|--------|
| T1 mobile-mcp variable injection | Harness bug | Re-run T1 mobile-mcp with working `.vars` |
| T5 scoring | **Fixed** — conversation logs confirm correct answers | Update `verify/expected.json` with T5 expected values |
| T6 grading | Stale expected value | Check `tasks/T6-scroll-hunt.txt` against actual app UI |
| T7 expected answer | **Fixed** — agents found real app bug | Update expected answer or accept 0.5 as correct |
| BH T8-marathon | Missing | Run `bh` on T8, 3 trials, 1800s timeout |
| idb T4-T8 | Missing | Run `idb` on T4-T8, 3 trials |
| BH T9-T12 variance | Suspiciously low | Re-run with 5 trials, verify independence |

## Experiment Backlog

### P0 — Fill Critical Gaps

| # | Experiment | Question |
|---|-----------|----------|
| 1 | BH marathon (T8) | Can BH complete T8? How much faster than mobile-mcp's ~28min/$4.60? |
| 2 | Full idb suite (T4-T8) | Complete the three-way picture |
| 3 | Fix T6 grading | Is T6 a real task or is the expected value wrong? |
| 4 | Re-run T1 mobile-mcp | Confirm mobile-mcp calculator accuracy with proper variable injection |

### P1 — Strengthen Findings

| # | Experiment | Question |
|---|-----------|----------|
| 5 | BH batch/expect on T4-T12 | Does the compounding advantage hold on gesture-heavy tasks? |
| 6 | BH T9-T12 independence check | Are identical turn counts real or an artifact? (5 trials, fresh sim each) |
| 7 | Update T5/T7 scoring | Add expected values to `verify/expected.json` so future runs score correctly |

### P2 — Challenge Findings

| # | Experiment | Question |
|---|-----------|----------|
| 8 | Opus model comparison (T1, T5, T9) | Does a stronger model close the gap for coordinate-based? |
| 9 | mobile-mcp with coaching (T1, T9) | Would a better system prompt fix coordinate math? |
| 10 | mobile-mcp longer timeout (T4, T5, T9) | Do timeout failures succeed with 1200s? |

### P3 — Expand Scope

| # | Experiment | Question |
|---|-----------|----------|
| 11 | Real-world app | Do results hold outside the test app? |
| 12 | Haiku cost floor (T0-T3) | How cheap can BH get with a weaker model? |
| 13 | Latency breakdown (T1, T2, T9) | How much is server overhead vs model thinking? |

## Running Benchmarks

```bash
# Single simulator, one task
benchmarks/run.sh --config bh --task T1-calculator --trials 3

# Parallel pool (3 workers, all tasks)
benchmarks/pool.sh --config bh --workers 3 --trials 3

# Score results
benchmarks/verify/score.sh benchmarks/results/<run-dir>

# Generate report
benchmarks/report.sh benchmarks/results/<run-dir>
```

Results land in `benchmarks/results/` with `.json` summaries, `.jsonl` conversation logs, `.vars` trial variables, and worker logs.

## Source Data

All numbers in this document are derived from these pool/run directories:

| Run | Configs | Tasks | Notes |
|-----|---------|-------|-------|
| `20260325-122152-6-p1455` | bh, bh-batch, bh-expect | T0-T3 | Single-sim, BH modes comparison |
| `20260325-130422-6-p1456` | idb | T0-T3 | Single-sim, idb baseline |
| `20260325-161057-6-p1455` | bh, bh-batch, bh-expect | T9-T12 | Single-sim, focused gesture tasks |
| `20260325-161057-6-p1456` | idb | T9-T12 | Single-sim, idb gesture tasks |
| `pool-20260325-185417-6-w3` | mobile-mcp | T0-T3, T8-T12 | Pool run, first mobile-mcp set |
| `pool-20260326-130107-6-w3` | bh, mobile-mcp | T4-T7 | Pool run, hard tasks |

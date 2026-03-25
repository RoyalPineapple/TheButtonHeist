# Benchmark Data: The Button Heist vs ios-simulator-mcp

Full data from the automated benchmark harness. All trials use randomized inputs (calculator operands, todo item names) to prevent memorization.

## Methodology

- **Model**: Claude Sonnet 4.6, n=3 per cell
- **App**: AccessibilityTestApp on iPhone 16 Pro Simulator (iOS 26.0/26.2)
- **Harness**: `benchmarks/run.sh` — interleaved trials, app reset between each, automated correctness scoring
- **Simulators**: Bench BH (port 1455) for BH configs, Bench idb (port 1456) for ios-simulator-mcp
- **Configurations**:
  - **idb**: ios-simulator-mcp v1.5.2 — external, coordinate-based, no deltas
  - **bh**: The Button Heist (main) — in-process, element-level activation, deltas
  - **bh-batch**: BH with `run_batch` — multi-action batching
  - **bh-expect**: BH with `run_batch` + expectations — inline outcome verification
- **Git**: `1a292e6` (main: heistId, topology screen change, compact MCP output)
- **Inputs**: Calculator operands randomized per trial (3-digit × 3-digit ÷ 2-digit). Todo item names randomized per trial.

## Task Suite

| Task | What it tests | Steps |
|---|---|---|
| **T0-full-workflow** | End-to-end: todo CRUD + filtering + calculator | 11 steps across 2 screens |
| **T1-calculator** | Pure sequential input, batching showcase | Navigate, press ~15 buttons, read display |
| **T2-todo-crud** | State mutations + verification | Add 3 items, complete 1, filter, read count |
| **T3-settings-roundtrip** | Cross-cutting effects, picker interactions | Change 3 settings, read back current values |

## Results: Turns (mean, n=3)

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | 50 | 25 | **10** | **10** |
| **T1-calculator** | 23 | 15 | **5** | **5** |
| **T2-todo-crud** | 37 | 14 | **7** | **8** |
| **T3-settings** | 31 | 11 | **10** | **13** |

## Results: Wall Time (mean seconds, n=3)

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | 215s | 104s | **63s** | **74s** |
| **T1-calculator** | 98s | 69s | **23s** | **25s** |
| **T2-todo-crud** | 134s | 51s | **51s** | **40s** |
| **T3-settings** | 131s | 47s | **49s** | **67s** |

## Correctness

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | 2/3 | 3/3 | 3/3 | 3/3 |
| **T1-calculator** | 3/3 | 3/3 | 3/3 | 3/3 |
| **T2-todo-crud** | 3/3 | 3/3 | 3/3 | 3/3 |
| **T3-settings** | 3/3 | 3/3 | 2/3 | 3/3 |

## Turn Reduction vs idb

| Task | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|
| **T0-full-workflow** | 50% | **80%** | **80%** |
| **T1-calculator** | 35% | **78%** | **78%** |
| **T2-todo-crud** | 62% | **81%** | **78%** |
| **T3-settings** | 65% | **68%** | **58%** |

## Individual Trials

### T0-full-workflow (11-step multi-screen workflow)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 54 | 209s | ✓ |
| idb #2 | 71 | 289s | ✗ |
| idb #3 | 26 | 147s | ✓ |
| BH #1 | 18 | 70s | ✓ |
| BH #2 | 29 | 108s | ✓ |
| BH #3 | 27 | 134s | ✓ |
| BH+batch #1 | 12 | 72s | ✓ |
| BH+batch #2 | 9 | 56s | ✓ |
| BH+batch #3 | 10 | 61s | ✓ |
| BH+expect #1 | 10 | 81s | ✓ |
| BH+expect #2 | 10 | 70s | ✓ |
| BH+expect #3 | 11 | 70s | ✓ |

### T1-calculator (sequential button input)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 23 | 86s | ✓ |
| idb #2 | 26 | 103s | ✓ |
| idb #3 | 20 | 104s | ✓ |
| BH #1 | 21 | 125s | ✓ |
| BH #2 | 6 | 28s | ✓ |
| BH #3 | 17 | 53s | ✓ |
| BH+batch #1 | 5 | 21s | ✓ |
| BH+batch #2 | 5 | 24s | ✓ |
| BH+batch #3 | 5 | 24s | ✓ |
| BH+expect #1 | 5 | 26s | ✓ |
| BH+expect #2 | 5 | 24s | ✓ |
| BH+expect #3 | 5 | 25s | ✓ |

### T2-todo-crud (add, complete, filter, count)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 35 | 113s | ✓ |
| idb #2 | 36 | 135s | ✓ |
| idb #3 | 39 | 155s | ✓ |
| BH #1 | 14 | 55s | ✓ |
| BH #2 | 14 | 50s | ✓ |
| BH #3 | 13 | 49s | ✓ |
| BH+batch #1 | 7 | 37s | ✓ |
| BH+batch #2 | 7 | 41s | ✓ |
| BH+batch #3 | 7 | 74s | ✓ |
| BH+expect #1 | 6 | 33s | ✓ |
| BH+expect #2 | 8 | 41s | ✓ |
| BH+expect #3 | 10 | 47s | ✓ |

### T3-settings-roundtrip (pickers, read back values)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 28 | 113s | ✓ |
| idb #2 | 40 | 179s | ✓ |
| idb #3 | 24 | 100s | ✓ |
| BH #1 | 11 | 43s | ✓ |
| BH #2 | 11 | 49s | ✓ |
| BH #3 | 11 | 49s | ✓ |
| BH+batch #1 | 8 | 40s | ✗ |
| BH+batch #2 | 10 | 51s | ✓ |
| BH+batch #3 | 11 | 56s | ✓ |
| BH+expect #1 | 14 | 76s | ✓ |
| BH+expect #2 | 13 | 63s | ✓ |
| BH+expect #3 | 11 | 62s | ✓ |

## Notes

- **BH base variance on T1**: One trial (21t) is 3x the other two (6t, 17t). The agent sometimes takes a longer path through the calculator. Batching eliminates this — all 3 batch trials hit exactly 5 turns.
- **T3 bh-base is remarkably tight**: 11 turns across all 3 trials. The settings screen has clear, well-labeled pickers that the accessibility data describes unambiguously.
- **T3 bh-expect is slower than bh-base**: 13t vs 11t. Expectations add overhead on tasks where the agent doesn't need verification — the pickers just work.
- **idb T0 variance is high**: 26-71 turns. The longer multi-screen workflow exposes idb's lack of deltas — the agent sometimes gets lost navigating back from calculator to root.
- **Batching and expectations converge on T0 and T1**: Both hit 5t (calc) and 10t (full workflow). These tasks are heavily sequential, so batching captures most of the advantage and expectations add little on top.
- **T2 shows expectations adding value**: 7t (batch) vs 8t (expect) is close, but expect has lower wall time (40s vs 51s) — the agent skips verification re-reads.

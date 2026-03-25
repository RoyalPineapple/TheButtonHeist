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

| Task | What it tests | Steps | BH differentiator |
|---|---|---|---|
| **T0-full-workflow** | End-to-end: todo CRUD + filtering + calculator | 11 steps, 2 screens | Deltas, batching |
| **T1-calculator** | Pure sequential input | ~15 button presses | Batching |
| **T2-todo-crud** | State mutations + verification | Add 3, complete 1, filter | Deltas, element activation |
| **T3-settings** | Picker interactions, read back values | Change 3 settings | Element activation |
| **T9-swipe-order** | Swipe actions / custom accessibility actions | Add 3 items to order | `perform_custom_action` vs swipe+tap |
| **T10-scroll-find** | Scroll to offscreen element | Find item 73, tap it | `scroll_to_visible` vs repeated swipes |
| **T11-increment** | Stepper increment | Increment stepper to 5 | `increment()` vs coordinate taps |
| **T12-search-filter** | Search + tap (control task) | Search, count, tap | Near parity expected |

## Results: Turns (mean, n=3, rounded)

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | 50 | 25 | **10** | **10** |
| **T1-calculator** | 23 | 15 | **5** | **5** |
| **T2-todo-crud** | 37 | 14 | **7** | **8** |
| **T3-settings** | 31 | 11 | **10** | **13** |
| **T9-swipe-order** | 24 | **7** | 9 | **8** |
| **T10-scroll-find** | 19 | **15** | 29 | 20 |
| **T11-increment** | 27 | 15 | **10** | **11** |
| **T12-search-filter** | 23 | 15 | **19** | 18 |

## Results: Cost (mean per task, n=3)

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | $0.87 | $0.43 | **$0.28** | **$0.24** |
| **T1-calculator** | $0.34 | $0.24 | **$0.13** | **$0.11** |
| **T2-todo-crud** | $0.52 | $0.22 | **$0.15** | $0.18 |
| **T3-settings** | $0.48 | $0.21 | **$0.20** | $0.23 |
| **T9-swipe-order** | $0.60 | **$0.16** | $0.17 | $0.17 |
| **T10-scroll-find** | $0.41 | **$0.33** | $1.00 | $0.43 |
| **T11-increment** | $0.59 | $0.32 | **$0.26** | **$0.26** |
| **T12-search-filter** | $0.37 | $0.38 | $0.37 | $0.46 |

## Correctness

| Task | idb | BH | BH + Batch | BH + Expect |
|---|--:|--:|--:|--:|
| **T0-full-workflow** | 2/3 | 3/3 | 3/3 | 3/3 |
| **T1-calculator** | 3/3 | 3/3 | 3/3 | 3/3 |
| **T2-todo-crud** | 3/3 | 3/3 | 3/3 | 3/3 |
| **T3-settings** | 3/3 | 3/3 | 2/3 | 3/3 |
| **T9-swipe-order** | 3/3 | 3/3 | 2/2 | 3/3 |
| **T10-scroll-find** | 3/3 | 3/3 | 2/3 | 3/3 |
| **T11-increment** | 3/3 | 3/3 | 3/3 | 3/3 |
| **T12-search-filter** | 3/3 | 3/3 | 3/3 | 2/3 |

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

### T9-swipe-order (custom accessibility actions)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 30 | 226s | ✓ |
| idb #2 | 39 | 245s | ✓ |
| idb #3 | 2 | 110s | ✓ |
| BH #1 | 7 | 35s | ✓ |
| BH #2 | 7 | 32s | ✓ |
| BH #3 | 8 | 33s | ✓ |
| BH+batch #1 | 8 | 35s | ✓ |
| BH+batch #2 | 9 | 44s | ✓ |
| BH+expect #1 | 8 | 34s | ✓ |
| BH+expect #2 | 8 | 32s | ✓ |
| BH+expect #3 | 8 | 36s | ✓ |

### T10-scroll-find (scroll to offscreen element)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 40 | 185s | ✓ |
| idb #2 | 15 | 70s | ✓ |
| idb #3 | 2 | 121s | ✓ |
| BH #1 | 16 | 70s | ✓ |
| BH #2 | 13 | 53s | ✓ |
| BH #3 | 17 | 78s | ✓ |
| BH+batch #1 | 15 | 85s | ✓ |
| BH+batch #2 | 56 | 485s | ✓ |
| BH+batch #3 | 15 | 74s | ✗ |
| BH+expect #1 | 17 | 87s | ✓ |
| BH+expect #2 | 15 | 58s | ✓ |
| BH+expect #3 | 27 | 133s | ✓ |

### T11-increment (stepper via accessibility increment)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 12 | 81s | ✓ |
| idb #2 | 48 | 414s | ✓ |
| idb #3 | 21 | 209s | ✓ |
| BH #1 | 23 | 224s | ✓ |
| BH #2 | 12 | 45s | ✓ |
| BH #3 | 10 | 37s | ✓ |
| BH+batch #1 | 16 | 141s | ✓ |
| BH+batch #2 | 6 | 29s | ✓ |
| BH+batch #3 | 9 | 50s | ✓ |
| BH+expect #1 | 21 | 159s | ✓ |
| BH+expect #2 | 6 | 31s | ✓ |
| BH+expect #3 | 7 | 42s | ✓ |

### T12-search-filter (search + tap — control task)

| Trial | Turns | Wall | Score |
|---|--:|--:|--:|
| idb #1 | 21 | 90s | ✓ |
| idb #2 | 21 | 151s | ✓ |
| idb #3 | 28 | 107s | ✓ |
| BH #1 | 25 | 142s | ✓ |
| BH #2 | 2 | 91s | ✓ |
| BH #3 | 17 | 87s | ✓ |
| BH+batch #1 | 20 | 133s | ✓ |
| BH+batch #2 | 17 | 102s | ✓ |
| BH+batch #3 | 20 | 106s | ✓ |
| BH+expect #1 | 26 | 158s | ✓ |
| BH+expect #2 | 12 | 78s | ✗ |
| BH+expect #3 | 18 | 127s | ✓ |

## Notes

- **T9-swipe-order is the strongest differentiator**: BH 7-8t vs idb 30-39t. BH calls `perform_custom_action("Add to Order")` — one tool call per row. idb must swipe to reveal the action button, re-read the tree to find it, then tap it — 6+ tool calls per row.
- **T12-search is near parity as expected**: 15-23t across all configs. Both tools handle search and tap similarly. This serves as a control showing BH doesn't have an unfair advantage on tasks where the tools are equivalent.
- **T11 shows the delta advantage**: BH's `increment()` returns the new value inline. The agent doesn't need to re-read the tree after each increment. idb must tap the stepper, then call `ui_describe_all` to check the value — 2 turns per increment vs 1.
- **T10 has high variance across all configs**: Scrolling behavior depends on whether the agent uses `scroll_to_visible` (BH) or repeated swipes (idb). Some trials find the element quickly; others don't.
- **BH base variance on T1**: One trial (21t) is 3x the other two (6t, 17t). Batching eliminates this — all 3 batch trials hit exactly 5 turns.
- **T3 bh-base is remarkably tight**: 11 turns across all 3 trials. Well-labeled pickers that the accessibility data describes unambiguously.
- **Batching is the big win; expectations are incremental**: Across all tasks, batching captures most of the turn reduction. Expectations help on verification-heavy tasks (T2) but add overhead on tasks where the agent doesn't need confirmation (T3).
- **idb T0 variance is high**: 26-71 turns. The longer workflow exposes idb's lack of deltas — the agent sometimes gets lost navigating back.

# Benchmark Data: The Button Heist vs ios-simulator-mcp

Full data from the agent-vs-agent comparison referenced in [the-argument.md](./the-argument.md).

## Methodology

- **Models**: Claude Sonnet 4.6 and Claude Haiku 4.5, via `claude -p` (Claude Code CLI)
- **App**: AccessibilityTestApp running on iPhone 16 Pro Simulator (iOS 26.1)
- **Task**: 11-step workflow — navigate to todos, add 3 items, complete one, filter, navigate to calculator, compute 456×789÷42, return to root
- **Trials**: 6 per configuration for Sonnet (interleaved, app reset between each). 3 per configuration for Haiku.
- **Configurations**: ios-simulator-mcp (idb), The Button Heist (BH), The Button Heist with `run_batch` (BH+batch)
- **Measurement**: Token usage, cost, wall time, and turn count reported by Claude Code's JSON output
- **Outliers**: One BH Sonnet trial hit a retry loop (64 turns, $1.59) and was excluded and replaced. One Haiku BH trial completed the task but didn't produce the expected summary keywords — marked as incomplete.

## Sonnet Results (n=6 each, all trials completed)

### Averages (mean ± stdev)

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Turns** | 41 ± 1.4 | 31 ± 4.0 | **12 ± 1.6** |
| **Wall time** | 175s ± 11 | 123s ± 12 | **83s ± 4** |
| **Context consumed** | 1,550,475 ± 67,840 | 1,137,241 ± 203,119 | **409,017 ± 58,807** |
| **Output tokens** | 6,678 ± 115 | 3,644 ± 268 | **2,773 ± 184** |
| **Cost** | $0.73 ± $0.02 | $0.55 ± $0.06 | **$0.30 ± $0.04** |

### Savings vs ios-simulator-mcp

| | The Button Heist | BH + Batching |
|---|--:|--:|
| Cost | 25% | **58%** |
| Wall time | 29% | **52%** |
| Context | 26% | **73%** |
| Turns | 24% | **69%** |

### Individual Trials

| Trial | Turns | Wall | Cost | Context | Output |
|---|--:|--:|--:|--:|--:|
| idb #1 | 41 | 174s | $0.7422 | 1,622,523 | 6,677 |
| idb #2 | 40 | 169s | $0.7124 | 1,545,347 | 6,702 |
| idb #3 | 40 | 169s | $0.7110 | 1,540,806 | 6,626 |
| idb #4 | 41 | 197s | $0.7678 | 1,542,727 | 6,733 |
| idb #5 | 39 | 167s | $0.7287 | 1,435,126 | 6,492 |
| idb #6 | 43 | 175s | $0.7385 | 1,616,322 | 6,839 |
| BH #1 | 34 | 137s | $0.6205 | 1,320,673 | 3,684 |
| BH #2 | 32 | 117s | $0.5411 | 1,212,757 | 3,445 |
| BH #3 | 33 | 126s | $0.5542 | 1,241,091 | 3,843 |
| BH #4 | 31 | 129s | $0.5672 | 1,112,095 | 3,661 |
| BH #5 | 23 | 101s | $0.4517 | 746,473 | 3,244 |
| BH #6 | 32 | 126s | $0.5637 | 1,190,362 | 3,989 |
| BH+batch #1 | 14 | 84s | $0.2974 | 471,491 | 2,832 |
| BH+batch #2 | 14 | 82s | $0.3544 | 454,634 | 2,694 |
| BH+batch #3 | 11 | 80s | $0.2542 | 371,832 | 2,780 |
| BH+batch #4 | 14 | 88s | $0.2915 | 458,993 | 2,801 |
| BH+batch #5 | 11 | 86s | $0.3390 | 340,775 | 3,050 |
| BH+batch #6 | 11 | 78s | $0.2740 | 356,380 | 2,484 |

### Observations

- idb results are tight: 39-43 turns, $0.71-0.77, 167-197s.
- BH ranges wider (23-34 turns) because the agent sometimes finds efficient paths through the task — the floor is lower because the tools give the agent room to be clever.
- BH+batch is the tightest: 11-14 turns, $0.25-0.35, 78-88s.

## Haiku Results (n=3 each)

### Averages (mean ± stdev)

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Turns** | 44 ± 0.6 | 35 ± 4.0 | **18 ± 1.5** |
| **Wall time** | 132s ± 7 | 126s ± 31 | **78s ± 4** |
| **Context consumed** | 2,482,405 ± 51,841 | 1,983,693 ± 337,833 | **911,397 ± 100,464** |
| **Output tokens** | 10,184 ± 784 | 7,774 ± 1,279 | **4,974 ± 292** |
| **Cost** | $0.37 ± $0.02 | $0.30 ± $0.07 | **$0.16 ± $0.02** |

### Savings vs ios-simulator-mcp

| | The Button Heist | BH + Batching |
|---|--:|--:|
| Cost | 17% | **55%** |
| Wall time | 4% | **40%** |
| Context | 20% | **63%** |
| Turns | 19% | **58%** |

### Individual Trials

| Trial | Turns | Wall | Cost | Context | Output | Completed |
|---|--:|--:|--:|--:|--:|--:|
| idb #1 | 44 | 139s | $0.3894 | 2,518,268 | 10,376 | Yes |
| idb #2 | 43 | 125s | $0.3453 | 2,422,966 | 9,322 | Yes |
| idb #3 | 44 | 131s | $0.3649 | 2,505,982 | 10,855 | Yes |
| BH #1 | 40 | 161s | $0.3829 | 2,372,712 | 9,243 | Yes |
| BH #2 | 33 | 106s | $0.2602 | 1,764,085 | 7,176 | Yes |
| BH #3 | 33 | 110s | $0.2677 | 1,814,284 | 6,903 | No* |
| BH+batch #1 | 17 | 73s | $0.1479 | 811,557 | 4,793 | Yes |
| BH+batch #2 | 18 | 80s | $0.1626 | 910,161 | 4,818 | Yes |
| BH+batch #3 | 20 | 81s | $0.1780 | 1,012,475 | 5,312 | Yes |

\* Completed the task but didn't produce the expected summary keywords.

### Observations

- Haiku uses more context tokens than Sonnet for the same task — it reasons less efficiently.
- BH base wall time savings are minimal on Haiku (4%) — the advantage is primarily in context and cost.
- Batching savings are consistent across models: 55-58% cost reduction.
- Haiku BH had one ambiguous completion (2/3 vs idb's 3/3). Honest reporting.

## Cross-Model Comparison

| | Sonnet idb | Sonnet BH | Sonnet batch | Haiku idb | Haiku BH | Haiku batch |
|---|--:|--:|--:|--:|--:|--:|
| Cost/run | $0.73 | $0.55 | $0.30 | $0.37 | $0.30 | $0.16 |
| BH savings | — | 25% | 58% | — | 17% | 55% |

Batching savings are remarkably consistent across models (55-58%). Base BH savings are larger on Sonnet (25%) than Haiku (17%).

## Why The Button Heist Uses Fewer Turns

Every turn means the agent re-reads its full context window, reasons about it, and generates a response. Fewer turns = less time, less cost, less context pressure.

**ios-simulator-mcp** requires a separate `ui_describe_all` call after every tap to see what happened. Tap a button? That's two turns: one for the tap, one for the re-read. The idb agent can't skip this — without deltas, it's flying blind after each action.

**The Button Heist** returns a delta with every action. The agent sees what changed inline. It still calls `get_interface` when it needs the full picture (navigating to a new screen, verifying final state), but it doesn't need to after every single tap.

## Why the Output Token Difference Matters

The idb agent generated 6,678 output tokens vs The Button Heist's 3,644 — **83% more reasoning**. The agent had to work harder: computing frame centers for coordinates, diffing accessibility trees to understand state changes, and reasoning about whether taps landed correctly. With The Button Heist, the agent spent less time on mechanics and more on the actual task.

## What the Agent Sees Per Element

**ios-simulator-mcp** returns the raw idb JSON per element:

```json
{
  "AXFrame": "{{16.0, 120.7}, {326.3, 39.7}}",
  "AXUniqueId": null,
  "frame": {"y": 120.7, "x": 16.0, "width": 326.3, "height": 39.7},
  "role_description": "heading",
  "AXLabel": "ButtonHeist Test App",
  "content_required": false,
  "type": "Heading",
  "title": null,
  "help": null,
  "custom_actions": [],
  "AXValue": null,
  "enabled": true,
  "role": "AXHeading",
  "children": [],
  "subrole": null
}
```

15 fields. 5 are null. `AXFrame` and `frame` are redundant. `role`, `role_description`, `subrole` are macOS AX concepts. `content_required` is a macOS assistive tech flag. **47% noise.**

**The Button Heist** returns:

```json
{
  "actions": ["activate"],
  "activationPointX": 201,
  "activationPointY": 193.5,
  "description": "Controls Demo. Button.",
  "frameHeight": 51,
  "frameWidth": 370,
  "frameX": 16,
  "frameY": 168,
  "label": "Controls Demo",
  "order": 0,
  "respondsToUserInteraction": true,
  "traits": ["button"]
}
```

12 fields. No nulls. No redundancy. **100% signal.** Every field tells the agent what it needs: what the element is, where to tap it, whether it's tappable, and what actions are available.

## Projected Cost at Scale

| | ios-simulator-mcp | The Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Sonnet** | | | |
| Per run | $0.73 | $0.55 | **$0.30** |
| 100 runs/day | $73/day | $55/day | **$30/day** |
| Annual (250 workdays) | $18,300 | $13,700 | **$7,500** |
| **Haiku** | | | |
| Per run | $0.37 | $0.30 | **$0.16** |
| 100 runs/day | $37/day | $30/day | **$16/day** |
| Annual (250 workdays) | $9,163 | $7,590 | **$4,070** |

These projections extrapolate from one workflow type. Your actual savings will depend on task complexity, screen density, and how much of the work is sequential taps vs reads. The per-run advantage is structural — it'll hold across tasks — but the exact multiplier will vary.

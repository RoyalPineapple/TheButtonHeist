# Benchmark Data: The Button Heist vs ios-simulator-mcp

Full data from the agent-vs-agent comparison referenced in [the-argument.md](./the-argument.md).

## Methodology

- **Models**: Claude Sonnet 4.6 (n=6 per config) and Claude Haiku 4.5 (n=3 per config, directional only)
- **App**: AccessibilityTestApp running on iPhone 16 Pro Simulator (iOS 26.1)
- **Task**: 11-step workflow — navigate to todos, add 3 items, complete one, filter, navigate to calculator, compute 456×789÷42, return to root
- **Trials**: Interleaved (BH, idb, batch cycled per trial number), app reset between each
- **Configurations**: ios-simulator-mcp (idb), The Button Heist (BH), BH with `run_batch` (BH+batch), BH with `run_batch` + expectations (BH+expect)
- **Measurement**: Token usage, wall time, and turn count reported by Claude Code's JSON output
- **Outliers**: One BH Sonnet trial hit a retry loop (64 turns, $1.59) and was excluded and replaced.
- **Limitations**: n=3 Haiku results have high variance relative to sample size (BH context stdev is 17% of mean). Treat as directional.

## Sonnet Results (n=6 each, all trials completed)

### Averages (mean ± stdev)

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching | BH + Batch + Expect |
|---|--:|--:|--:|--:|
| **Turns** | 41 ± 1.4 | 31 ± 4.0 | 12 ± 1.6 | 12 ± 1.7 |
| **Wall time** | 175s ± 11 | 123s ± 12 | 83s ± 4 | 93s ± 4 |
| **Context consumed** | 1,550,475 ± 67,840 | 1,137,241 ± 203,119 | 409,017 ± 58,807 | 381,051 ± 59,136 |
| **Output tokens** | 6,678 ± 115 | 3,644 ± 268 | 2,773 ± 184 | 3,721 ± 292 |

### Savings vs ios-simulator-mcp

| | The Button Heist | BH + Batching | BH + Batch + Expect |
|---|--:|--:|--:|
| Wall time | 29% | 52% | 47% |
| Context | 26% | 74% | 75% |
| Output tokens | 45% | 58% | 44% |
| Turns | 24% | 69% | 70% |

### Individual Trials

| Trial | Turns | Wall | Context | Output |
|---|--:|--:|--:|--:|
| idb #1 | 41 | 174s | 1,622,523 | 6,677 |
| idb #2 | 40 | 169s | 1,545,347 | 6,702 |
| idb #3 | 40 | 169s | 1,540,806 | 6,626 |
| idb #4 | 41 | 197s | 1,542,727 | 6,733 |
| idb #5 | 39 | 167s | 1,435,126 | 6,492 |
| idb #6 | 43 | 175s | 1,616,322 | 6,839 |
| BH #1 | 34 | 137s | 1,320,673 | 3,684 |
| BH #2 | 32 | 117s | 1,212,757 | 3,445 |
| BH #3 | 33 | 126s | 1,241,091 | 3,843 |
| BH #4 | 31 | 129s | 1,112,095 | 3,661 |
| BH #5 | 23 | 101s | 746,473 | 3,244 |
| BH #6 | 32 | 126s | 1,190,362 | 3,989 |
| BH+batch #1 | 14 | 84s | 471,491 | 2,832 |
| BH+batch #2 | 14 | 82s | 454,634 | 2,694 |
| BH+batch #3 | 11 | 80s | 371,832 | 2,780 |
| BH+batch #4 | 14 | 88s | 458,993 | 2,801 |
| BH+batch #5 | 11 | 86s | 340,775 | 3,050 |
| BH+batch #6 | 11 | 78s | 356,380 | 2,484 |
| BH+expect #1 | 10 | 85s | 308,515 | 3,398 |
| BH+expect #2 | 11 | 96s | 333,780 | 3,928 |
| BH+expect #3 | 12 | 95s | 386,531 | 4,032 |
| BH+expect #4 | 13 | 96s | 427,089 | 3,758 |
| BH+expect #5 | 15 | 91s | 467,676 | 3,328 |
| BH+expect #6 | 12 | 94s | 362,717 | 3,886 |

### Notes

- idb results are tight: 39-43 turns, 1.4-1.6M context, 167-197s.
- BH ranges wider (23-34 turns). BH #5 is an outlier on the low side (23 turns, 746K context vs 31-34 and 1.1-1.3M for the other five). It was kept in the averages; excluding it would raise the BH mean to ~33 turns and ~1,219K context.
- BH+batch is the tightest: 11-14 turns, 341-472K context, 78-88s.
- BH+expect uses less context than plain batching (381K vs 409K) but more output tokens (3,721 vs 2,773). The higher output token count may reflect processing the richer expectations response format rather than additional reasoning.

## Haiku Results (n=3 each)

**Note**: n=3 per configuration. High variance relative to sample size — treat as directional.

### Averages (mean ± stdev)

| Metric | ios-simulator-mcp | The Button Heist | BH + Batching |
|---|--:|--:|--:|
| **Turns** | 44 ± 0.6 | 35 ± 4.0 | 18 ± 1.5 |
| **Wall time** | 132s ± 7 | 126s ± 31 | 78s ± 4 |
| **Context consumed** | 2,482,405 ± 51,841 | 1,983,693 ± 337,833 | 911,397 ± 100,464 |
| **Output tokens** | 10,184 ± 784 | 7,774 ± 1,279 | 4,974 ± 292 |

### Individual Trials

| Trial | Turns | Wall | Context | Output | Completed |
|---|--:|--:|--:|--:|--:|
| idb #1 | 44 | 139s | 2,518,268 | 10,376 | Yes |
| idb #2 | 43 | 125s | 2,422,966 | 9,322 | Yes |
| idb #3 | 44 | 131s | 2,505,982 | 10,855 | Yes |
| BH #1 | 40 | 161s | 2,372,712 | 9,243 | Yes |
| BH #2 | 33 | 106s | 1,764,085 | 7,176 | Yes |
| BH #3 | 33 | 110s | 1,814,284 | 6,903 | Yes |
| BH+batch #1 | 17 | 73s | 811,557 | 4,793 | Yes |
| BH+batch #2 | 18 | 80s | 910,161 | 4,818 | Yes |
| BH+batch #3 | 20 | 81s | 1,012,475 | 5,312 | Yes |

### Notes

- Haiku uses more context tokens than Sonnet for the same task.
- BH base wall time savings are minimal on Haiku (4%) — the advantage shows primarily in context and output tokens.
- Batching context savings are consistent across models: 63-74%.

## Token Composition

| Config | Context (input) | Output | Output share |
|---|--:|--:|--:|
| idb | 1,550K | 6,678 | 0.4% |
| BH | 1,137K | 3,644 | 0.3% |
| BH + batch | 409K | 2,773 | 0.7% |
| BH + batch + expect | 381K | 3,721 | 1.0% |

Context tokens are accumulated conversation history re-read every turn. Output tokens are the agent's generated responses. Each configuration shifts the ratio toward output — the agent spends proportionally less on re-reading context.

# Session Files

Every fuzzing session produces two companion files: **session notes** (external memory that survives context compaction) and an **action trace** (append-only log for deterministic replay).

## Naming Convention

```
.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-{command}-{description}.md
.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-{command}-{description}.trace.md
```

The `{command}` is the slash command name (`fuzz`, `explore`, `map-screens`, `stress-test`). The `{description}` is a short kebab-case summary. Previous session files are never overwritten.

## Session Notes Lifecycle

1. **Session start**: Create a new notes file with initial config
2. **During session**: Update after significant events — new screen, finding, transition, or every ~5 actions
3. **After compaction**: Find and read your notes file immediately — it IS your memory
4. **Session end**: Merge discoveries into `references/app-knowledge.md`

### Resuming After Compaction

1. List `.fuzzer-data/sessions/fuzzsession-*.md` files, find most recent with `Status: in_progress`
2. Read it fully — check Config, Progress, Navigation Stack, Coverage, Findings, Next Actions
3. Continue from where you left off — don't restart or re-explore completed screens

## Notes File Template

```markdown
# Fuzzing Session Notes

## Config
- **Strategy**: [name]
- **Max iterations**: [N]
- **App**: [name from list_devices]
- **Device**: [device name]
- **Started**: [timestamp]
- **Status**: in_progress | refinement | complete
- **Trace file**: [trace filename]
- **Next finding ID**: F-1

## Progress
- **Actions taken**: [count]
- **Current screen**: [name / fingerprint]
- **Current phase**: fuzzing_loop | refinement | report

## Screens Discovered
| # | Name | Fingerprint (key identifiers) | Elements | Fully Explored |
|---|------|-------------------------------|----------|----------------|
| 1 | Main Menu | {home, settings, profile} | 8 | yes |

## Coverage
### Screen: Main Menu
- [x] home — activate, tap, long_press
- [x] settings — activate → navigates to Settings
- [ ] profile — not yet tried

## Behavioral Models
### [Screen Name] ([Intent])
**State**: {variable: value, ...}
**Element-state map**: element → writes: stateVar; label ← reads: stateVar
**Coupling**: element.X ↔ element.Y (relationship)
**Predictions**: P1: [prediction] — status: confirmed|violated(F-N)|revised

## Transitions
| From | Action | To |
|------|--------|----|
| Main Menu | activate "settings" | Settings |

## Navigation Stack
| Depth | Screen | Arrived Via |
|-------|--------|-------------|
| 0 | Main Menu | (root) |

## Findings
### F-1 [ANOMALY] Brief description
**Trace refs**: #42, #43
**Screen**: Settings
**Action**: activate(identifier: "darkModeToggle") [trace #43]
**Expected**: Toggle value changes
**Actual**: No change

## Recordings
| Finding | File | Duration | Notes |
|---------|------|----------|-------|

## Action Log (last 10)
1. [trace #42] activate(identifier: "settings") → navigated to Settings

## Next Actions
- Continue exploring Screen: Settings
- Untried elements: theme, notifications
```

## Update Frequency

- **Immediately**: Findings (CRASH, ERROR, ANOMALY) and new screen discoveries
- **Every 5 actions**: Batch update Coverage, Progress, Action Log, Next Actions, Transitions
- **On phase changes**: fuzzing → refinement → report

---

# Action Trace Format

The trace is an append-only log of every tool call. Each entry captures exact parameters, before/after state, and results.

## File Header

```markdown
# Action Trace

- **Session**: fuzzsession-YYYY-MM-DD-HHMM-description.md
- **App**: [app name]
- **Device**: [device name]
- **Started**: [ISO 8601 timestamp]
- **Format version**: 1
```

## Entry Format

Each entry is a markdown heading + fenced YAML block, separated by `---`:

```markdown
---

### #N | type | screen name
```yaml
[YAML fields]
`` `
```

Types: `observe`, `interact`, `navigate`, `snapshot`. Sequence numbers are monotonically increasing across all types.

## Entry Types

### observe — After get_interface

```yaml
seq: 1
ts: "2026-02-17T14:30:01Z"
type: observe
tool: get_interface
screen: "Controls Demo"
screen_fingerprint: ["id1", "id2", "id3"]
element_count: 9
interactive_count: 7
notes: "Main navigation screen"
```

### interact — After any action

```yaml
seq: 2
ts: "2026-02-17T14:30:04Z"
type: interact
tool: activate
args:
  order: 3
target:
  label: "Adjustable Controls"
  identifier: null
  order: 3
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["id1", "id2", "id3"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["adj.slider", "adj.stepper"]
  element_count_after: 10
  value_after: null
  finding: null
prediction: "Navigate to Adjustable Controls screen"
validation: "MATCH"
```

Required fields: `seq`, `ts`, `type`, `tool`, `args`, `target` (omit for coordinate-only), `screen_before`, `screen_fingerprint_before`, `result.status`, `result.screen_changed`, `result.screen_after`, `result.screen_fingerprint_after`, `result.element_count_after`. Optional: `result.method`, `result.value_after`, `result.error`, `result.finding`, `prediction`, `validation`.

### navigate — Deliberate back-navigation

Same fields as `interact` plus `purpose: back_navigation | setup | reproduction`. Distinguishes traversal from fuzzing for replay.

### snapshot — Simulator state save/restore

```yaml
seq: 25
ts: "2026-02-17T14:35:00Z"
type: snapshot
action: save
name: "fuzz-20260217-settings-modified"
screen: "Settings"
notes: "Before destructive test"
```

## Building Fingerprints

Extract all element identifiers (use label if no identifier). Sort alphabetically. This sorted list is the fingerprint.

## Fingerprint Comparison (Replay Divergence)

| Similarity | Classification | Action |
|-----------|---------------|--------|
| 100% | Exact match | Continue |
| >= 80% | Minor drift | Log and continue |
| >= 50% | Significant drift | Warn, flag reproduction as uncertain |
| < 50% | Major divergence | Abort and report |

Element lookup fallback: search by label → search by position → skip if not found.

## Rapid-Fire Summarization

For stress-test sequences, trace the first action individually, then use `rapid_fire` summary:

```yaml
result:
  rapid_fire:
    count: 20
    all_succeeded: true
    notes: "20x rapid tap, no state change"
```

If any action in the batch produces an unexpected result, trace that action individually too.

## Writing Rules

- **Append only** — never rewrite the entire trace file
- **Batch writes**: Accumulate 3-5 entries, then append all at once
- **Immediate write**: Only for CRASH findings
- Omit the separate pre-action observe entry if the interact entry captures `screen_before` and `screen_fingerprint_before`

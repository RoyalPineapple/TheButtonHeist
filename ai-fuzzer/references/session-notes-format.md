# Session Notes Format

## Contents
- [Naming Convention](#naming-convention) — file naming pattern and examples
- [How It Works](#how-it-works) — create, update, resume lifecycle
- [Resuming After Compaction](#resuming-after-compaction) — how to recover state
- [Notes File Format](#notes-file-format) — complete template with all sections
- [Action Trace File](#action-trace-file) — companion trace file for deterministic replay
- [Update Frequency](#update-frequency) — when to write notes and trace entries

---

**Long-running sessions will lose context to compaction.** To survive this, write all state to a session notes file continuously. This is your external memory.

### Naming convention

Each session gets a unique file:

```
.fuzzer-data/sessions/fuzzsession-YYYY-MM-DD-HHMM-{command}-{description}.md
```

Examples:
- `.fuzzer-data/sessions/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.md`
- `.fuzzer-data/sessions/fuzzsession-2026-02-17-1545-explore-settings-screen.md`
- `.fuzzer-data/sessions/fuzzsession-2026-02-17-1600-map-screens.md`
- `.fuzzer-data/sessions/fuzzsession-2026-02-17-1620-stress-test-all-elements.md`

The `{command}` is the slash command name (`fuzz`, `explore`, `map-screens`, `stress-test`). The `{description}` is a short kebab-case summary (strategy name, screen name, target element, etc.). Use the current date and time when creating the file.

Previous session files are kept for reference — they're never overwritten.

### How it works

1. **At session start**: Create a new notes file with initial config (strategy, app info, iteration limit)
2. **After every significant event**: Update the notes file — new screen discovered, finding recorded, navigation transition (push/pop `## Navigation Stack`), or every ~5 actions as a periodic checkpoint
3. **After compaction**: If you find yourself in a conversation with no memory of what you've done, **find and read your notes file immediately**. It contains everything you need to resume.
4. **At session end**: The notes file persists as a record of the session. **Merge discoveries into `references/app-knowledge.md`** — update coverage summary, behavioral models, findings tracker, testing gaps, and session history.

### Resuming after compaction

At the start of any command, look for session notes files in `.fuzzer-data/sessions/`:
1. **List `.fuzzer-data/sessions/fuzzsession-*.md` files** — find the most recent one with `Status: in_progress`
2. **Read it fully** — this file IS your memory. Everything you knew before compaction is here.
3. Check `## Config` for strategy and iteration limit, `## Progress` for action count and current screen
4. Check `## Navigation Stack` to know your current position in the app and how to backtrack
5. Check `## Coverage` to understand what's been tried on each screen
6. Check `## Findings` for what you've already discovered
7. Check `## Next Actions` — this is what past-you decided to do next. Follow this plan.
8. Continue from where you left off — don't restart, don't re-explore screens marked as fully explored

If no `in_progress` session is found, start a fresh one.

### Notes file format

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
| 2 | Settings | {back, theme, notifications} | 12 | no |

## Coverage
### Screen: Main Menu
- [x] home — activate, tap, long_press
- [x] settings — activate → navigates to Settings
- [ ] profile — not yet tried

### Screen: Settings
- [x] back — activate → navigates to Main Menu
- [ ] theme — not yet tried
- [ ] notifications — not yet tried

## Behavioral Models
### [Screen Name] ([Intent])
**State**: {variable: value, ...}
**Element-state map**:
- element → writes: stateVar (how)
- label ← reads: stateVar
**Coupling**: element.X ↔ element.Y (relationship)
**Predictions**:
- P1: [specific testable prediction] — status: confirmed|violated(F-N)|revised
- P2: [specific testable prediction] — status: pending

## Transitions
| From | Action | To |
|------|--------|----|
| Main Menu | activate "settings" | Settings |
| Settings | activate "back" | Main Menu |

## Navigation Stack
| Depth | Screen | Arrived Via |
|-------|--------|-------------|
| 0 | Main Menu | (root) |
| 1 | Settings | activate "settings" |

**Current screen**: Settings (depth 1)
**Back action**: activate "back" → Main Menu (known transition)

## Findings
### F-1 [ANOMALY] Toggle doesn't respond to activate
**Trace refs**: #42, #43
**Screen**: Settings
**Action**: activate(identifier: "darkModeToggle") [trace #43]
**Expected**: Toggle value changes
**Actual**: No change
**Confidence**: pending

## Recordings
| Finding | File | Duration | Size | Notes |
|---------|------|----------|------|-------|
| F-1 | .fuzzer-data/recordings/F-1-refinement.mp4 | 12.3s | 245KB | Reproduction confirmed |

## Action Log (last 10)
1. [trace #42] activate(identifier: "settings") on Main Menu → navigated to Settings
2. [trace #43] get_interface on Settings — 12 elements
3. [trace #44] activate(identifier: "theme") on Settings → navigated to Theme Picker
...

## Next Actions
- Continue exploring Screen: Settings
- Untried elements: theme, notifications, privacy
- After this screen: visit Theme Picker (discovered but unexplored)
```

### Action Trace File

Every session gets a companion **trace file** for deterministic replay. The trace captures every tool call with exact parameters, before/after state, and results — enough for another agent to replay the exact sequence.

**Naming**: Same as the session notes file but with `.trace.md` extension:
```
.fuzzer-data/sessions/fuzzsession-2026-02-17-1430-fuzz-systematic-traversal.trace.md
```

**When to write trace entries:**
- After every `get_interface` call → `observe` entry
- After every interaction (activate, tap, swipe, increment, etc.) → `interact` entry
- After every back-navigation → `navigate` entry
- After every simulator snapshot save/restore → `snapshot` entry

**How to write:** Append each entry to the end of the trace file. Never rewrite the whole file. Collect all before/after state before writing a single complete entry. See `references/trace-format.md` for the entry format, field definitions, and examples.

**Cross-references:**
- In `## Config`, include: `- **Trace file**: [trace filename]`
- In `## Findings`, include `**Trace refs**: #N, #M` with the sequence numbers of relevant actions
- In `## Action Log`, prefix entries with `[trace #N]` to link to the trace

### Update frequency

**Minimize file I/O — batch your writes.** The session notes exist for compaction survival, not per-action bookkeeping.

Write session notes:
- **Immediately**: Findings (CRASH, ERROR, ANOMALY) and new screen discoveries — these are high-value and must not be lost
- **Every 5 actions**: Batch update Coverage, Progress, Action Log, Next Actions, and Transitions
- **On phase changes**: fuzzing → refinement → report

Write trace entries:
- **Every 3-5 actions**: Accumulate entries in memory, then append them all at once to the trace file
- **Immediately**: Only for CRASH findings — write the trace before the session dies

You don't need to rewrite the entire file every time — use targeted edits to update specific sections.

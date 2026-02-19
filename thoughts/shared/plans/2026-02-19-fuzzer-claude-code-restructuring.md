# Fuzzer Claude Code Feature Restructuring

## Overview

The AI fuzzer's SKILL.md is 564 lines — over Claude Code's documented 500-line limit. Operational procedures (session notes format, navigation algorithms) crowd out the agent's identity. Four reference files are orphaned (never loaded by any command). No reference file has a table of contents despite several exceeding 100 lines. This plan restructures the fuzzer to follow Claude Code's progressive disclosure pattern: a lean SKILL.md with a routing table pointing to on-demand reference files.

## Current State Analysis

**SKILL.md (564 lines)** — 21 sections, two concerns mixed together:

| Category | Sections | Lines |
|----------|----------|-------|
| Agent identity | CRITICAL, UI Coverage, State Tracking, Crash Detection, Severity Levels, Observable Invariants, REMEMBER | ~83 |
| Operational procedures | Core Loop, Deltas, Navigation Planning (79), Session Notes (153), Finding Format, Screen Intent (48), Novelty (28), Strategy System, Exploration Heuristics (33), Back Navigation (26), Error Recovery, Reporting, Guidelines, What NOT to Do | ~481 |

The two largest sections — **Session Notes** (153 lines, lines 138–290) and **Navigation Planning** (79 lines, lines 59–137) — are pure operational procedure and prime extraction candidates.

**Reference files >100 lines without table of contents:**

| File | Lines |
|------|-------|
| `references/trace-format.md` | 436 |
| `references/interesting-values.md` | 304 |
| `references/simulator-lifecycle.md` | 297 (human-only, orphaned) |
| `references/screen-intent.md` | 269 |
| `references/action-patterns.md` | 252 (orphaned) |
| `references/examples.md` | 188 (orphaned) |
| `references/strategies/invariant-testing.md` | 160 |
| `references/simulator-snapshots.md` | 119 (human-only, orphaned) |

**Orphaned reference files** (never loaded by any command or SKILL.md):
1. `references/examples.md` — MCP response interpretation examples. Should be loaded at session start.
2. `references/action-patterns.md` — Composable interaction templates. Should be loaded when planning action batches.
3. `references/simulator-lifecycle.md` — Simulator setup commands. Human-only reference, fine as-is.
4. `references/simulator-snapshots.md` — Snapshot management. Human-only reference, fine as-is.

### Key Discoveries
- Session Notes (153 lines) is the single largest section in SKILL.md — it's a complete file format specification with templates, naming conventions, and update frequency rules
- Navigation Planning (79 lines) is a self-contained BFS algorithm with stack management and persistent graph I/O protocol
- Extracting just these two sections removes ~220 lines from SKILL.md → brings it to ~344 lines, well under 500
- The two simulator reference files are genuinely human-only (xcrun simctl commands) — they don't need agent routing

## Desired End State

- SKILL.md under 500 lines with a clear routing table near the top
- Every agent-facing reference file is discoverable from SKILL.md's routing table
- Reference files >100 lines have a table of contents at the top
- No orphaned reference files (except the two human-only simulator docs)
- Session notes format and navigation planning live in their own reference files, loaded on demand by commands

### Verification
- `wc -l ai-fuzzer/SKILL.md` reports ≤ 500
- Every reference file path in SKILL.md's routing table exists on disk
- Every non-simulator file in `references/` appears in SKILL.md's routing table
- Grep for `references/` in all commands and SKILL.md — no broken paths
- Files >100 lines start with a `## Contents` section

## What We're NOT Doing

- **Not creating subagents** — the single-context architecture works for now. Subagents would add complexity for unclear benefit.
- **Not using `.claude/rules/`** — rules files are for project-wide conventions (coding style, commit format), not skill-specific operating procedures.
- **Not migrating commands to skills directory** — commands in `.claude/commands/` work identically to skills. The directory difference is cosmetic.
- **Not adding `context: fork`** — forked execution would isolate the fuzzer from its MCP server connection. Counterproductive.
- **Not restructuring the fuzz-sessions or reports directories** — they work fine as-is.

## Implementation Approach

Extract the two largest operational sections from SKILL.md into reference files, add a routing table to make all references discoverable, add tables of contents to large reference files, and wire orphaned references into commands. Four phases, each independently verifiable.

---

## Phase 1: Extract Session Notes and Navigation Planning from SKILL.md

### Overview
Move the two largest operational sections out of SKILL.md into dedicated reference files. Replace them with brief pointers. This is the main line-count reduction.

### Changes Required:

#### 1. New file: `ai-fuzzer/references/session-notes-format.md`

Extract SKILL.md lines 138–290 (the entire `## Session Notes` section) into this new file. Keep the content exactly as-is — naming convention, how it works, resuming after compaction, notes file format template, action trace file section, cross-references, update frequency rules.

Add a table of contents at the top since it's 153 lines:

```markdown
# Session Notes Format

## Contents
- [Naming Convention](#naming-convention) — file naming pattern and examples
- [How It Works](#how-it-works) — create, update, resume lifecycle
- [Resuming After Compaction](#resuming-after-compaction) — how to recover state
- [Notes File Format](#notes-file-format) — complete template with all sections
- [Action Trace File](#action-trace-file) — companion trace file for deterministic replay
- [Update Frequency](#update-frequency) — when to write notes and trace entries

---

[... existing content from SKILL.md lines 140–289 ...]
```

#### 2. New file: `ai-fuzzer/references/navigation-planning.md`

Extract SKILL.md lines 59–137 (the entire `## Navigation Planning` section) into this new file. Keep the content exactly as-is — building the graph, finding a route (BFS), executing a route, navigation stack, persistent navigation map, when to plan routes.

Add a brief table of contents:

```markdown
# Navigation Planning

## Contents
- [Building the Graph](#building-the-graph) — how the transition table works
- [Finding a Route](#finding-a-route) — BFS route planning
- [Executing a Route](#executing-a-route) — step-by-step route execution
- [Navigation Stack](#navigation-stack) — tracking depth and backtracking
- [Persistent Navigation Map](#persistent-navigation-map) — cross-session nav-graph.md I/O
- [When to Plan Routes](#when-to-plan-routes) — when to use route planning vs. wandering

---

[... existing content from SKILL.md lines 60–137 ...]
```

#### 3. Replace extracted sections in SKILL.md with brief pointers

Replace the Session Notes section (lines 138–290) with:

```markdown
## Session Notes

Long-running sessions lose context to compaction. Write all state to a session notes file continuously — this is your external memory. Read `references/session-notes-format.md` for the complete format specification, naming conventions, file template, trace file protocol, and update frequency rules.

**Key rules** (always in memory):
- Create a new notes file at session start
- Write findings and new screens immediately
- Batch other updates every 5 actions
- After compaction: find and read your notes file — it IS your memory
```

Replace the Navigation Planning section (lines 59–137) with:

```markdown
## Navigation Planning

You accumulate a navigation graph as you explore. **Use it.** When you need to reach a specific screen, don't wander — plan a route using BFS through your `## Transitions` table.

Read `references/navigation-planning.md` for the complete algorithm: graph building, BFS route finding, route execution with verification, navigation stack management, and persistent nav-graph.md I/O protocol.

**Key rules** (always in memory):
- Check `## Transitions` for known routes before exploring
- Push to `## Navigation Stack` on every `screenChanged`
- Pop on every back-navigation
- Read `references/nav-graph.md` at session start, merge discoveries at session end
```

### Success Criteria:
- [x] `wc -l ai-fuzzer/SKILL.md` reports ≤ 500 lines (370)
- [x] `references/session-notes-format.md` exists and contains the full session notes specification
- [x] `references/navigation-planning.md` exists and contains the full navigation planning algorithm
- [x] SKILL.md still has brief session notes and navigation planning pointers with key rules
- [x] No broken `references/` paths: all files verified to exist on disk

---

## Phase 2: Add Progressive Disclosure Routing Table to SKILL.md

### Overview
Add a `## Reference Files` section near the top of SKILL.md that acts as a table of contents for all reference files. This is the "progressive disclosure" pattern — SKILL.md tells the agent what exists and when to load it, without including the content inline.

### Changes Required:

#### 1. Add `## Reference Files` section to SKILL.md

Insert after the `## CRITICAL: You are a black-box observer` section (after line 22), before `## Core Loop`:

```markdown
## Reference Files

These files contain detailed specifications loaded on demand. Don't read them all at once — load each one when you need it.

| File | When to Read | What It Contains |
|------|-------------|-----------------|
| `references/session-notes-format.md` | Session start (to create notes file) | Notes file format, naming, trace file protocol, update frequency |
| `references/navigation-planning.md` | When you need to plan a route | BFS algorithm, navigation stack, persistent nav-graph I/O |
| `references/nav-graph.md` | Session start + session end (to merge) | Cross-session navigation map with screens, transitions, back routes |
| `references/screen-intent.md` | When landing on a new screen | Screen intent categories, workflow tests, violation tests |
| `references/interesting-values.md` | When testing text fields | Context-aware value generation, value categories, mutation techniques |
| `references/action-patterns.md` | When planning action batches | Composable interaction sequences, pattern composition, mutation |
| `references/examples.md` | Session start (for response interpretation) | Annotated MCP tool response examples, intent-driven testing demos |
| `references/trace-format.md` | When writing trace entries | Trace entry format, field definitions, examples |
| `references/troubleshooting.md` | When encountering errors | Error recovery procedures |
| `references/strategies/*.md` | Session start (when strategy is specified) | Strategy-specific element selection, action ordering, anomaly focus |
```

### Success Criteria:
- [x] SKILL.md contains `## Reference Files` section with routing table
- [x] Every non-simulator file in `references/` appears in the table
- [x] Each row has a clear "when to read" trigger

---

## Phase 3: Add Tables of Contents to Large Reference Files

### Overview
Add a `## Contents` section at the top of every reference file over 100 lines that doesn't already have one (from Phase 1). This helps the agent navigate long files efficiently.

### Changes Required:

Add a `## Contents` section with anchor links to each file's major sections. The ToC should list section names with a brief (3-8 word) description of what's in each.

Files to update:

1. **`references/trace-format.md`** (436 lines) — ToC for entry types, field definitions, examples
2. **`references/interesting-values.md`** (304 lines) — ToC for context-aware generation, value categories, mutation techniques
3. **`references/screen-intent.md`** (269 lines) — ToC for each intent category + cross-screen relationships
4. **`references/action-patterns.md`** (252 lines) — ToC for each pattern + composition/mutation sections
5. **`references/examples.md`** (188 lines) — ToC for each example scenario + anti-patterns
6. **`references/strategies/invariant-testing.md`** (160 lines) — ToC for invariant categories

Skip the two human-only simulator files — they're not agent-facing.

### Success Criteria:
- [x] All 6 listed files have a `## Contents` section at the top
- [x] Each ToC entry has an anchor link and brief description
- [x] No existing content was removed or modified — ToCs are additive

---

## Phase 4: Wire Orphaned References into Commands

### Overview
`references/examples.md` and `references/action-patterns.md` are never loaded by any command. Add explicit load instructions to the commands that benefit from them.

### Changes Required:

#### 1. Wire `references/examples.md` into `/fuzz` and `/fuzz-explore`

In `ai-fuzzer/.claude/commands/fuzz.md`, add to Step 0 (alongside existing reference file reads):
```markdown
5. **Load response examples**: Read `references/examples.md` for annotated MCP tool response examples — these show how to interpret deltas and recognize screen intents in practice.
```

In `ai-fuzzer/.claude/commands/fuzz-explore.md`, add to Step 0:
```markdown
5. **Load response examples**: Read `references/examples.md` for annotated MCP response interpretation examples.
```

#### 2. Wire `references/action-patterns.md` into `/fuzz` and `/fuzz-explore`

In `ai-fuzzer/.claude/commands/fuzz.md`, add to Step 0:
```markdown
6. **Load action patterns**: Read `references/action-patterns.md` for composable interaction sequences to use when planning action batches.
```

In `ai-fuzzer/.claude/commands/fuzz-explore.md`, add to Step 0:
```markdown
6. **Load action patterns**: Read `references/action-patterns.md` for composable interaction sequences.
```

#### 3. Wire new reference files into commands

The two new files from Phase 1 need to be loaded by commands that currently rely on the SKILL.md sections:

In all 6 command files, add to Step 0 (the session setup step):
```markdown
- **Load session notes format**: Read `references/session-notes-format.md` for notes file format, naming, and update protocol.
```

In commands that do navigation (`/fuzz`, `/fuzz-explore`, `/fuzz-map-screens`, `/fuzz-reproduce`), add to Step 0:
```markdown
- **Load navigation planning**: Read `references/navigation-planning.md` for route planning algorithm and navigation stack protocol.
```

### Success Criteria:
- [x] `grep -r 'examples.md' ai-fuzzer/.claude/commands/` returns matches in fuzz.md and fuzz-explore.md
- [x] `grep -r 'action-patterns.md' ai-fuzzer/.claude/commands/` returns matches in fuzz.md and fuzz-explore.md
- [x] `grep -r 'session-notes-format.md' ai-fuzzer/.claude/commands/` returns matches in all 6 command files
- [x] `grep -r 'navigation-planning.md' ai-fuzzer/.claude/commands/` returns matches in fuzz.md, fuzz-explore.md, fuzz-map-screens.md, fuzz-reproduce.md

---

## Testing Strategy

### Automated Verification:
- `wc -l ai-fuzzer/SKILL.md` ≤ 500
- All files referenced in SKILL.md's routing table exist: `for f in $(grep 'references/' ai-fuzzer/SKILL.md | grep -oP 'references/\S+\.md'); do test -f "ai-fuzzer/$f" && echo "OK: $f" || echo "MISSING: $f"; done`
- No broken references in commands: `grep -rn 'references/' ai-fuzzer/.claude/commands/ | grep '\.md'` — spot-check all paths exist
- ToC sections present: `for f in trace-format interesting-values screen-intent action-patterns examples; do grep -l '## Contents' "ai-fuzzer/references/$f.md" && echo "OK" || echo "MISSING ToC: $f"; done`

### Manual Verification:
- Read through SKILL.md to confirm it still reads as a coherent agent persona
- Verify the extracted reference files are self-contained (no dangling "see above" references)
- Check that the routing table's "when to read" triggers make sense for each file

## References

- Research: `thoughts/shared/research/2026-02-19-fuzzer-claude-code-feature-audit.md`
- Claude Code docs: 500-line SKILL.md limit, progressive disclosure pattern, 100-line ToC threshold
- Previous plan (completed): `/Users/aodawa/.claude/plans/mellow-puzzling-pancake.md`

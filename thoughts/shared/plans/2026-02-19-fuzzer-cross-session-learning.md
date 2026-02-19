# Cross-Session Learning & Gap-Driven Planning

## Overview

Teach the fuzzer to accumulate knowledge across sessions and plan each new session based on what it hasn't tested yet. Currently `nav-graph.md` persists navigation structure, but behavioral models, coverage gaps, finding investigation status, and prediction outcomes are per-session and lost. This means session 5 can discover that Text Input was never adversarially tested — a gap that persisted invisibly across all prior sessions.

## Current State Analysis

**What persists today:**
- `references/nav-graph.md` — screens, transitions, back routes, and a freeform "Notes" section with findings and explored sub-interactions

**What is lost between sessions:**
- Behavioral models (state variables, coupling rules, confirmed/violated predictions)
- Per-screen coverage details (which elements tested, which action types tried, which untried)
- Finding investigation status (which findings have been probed, which need follow-up)
- Testing history (which strategies have been run on which screens)
- Explicitly identified gaps ("Text Input never adversarially tested", "Touch Canvas drawing untested")

**Evidence of the problem:**
- 6 sessions, ~200 actions total — yet Text Input adversarial testing never happened
- CRIT-1 (rotate gesture 50% failure) was never re-investigated after the initial stress test
- Session 1 (stress test) spent 390 actions for 1 finding; session 5 (state exploration) spent 92 actions for 7 findings — no mechanism to learn that workflow testing is higher-yield
- The full-app report (`reports/report-2026-02-19-full-app.md:318-328`) lists 7 untested areas that exist only in a human-authored report, not in any file the fuzzer reads at session start

### Key Discoveries:
- `nav-graph.md` is read at session start (`fuzz.md:30`) and merged at session end (`fuzz.md:164`) — this is the proven pattern to follow
- Session notes (`session-notes-format.md`) already have `## Behavioral Models`, `## Coverage`, and `## Findings` sections — the data exists, it just isn't merged into a persistent store
- Strategy auto-selection (`fuzz.md:46-54`) only considers element composition of the first screen — it doesn't know what prior sessions already covered
- The refinement pass (`fuzz.md:137-153`) reproduces findings but doesn't track investigation status persistently

## Desired End State

After implementation:
1. A new persistent file `references/app-knowledge.md` accumulates behavioral models, coverage summaries, finding status, and known gaps across sessions
2. Every `/fuzz` session starts with a gap analysis that identifies the highest-priority untested areas and uninvestigated findings
3. Strategy auto-selection considers prior coverage — if systematic-traversal has been run 3 times, it picks something else
4. The main loop monitors yield (findings per action) and pivots when spinning without results
5. Every confirmed finding gets tracked with investigation status — uninvestigated findings are surfaced at session start

**How to verify:** Run `/fuzz` twice. The second session should explicitly reference knowledge from the first — naming specific coverage gaps, uninvestigated findings, and untested areas — and plan its actions to fill those gaps rather than re-exploring already-covered ground.

## What We're NOT Doing

- **Not auto-merging behavioral models.** Models are per-screen hypotheses that evolve. We store the latest confirmed model per screen, not a complex merge of conflicting models.
- **Not creating a separate investigation command.** Investigation planning folds into the existing `/fuzz` flow via the gap analysis step.
- **Not adding cross-session model comparison.** If session 3's model for Settings conflicts with session 5's model, the newer one wins. No diffing.
- **Not changing the nav-graph.** It stays focused on navigation structure. The knowledge base is a separate concern.
- **Not changing report format.** Reports remain human-readable summaries. The knowledge base is the machine-readable persistent state.

## Implementation Approach

Follow the `nav-graph.md` pattern: a single markdown file that the fuzzer reads at session start and merges into at session end. The file is structured with clear tables so the fuzzer can scan it quickly without reading hundreds of lines of prose.

Three phases: (1) define the knowledge base format and SKILL.md protocol, (2) wire gap analysis into `/fuzz` session planning, (3) add yield monitoring to the main loop.

---

## Phase 1: Persistent App Knowledge Base

### Overview
Create `references/app-knowledge.md` and add the cross-session knowledge protocol to SKILL.md. This phase defines what gets persisted and when.

### Changes Required:

#### 1. New file: `references/app-knowledge.md`
**File**: `ai-fuzzer/references/app-knowledge.md`
**Purpose**: Persistent cross-session knowledge base — the fuzzer's long-term memory

Format:

```markdown
# App Knowledge Base

Persistent knowledge accumulated across fuzzing sessions. Read at session start to plan intelligently. Update at session end with new discoveries.

**Last updated**: [date]
**App**: [app name]
**Sessions contributing**: [count and list]

## Coverage Summary

Per-screen testing depth. Use this to identify where to focus next.

| Screen | Intent | Elements | Tested | Action Types Used | Strategies Run | Last Tested | Gaps |
|--------|--------|----------|--------|-------------------|----------------|-------------|------|
| Main Menu | Nav Hub | 4 | 4 (100%) | activate, tap | systematic, state-exploration, swarm | 2026-02-19 | — |
| Text Input | Form | 4 | 4 (100%) | activate, tap, type_text, long_press, pinch | swarm | 2026-02-17 | adversarial values not tested, no submit behavior tested |
| Touch Canvas | Canvas | 2 | 1 (50%) | activate, tap | map-screens | 2026-02-18 | draw_path never used, drawing gestures untested |

## Behavioral Models

Accumulated per-screen models from the most recent session that tested each screen. These are starting points — always verify against current app state.

### Settings (Settings/Preferences)
**Last validated**: 2026-02-19 (state-exploration session)
**State**: {colorScheme: "light"|"dark", accentColor: color, textSize: "default"|"large", username: string, showCompleted: bool, compactMode: bool}
**Coupling**: showCompleted → Todo List filter/empty state, colorScheme → app-wide theme, accentColor → nav bar tint, textSize → nav bar style + heading size
**Cross-screen effects**: All settings persist and apply app-wide immediately
**Confirmed predictions**: settings persist across navigation (3/3), dark mode applies to all screens, showCompleted affects Todo List filter behavior
**Open questions**: Does changing username affect any other screen?

### [Screen Name] ([Intent])
**Last validated**: [date]
**State**: {variables...}
**Coupling**: [relationships]
**Confirmed predictions**: [list]
**Open questions**: [list]

## Findings Tracker

Track every finding across all sessions with investigation status.

| ID | Severity | Screen | Summary | Found | Status | Investigation Notes |
|----|----------|--------|---------|-------|--------|---------------------|
| CRIT-1 | CRITICAL | Buttons & Actions | Rotate gesture 50% failure + unintended back nav | 2026-02-17 | open:uninvestigated | Only tested in stress-test session. Needs: reproduce on other screens, vary rotation angle, test with different elements |
| A-HIGH-1 | HIGH | Todo List | Items not persisted across navigation | 2026-02-19 | open:confirmed | Reproduced 3/3. Scoped: entire screen state ephemeral, settings DO persist. |
| A-HIGH-2 | HIGH | Toggles & Pickers | Color picker 0 accessibility elements | 2026-02-19 | open:investigated | Dedicated investigation session confirmed. Coordinate taps work but a11y tree empty. |
| A-MED-1 | MEDIUM | Todo List | Clear Completed visible when completed hidden | 2026-02-19 | open:confirmed | Reproduced 2/2. |
| A-MED-2 | MEDIUM | Disclosure & Grouping | 3 elements share same identifier | 2026-02-19 | open:confirmed | Likely root cause of A-MED-3 |
| A-MED-3 | MEDIUM | Disclosure & Grouping | Disclosed toggles completely inert | 2026-02-19 | open:uninvestigated | 4/4 attempts all noChange. Needs: test after fixing A-MED-2, test via coordinate tap at exact toggle position |
| A-LOW-1 | LOW | Todo List | "No all todos" grammatical error | 2026-02-19 | open:confirmed | String interpolation without special-casing "All" filter |
| A-LOW-2 | LOW | Text Input | Pinch fails on bioEditor | 2026-02-17 | open:uninvestigated | Single occurrence. Needs: reproduce, test pinch on other text fields |

### Status values:
- `open:uninvestigated` — found but not probed further (HIGH PRIORITY for next session)
- `open:investigating` — currently being investigated
- `open:confirmed` — reproduced and scoped, but not fixed
- `open:investigated` — fully investigated, understood, awaiting fix
- `closed:fixed` — verified fixed in a later session
- `closed:wont-fix` — intentional behavior or won't address

## Testing Gaps

Explicit list of known untested areas. The fuzzer should consult this when planning sessions.

- [ ] Text Input: adversarial values (injection, unicode edge cases, long strings) — never tested across 6 sessions
- [ ] Touch Canvas: drawing gestures (draw_path, draw_bezier) — canvas was mapped but never drawn on
- [ ] Color picker: Spectrum + Sliders tabs — coordinate-based, not reached
- [ ] Color picker: opacity slider — coordinate-based, not reached
- [ ] Adjustable Controls: stepper increment/decrement boundary testing
- [ ] Settings: adversarial username values (long strings, emoji, injection)
- [ ] Invariant testing: never run as a dedicated strategy
- [ ] Boundary testing: never run as a dedicated strategy
- [x] Todo List: CRUD lifecycle + persistence — tested 2026-02-19
- [x] Settings: cross-screen effects — verified 2026-02-19

## Session History

| Date | Strategy | Actions | Findings | Focus |
|------|----------|---------|----------|-------|
| 2026-02-17 | stress-test | ~390 | 1 (CRIT-1) | Buttons & Actions rapid gestures |
| 2026-02-17 | map-screens | ~50 | 1 (resolved) | Full app screen discovery |
| 2026-02-17 | swarm-testing | ~100 | 2 (A-LOW-2, 1 resolved) | Random action subsets across screens |
| 2026-02-18 | map-screens | ~50 | 1 (INFO-2) | Re-map after fixes |
| 2026-02-19 | state-exploration | ~92 | 7 | Todo List, Settings, cross-screen |
| 2026-02-19 | gesture-fuzzing | ~10 | 1 | Color picker investigation |
```

#### 2. Add cross-session knowledge protocol to SKILL.md
**File**: `ai-fuzzer/SKILL.md`
**Location**: After `## Navigation Planning` section (line ~88), add a new `## Cross-Session Knowledge` section

**Content to add:**

```markdown
## Cross-Session Knowledge

You accumulate app knowledge across sessions in `references/app-knowledge.md`. This is your long-term memory — behavioral models, coverage gaps, finding investigation status, and testing history.

### Reading the Knowledge Base

At session start, read `references/app-knowledge.md`. Use it to:
1. **Skip re-discovery**: If a screen's behavioral model is recorded, start from it (verify it's still accurate, don't rebuild from scratch)
2. **Target gaps**: Check `## Testing Gaps` for explicitly identified untested areas — these are high-priority targets
3. **Prioritize investigation**: Check `## Findings Tracker` for `open:uninvestigated` findings — these need follow-up probes
4. **Avoid redundancy**: Check `## Session History` to avoid running the same strategy on the same screens again
5. **Load models**: Check `## Behavioral Models` for existing models of screens you're about to test — start from the recorded model and verify/update it

### Updating the Knowledge Base

At session end, merge your session's discoveries into `references/app-knowledge.md`:
1. **Coverage Summary**: Update tested counts, action types used, strategies run, last-tested dates, and gaps for every screen you touched
2. **Behavioral Models**: For each screen where you built or refined a model, update the stored model. Newer observations replace older ones.
3. **Findings Tracker**: Add new findings with status `open:uninvestigated` or `open:confirmed`. Update investigation status for findings you probed.
4. **Testing Gaps**: Check off completed gaps. Add any new gaps you identified.
5. **Session History**: Add a row for this session.

The knowledge base should stay concise — it's a reference table, not a narrative. Use the session notes files for detailed per-session records.
```

#### 3. Add to reference routing table in SKILL.md
**File**: `ai-fuzzer/SKILL.md`
**Location**: `## Reference Files` table (line ~27)

Add a new row:

```markdown
| `references/app-knowledge.md` | Session start + session end (to merge) | Cross-session knowledge: coverage, models, findings, gaps |
```

#### 4. Add knowledge base merge to session-notes-format.md
**File**: `ai-fuzzer/references/session-notes-format.md`
**Location**: After the "How it works" section (after line ~38), add to step 4:

Update the session end description to include:

```markdown
4. **At session end**: The notes file persists as a record of the session. **Merge discoveries into `references/app-knowledge.md`** — update coverage summary, behavioral models, findings tracker, testing gaps, and session history.
```

### Success Criteria:
- [ ] `references/app-knowledge.md` exists with all 5 sections populated from existing session data
- [ ] SKILL.md has a `## Cross-Session Knowledge` section with read and update protocols
- [ ] SKILL.md reference routing table includes `app-knowledge.md`
- [ ] `session-notes-format.md` mentions knowledge base merge at session end

---

## Phase 2: Gap-Driven Session Planning

### Overview
When `/fuzz` starts, the fuzzer reads the knowledge base, identifies the highest-priority gaps, and plans the session accordingly. Strategy auto-selection considers prior coverage. Investigation queue is surfaced.

### Changes Required:

#### 1. Add gap analysis step to /fuzz command
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: After Step 0 (line ~30, after loading nav-graph), add a new sub-step

Add to Step 0, after loading nav-graph:

```markdown
10. **Load app knowledge**: Read `references/app-knowledge.md` if it exists. This gives you accumulated coverage, behavioral models, finding investigation status, and known testing gaps from prior sessions.
11. **Gap analysis**: Before choosing a strategy, identify the highest-priority work:
    - **Uninvestigated findings**: Check `## Findings Tracker` for `open:uninvestigated` entries — these need 5-10 actions of investigation each
    - **Untested areas**: Check `## Testing Gaps` for unchecked items — these are explicitly known blind spots
    - **Low-coverage screens**: Check `## Coverage Summary` for screens with < 80% element coverage or missing action types
    - **Stale screens**: Screens not tested in the last 2+ sessions may have regressed
    Print the gap analysis:
    ```
    [Gap Analysis]
    Uninvestigated findings: CRIT-1 (rotate gesture), A-MED-3 (inert toggles), A-LOW-2 (pinch on bio)
    Untested areas: Text Input adversarial values, Touch Canvas drawing, invariant testing
    Low coverage: Touch Canvas (50%), Adjustable Controls (80%)
    Session plan: Prioritize CRIT-1 investigation (5 actions), then Text Input adversarial testing, then Touch Canvas drawing
    ```
```

#### 2. Enhance strategy auto-selection
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: Strategy Auto-Selection section (lines ~44-56)

Replace the current auto-selection logic with gap-aware selection:

```markdown
### Strategy Auto-Selection

If no strategy was specified in `$ARGUMENTS`, choose based on gaps and context:

1. **Check for uninvestigated findings**: If `references/app-knowledge.md` has `open:uninvestigated` findings at CRITICAL or HIGH severity, use `state-exploration` focused on those findings' screens — investigation is highest priority.
2. **Check for untested strategies**: If `## Session History` shows that `invariant-testing` or `boundary-testing` have never been run, prefer those — they find different bug classes than traversal/exploration.
3. **Check for prior sessions**: If 3+ completed sessions exist with similar strategies, use `swarm-testing` — maximize diversity.
4. **Otherwise, use the initial observation** (after Step 2):
   - Count the interactive elements on the first screen
   - **> 3 navigation elements**: use `state-exploration`
   - **> 5 adjustable elements** or **> 2 text fields**: use `boundary-testing`
   - **< 5 total interactive elements**: use `gesture-fuzzing`
   - **Otherwise**: use `systematic-traversal`
5. Print the auto-selected strategy, reasoning, and how it connects to the gap analysis
6. Read the corresponding strategy file from `references/strategies/`
```

#### 3. Add investigation queue processing to main loop
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: Step 4 (Fuzzing Loop), at the beginning (line ~89)

Add to the beginning of Step 4:

```markdown
### 4-pre. Investigation Queue (if uninvestigated findings exist)

Before starting the main exploration loop, process uninvestigated findings from `references/app-knowledge.md`:

1. For each `open:uninvestigated` finding (highest severity first, max 3 per session):
   a. Navigate to the finding's screen using `references/nav-graph.md`
   b. Spend up to 5 actions investigating: reproduce, vary, scope, reduce, boundary (see SKILL.md `### When Predictions Fail: Investigate`)
   c. Update the finding's status in session notes:
      - Reproduced consistently → `open:confirmed`
      - Fully understood (scope + minimal trigger) → `open:investigated`
      - Cannot reproduce → note the failure, keep as `open:uninvestigated`
   d. Record investigation results in session notes and trace
2. After processing the investigation queue, continue to the main loop
3. Budget: max 15 actions total for investigation queue (3 findings x 5 actions)
```

#### 4. Add gap-targeting to screen selection
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: Step 4a, point 3 (planning actions, line ~96)

Add after the existing "If everything on this screen has been tried" bullet:

```markdown
   - When choosing the next screen, **consult `references/app-knowledge.md`**:
     - Prefer screens listed in `## Testing Gaps` with unchecked items
     - Prefer screens with lowest coverage percentage in `## Coverage Summary`
     - Prefer screens not tested by the current session's strategy
     - Use `references/nav-graph.md` to plan the route
```

### Success Criteria:
- [ ] `fuzz.md` Step 0 includes loading `app-knowledge.md` and running gap analysis
- [ ] Strategy auto-selection considers uninvestigated findings, untested strategies, and prior session count
- [ ] Main loop includes investigation queue processing before exploration
- [ ] Screen selection consults the knowledge base for gap-targeting

---

## Phase 3: Yield Monitoring and Strategy Adaptation

### Overview
During the main loop, track findings-per-action rate. If the fuzzer is spinning without results, it pivots to a different screen or approach. This prevents the 390-actions-for-1-finding pattern.

### Changes Required:

#### 1. Add yield monitoring to SKILL.md
**File**: `ai-fuzzer/SKILL.md`
**Location**: After `## Exploration Heuristics` section (around line ~367), add a new section

```markdown
## Yield Monitoring

Track your effectiveness as you explore. Not every action finds a bug, but long stretches of zero findings signal you should change approach.

### Yield Check (every 15 actions)

Every 15 actions, assess:
1. **Findings in last 15 actions**: How many anomalies, errors, or prediction violations?
2. **New coverage in last 15 actions**: How many previously-untested elements or action types?
3. **Screen staleness**: Have you been on the same screen for > 20 actions?

### When to Pivot

- **0 findings AND < 3 new coverage items in 15 actions**: This screen/approach is saturated. Move to:
  1. The highest-priority screen from `## Testing Gaps` in `references/app-knowledge.md`
  2. If no gaps listed: the screen with lowest coverage in `## Coverage Summary`
  3. If all screens are high-coverage: switch to a different action approach (e.g., from element-by-element to workflow testing, or from activate to gesture-based)

- **Same screen for 20+ actions with 0 findings**: Leave immediately. Mark screen as "saturated for current strategy" in coverage notes.

- **3+ findings on current screen**: Stay and go deeper. Increase the batch size. This is a productive vein — mine it.

### Yield in Session Notes

Track yield in `## Progress`:
```
- **Actions taken**: 45
- **Findings**: 3
- **Yield**: 1 finding per 15 actions
- **Last pivot**: action 30 (moved from Display to Text Input — Display saturated)
```
```

#### 2. Wire yield monitoring into /fuzz main loop
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: Step 4c (Record section, after line ~119), add yield check

Add after the progress update print:

```markdown
4. **Yield check** (every 15 actions): Count findings and new coverage in the last 15 actions.
   - If yield is low (0 findings, < 3 new coverage items), print:
     ```
     [Yield] Low yield on [screen] — 0 findings in 15 actions. Pivoting to [next target from gap analysis].
     ```
   - Navigate to the highest-priority untested area and continue the loop from there.
   - If yield is high (2+ findings in 15 actions), print:
     ```
     [Yield] Productive vein on [screen] — N findings in 15 actions. Continuing deep exploration.
     ```
```

#### 3. Add knowledge base merge to session end
**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Location**: Step 6 (Generate Report, line ~157), add after nav-graph merge

Add as step 5 in the report generation:

```markdown
5. **Update app knowledge base**: Merge session discoveries into `references/app-knowledge.md`:
   - Update `## Coverage Summary` for all screens touched this session
   - Update or add `## Behavioral Models` for screens where models were built/refined
   - Update `## Findings Tracker` — add new findings, update investigation status for probed findings
   - Check off completed items in `## Testing Gaps`, add any newly identified gaps
   - Add this session to `## Session History`
```

### Success Criteria:
- [ ] SKILL.md has a `## Yield Monitoring` section with yield check protocol and pivot rules
- [ ] `fuzz.md` main loop includes yield check every 15 actions with pivot behavior
- [ ] `fuzz.md` Step 6 includes knowledge base merge alongside nav-graph merge

---

## What We're NOT Doing

- **Not changing other commands** (`/fuzz-explore`, `/fuzz-stress-test`, `/fuzz-map-screens`). They can read the knowledge base for context but don't need gap-driven planning — they're targeted commands. The knowledge base merge at session end should be added to them in a follow-up if warranted.
- **Not adding complexity to the knowledge base format.** It's tables and short notes, not a database. The fuzzer should be able to scan it in one read.
- **Not tracking per-element action history across sessions.** Per-screen coverage percentage is enough granularity. Element-level history would make the file too large.
- **Not adding automated yield-based strategy switching.** The fuzzer pivots screens/approaches, but doesn't automatically switch from e.g. systematic-traversal to gesture-fuzzing mid-session. That would be confusing in session notes.

## References

- Previous behavioral modeling plan: `thoughts/shared/plans/2026-02-19-fuzzer-behavioral-modeling.md`
- Full app report with gap analysis: `ai-fuzzer/reports/report-2026-02-19-full-app.md`
- Claude Code restructuring research: `thoughts/shared/research/2026-02-19-fuzzer-claude-code-feature-audit.md`
- Nav-graph (pattern to follow): `ai-fuzzer/references/nav-graph.md`

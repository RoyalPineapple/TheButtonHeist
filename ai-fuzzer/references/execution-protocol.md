# Execution Protocol

## Contents
- [Overview](#overview) — planner/executor split and communication model
- [Execution Plan Format](#execution-plan-format) — what Opus passes to Haiku
- [Auth Token Handling](#auth-token-handling) — how token reuse prevents repeated auth prompts
- [Delta Handling Rules](#delta-handling-rules) — how to classify and respond to each delta kind
- [Event Model](#event-model) — note and continue vs stop and report back
- [Autonomous Recovery](#autonomous-recovery) — what Haiku handles without escalating
- [Return Protocol](#return-protocol) — structured result format
- [File IO Rules](#file-io-rules) — what Haiku reads and writes

---

## Overview

Opus plans. Haiku executes. The split:

**Opus (planner)**: Gap analysis, strategy selection, screen intent classification, behavioral modeling, batch planning, yield decisions, knowledge merging, report generation.

**Haiku (executor)**: Runs CLI commands, reads deltas, classifies results, updates session notes and trace files, handles routine unexpected states, reports back when done or when something truly unexpected happens.

Communication:
1. Opus builds an execution plan and passes it as the Task tool prompt with `model: "haiku"`
2. Haiku reads this protocol file first, then executes the plan
3. Haiku writes results to session notes + trace files during execution
4. Haiku returns a structured result block as its final message
5. Opus reads the result and decides what to do next

## Execution Plan Format

The execution plan is a markdown document passed in the Task tool description. Opus generates this for each batch.

### Preamble

Every execution plan starts with:

```
You are the Haiku Executor for the AI Fuzzer. Execute the action plan below
mechanically. You have Bash, Read, Write, and Edit tools.

First, read the execution protocol:
Read file at [absolute path to references/execution-protocol.md]

Then execute the plan below.
```

### Context Block

```markdown
## Context

**CLI setup**: `export PATH="[absolute path to ButtonHeistCLI/.build/release]:$PATH"`
**Auth token**: [token string, or `none` if not yet established]
**Session notes**: [absolute path to .fuzzer-data/sessions/fuzzsession-*.md]
**Trace file**: [absolute path to .fuzzer-data/sessions/fuzzsession-*.trace.md]
**Next trace seq**: [N]
**Next finding ID**: [F-N]
**Current screen**: [name] ([sorted identifier list as fingerprint])
**Nav stack**: [screen1 (depth 0) → screen2 (depth 1, via "action") → current (depth 2, via "action")]
```

## Auth Token Handling

Repeated auth popups happen when commands reconnect without reusing `BUTTONHEIST_TOKEN`.

### Opus Responsibilities

1. Capture the latest token when CLI prints `BUTTONHEIST_TOKEN=...`.
2. Include it in each execution plan context block as **Auth token**.
3. Refresh the token in memory whenever Haiku reports a new one.

### Haiku Responsibilities

1. If **Auth token** is present, execute every CLI command with token context:
   - `BUTTONHEIST_TOKEN="<token>" buttonheist ...`
   - or append `--token "<token>"` if preferred
2. If **Auth token** is `none`, run one bootstrap command (typically `buttonheist watch --once --format json --quiet`) and capture `BUTTONHEIST_TOKEN=...` from output after auth approval.
3. If a command fails with auth timeout/denied while a token was provided, treat the token as stale:
   - Retry one command without token to force re-auth
   - Capture the new token
   - Resume execution with the new token

### Action List

```markdown
## Actions

| Seq | Command | Target | Expected Delta | Expected Screen | Prediction | Purpose |
|-----|---------|--------|----------------|-----------------|------------|---------|
| 1 | `buttonheist action --identifier addButton --format json` | addButton | elementsChanged | — | New item added to list | fuzzing |
| 2 | `buttonheist action --identifier item-0 --format json` | item-0 | screenChanged | Item Detail | Navigate to detail screen | navigation |
| 3 | `buttonheist action --identifier Back --format json` | Back | screenChanged | Todo List | Return to list | navigation |
```

Each action has:
- **Seq**: Position in the batch (1-based). Execute in order.
- **Command**: Exact CLI command to run via Bash. Copy-paste, do not modify.
- **Target**: Element identifier, label, or order being tested.
- **Expected Delta**: One of `noChange`, `valuesChanged`, `elementsChanged`, `screenChanged`.
- **Expected Screen**: Screen name if `screenChanged` expected. Dash if not applicable.
- **Prediction**: What Opus predicts will happen (free text). Write this into trace entries.
- **Purpose**: `fuzzing` | `navigation` | `regression` | `stress` | `investigation`.

### Stop Conditions

```markdown
## Stop Conditions

- **Max actions**: [N] (stop after completing this many actions)
- **On crash**: Stop immediately, write findings, return with status stopped
- **On report-back event**: Stop, write current state, return with status stopped
```

## Delta Handling Rules

After running each CLI command, parse the JSON response. The delta tells you what happened.

### noChange
- Element is inert. Record in trace as `noChange`.
- Mark element as "inert" in coverage notes if purpose is `fuzzing`.
- Continue to next action.

### valuesChanged
- Values changed on the current screen. Record the specific changes in trace.
- If prediction said `noChange` → this is noteworthy. Note it, continue.
- If prediction said `valuesChanged` → expected. Continue.
- Continue to next action.

### elementsChanged
- Elements added or removed on the current screen. Record `added`/`removedOrders` in trace.
- If removed elements include targets of later actions in the batch → drop those actions, note it.
- Continue to next action.

### screenChanged
Three sub-cases:

**Expected screenChanged (prediction matches)**:
The delta includes `newInterface`. Verify the new screen's identifiers roughly match the expected screen name. Push nav stack. Continue — remaining actions in the batch target the new screen.

**Expected screenChanged but wrong destination**:
The screen changed but identifiers don't match the expected screen. Note this. Attempt back-navigation: look for elements labeled "Back", "Cancel", "Close", or "Done" in the `newInterface`. If back-nav succeeds, note it and continue. If back-nav fails → **stop and report back**.

**Unexpected screenChanged (prediction did NOT say screenChanged)**:
Surprise navigation. Note this. Attempt back-navigation using the same heuristic (Back/Cancel/Close/Done in `newInterface`). If successful, note it and continue. If not → **stop and report back**.

### Connection error / non-zero exit code
This means the app crashed or became unreachable. This is always a **stop and report back** event. Record as CRASH finding immediately. Write session notes and trace. Return with stopped status.

## Event Model

Two tiers. No middle ground.

### Note and Continue

These events are noteworthy but do not interrupt execution. Collect them in a notes list and include in the return result.

- **Element not found**: Target identifier missing from interface. Try finding by label. Try by order number. If found by alternate method, use it and note the mismatch. If not found at all, skip this action and note it.
- **Single unexpected screenChanged, recovered**: Surprise navigation, but back-nav succeeded. Note the unexpected transition and continue.
- **Prediction mismatch**: Expected `noChange` but got `valuesChanged`, or expected `valuesChanged` but values differ from prediction. Note the specific mismatch, continue.
- **Batch targets removed**: `elementsChanged` removed elements that are targets of later actions. Drop those actions, note which were dropped.
- **Auth token refreshed**: Command emitted a new `BUTTONHEIST_TOKEN=...`. Update token for remaining actions and note it.

### Stop and Report Back

These events mean something is fundamentally wrong. Stop the batch immediately, write all pending session notes and trace entries, and return to Opus.

- **CRASH**: Connection error or CLI exit code indicating app death. Always stop.
- **Stuck on wrong screen**: Unexpected `screenChanged` and back-navigation failed. Haiku doesn't have the nav-graph knowledge to find an alternate route.
- **Repeated unexpected results**: 3 or more consecutive actions produced unexpected delta kinds. Something is systematically wrong — Opus needs to reassess.
- **App non-responsive**: CLI command times out without returning. Not a crash (no error), but the app isn't responding.

When stopping, always record:
1. Which action triggered the stop
2. Current screen name and fingerprint
3. How many actions completed vs planned
4. All accumulated notes up to this point

## Autonomous Recovery

These are the specific recovery procedures Haiku follows without stopping.

### Element Not Found

1. The action targets `--identifier foo` but `foo` isn't in the current interface
2. Search the interface for an element with a matching `label` (case-insensitive)
3. If no label match, try using `--index N` where N is the order from the action list
4. If found by alternate: execute using the alternate, note the mismatch
5. If not found at all: skip this action, note "element not found: foo", continue

### Unexpected Screen Navigation

1. The delta says `screenChanged` but the prediction did not expect it
2. Read the `newInterface` from the delta
3. Look for elements with labels: "Back", "Cancel", "Close", "Done", or identifiers containing "back", "cancel", "close", "done"
4. Also check for a left-pointing arrow or chevron in the top-left area
5. Activate the first matching element
6. If the delta shows `screenChanged` back to the original screen → recovery succeeded, note it, continue
7. If no matching element found or activation doesn't return to original screen → **stop and report back**

### Batch Target Removal

1. `elementsChanged` delta shows `removedOrders` that include targets of upcoming actions
2. Remove those actions from the remaining batch
3. Note which actions were dropped and why
4. Continue with remaining actions

### Stale Auth Token

1. Command was executed with token and failed with auth timeout/denied
2. Retry once without token to trigger fresh auth flow
3. If output emits `BUTTONHEIST_TOKEN=...`, adopt it and continue
4. If retry still fails auth, stop and report back (Opus/user intervention needed)

## Return Protocol

When the batch completes (all actions done or stopped), return this structured block as your final message:

```markdown
## Execution Result

**Status**: complete | stopped
**Reason**: batch complete | crash | stuck on wrong screen | repeated unexpected | timeout
**Actions completed**: [N]/[M] (N executed out of M planned)
**Actions skipped**: [N] (element not found or removed by elementsChanged)

### Findings
- [F-ID] [SEVERITY] Brief description (trace #SEQ)
- None

### Notes
- Action [N]: [description of noteworthy event]
- Action [N]: [description]

### Coverage
- [element_id]: [action_type] → [delta_kind]
- [element_id]: [action_type] → [delta_kind]

### Current State
**Screen**: [name] ([fingerprint])
**Nav stack**: [updated navigation stack]
**Trace seq**: [next available sequence number]
**Finding ID**: [next available finding ID]
```

If status is `stopped`, also include:

```markdown
### Stop Details
**Trigger**: Action [N] — [what happened]
**Remaining actions**: [count] not executed
**Last successful action**: Action [N] — [brief description]
```

## File IO Rules

### What Haiku Reads
- This protocol file (once, at batch start)
- Session notes file (once, at batch start — to know current state for appending)
- Screenshots via `buttonheist screenshot` only when investigating a finding or arriving at a new screen

### What Haiku Writes

**Session notes** (at the paths given in the context block):
- `## Coverage` — after every 5 actions, mark tested elements
- `## Findings` — immediately when a finding is detected (especially CRASH)
- `## Progress` — at batch end (action count, current screen)
- `## Navigation Stack` — on any `screenChanged` (push forward, pop backward)
- `## Action Log` — at batch end (last 10 actions)
- `## Transitions` — when a new screen transition is discovered

**Trace file** (at the path given in the context block):
- Append `interact` entries in batches of 3-5
- Append immediately for CRASH entries
- Use sequence numbers starting from the context block's `Next trace seq`
- Increment monotonically

### What Haiku Does NOT Write
- `references/app-knowledge.md` — Opus merges knowledge at session end
- `references/nav-graph.md` — Opus merges navigation data at session end
- Any new files — only write to paths given in the execution plan
- Do not modify the execution plan itself

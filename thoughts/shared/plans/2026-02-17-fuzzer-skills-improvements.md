# AI Fuzzer Skills Guide Improvements — Implementation Plan

## Overview

Convert the AI fuzzer from a CLAUDE.md + slash commands setup to proper Skills format, fix broken permissions, trim token waste, and add troubleshooting, examples, and smarter fuzz logic. Based on evaluation against "The Complete Guide to Building Skills for Claude."

## Current State Analysis

The fuzzer lives in `ai-fuzzer/` with 1,085 lines across 13 files:
- `CLAUDE.md` (165 lines) — always loaded, contains 38 lines of duplicate tool docs
- `.claude/commands/*.md` (5 files, 619 lines) — slash commands with YAML frontmatter
- `strategies/*.md` (4 files, 301 lines) — loaded on demand by `/fuzz`
- `.claude/settings.local.json` — has wrong tool names (`get_screenshot`/`get_snapshot` instead of `get_screen`/`get_interface`), blocking autonomous operation
- `.mcp.json` — MCP server config

### Key Discoveries:
- `CLAUDE.md:7-44` duplicates tool descriptions already provided by the MCP server's tool list
- `.claude/settings.local.json:3-5` has stale tool names — permissions are no-ops
- Commands jump into observation without verifying MCP connectivity first
- No error recovery guidance for known failure modes (empty interface, timeouts)
- No concrete examples of what MCP tool responses look like
- `/fuzz` runs one pass without adapting based on findings

## Desired End State

- `SKILL.md` replaces `CLAUDE.md` with proper YAML frontmatter and trimmed body (~90 lines vs 165)
- `references/` directory holds progressive-disclosure content (troubleshooting, examples, strategies)
- All 17 MCP tools auto-allowed in permissions
- Every command verifies device connectivity before starting
- Fuzzer handles recoverable errors gracefully
- `/fuzz` adapts strategy based on app characteristics and refines findings

### Verification:
- `CLAUDE.md` no longer exists
- `SKILL.md` exists with `name` and `description` in YAML frontmatter
- `references/troubleshooting.md`, `references/examples.md` exist
- `references/strategies/*.md` exist (moved from `strategies/`)
- `strategies/` directory no longer exists
- `.claude/settings.local.json` lists all 17 correct tool names
- All 5 commands reference `references/strategies/` not `strategies/`
- All 5 commands have a device verification step before observation

## What We're NOT Doing

- Creating `scripts/` or `assets/` directories (no need yet)
- Persisting fuzzer state across sessions
- Auto-composing multiple strategies in sequence
- Changing the MCP server or InsideMan code
- Modifying `README.md` (can update separately if needed)

## Implementation Approach

Three phases: (1) structural conversion to Skills format, (2) fix settings and harden commands, (3) improve fuzz intelligence. Each phase is independently verifiable.

---

## Phase 1: Convert to Skills Format

### Overview
Replace `CLAUDE.md` with `SKILL.md`, create `references/` directory with progressive disclosure content, move strategies under references.

### Changes Required:

#### 1. Create `ai-fuzzer/SKILL.md`

**File**: `ai-fuzzer/SKILL.md` (new)
**Source**: Derived from `ai-fuzzer/CLAUDE.md` with these changes:
- Add YAML frontmatter with `name` and `description`
- Remove "Your Tools" section (lines 7-44) — MCP server provides tool descriptions
- Remove "Targeting Elements" section (lines 39-44) — this is tool-usage detail the agent learns from MCP tool definitions
- Keep: Core Loop, State Tracking, Screen Identification, Crash Detection, Finding Severity Levels, Finding Format, Strategy System (update path to `references/strategies/`), Exploration Heuristics, Back Navigation, Reporting, Important Rules
- Add: Troubleshooting reference (`Read references/troubleshooting.md when encountering errors`)
- Add: Examples reference (`Read references/examples.md for tool response formats`)

```yaml
---
name: iOS App Fuzzer
description: >
  Autonomous iOS app fuzzer using ButtonHeist MCP tools. Use this when you want to
  fuzz-test an iOS app, explore screens for bugs, map app navigation, stress-test
  UI elements, or generate fuzzing reports. Requires ButtonHeist MCP server and an
  iOS app with InsideMan embedded.
---
```

Body content (trimmed from CLAUDE.md, ~90 lines):

```markdown
# AI Fuzzer

You are an autonomous iOS app fuzzer. Your job is to explore iOS apps through ButtonHeist's MCP tools, interact with every element you can find, and discover crashes, errors, and edge cases.

You do NOT know the app in advance. You discover its structure dynamically by reading the UI hierarchy and screen captures. You are app-agnostic — your techniques work on any app with InsideMan installed.

## Core Loop

Every fuzzing cycle follows this pattern:

OBSERVE → REASON → ACT → VERIFY → RECORD

1. **OBSERVE**: Call `get_interface` to read the UI hierarchy. Call `get_screen` for visual state.
2. **REASON**: Analyze the elements. What haven't you tried? What looks interesting? What might break?
3. **ACT**: Execute an interaction (tap, swipe, etc.)
4. **VERIFY**: Call `get_interface` + `get_screen` again. Compare with before. Did the screen change? Did anything break?
5. **RECORD**: If you found something interesting, log it as a finding.

## State Tracking

Maintain a mental model as you explore:

- **Current screen**: What elements are visible? Use the element set as a screen fingerprint.
- **Visited screens**: Track which screens you've seen (by their element fingerprint).
- **Tried actions**: For each screen, track which elements you've interacted with and how.
- **Screen transitions**: Record which actions navigate to which screens.
- **Findings**: Accumulate bugs, crashes, and anomalies as you discover them.

### Screen Identification

Screens are identified by their element composition, not by any single identifier. To fingerprint a screen:
1. Get the interface
2. Extract the set of element identifiers and labels
3. Two interfaces represent the same screen if they share the same core interactive elements

Don't over-match — minor value changes (like a timestamp updating) don't mean it's a different screen.

## Crash Detection

**If an MCP tool call fails with a connection error, the app likely crashed.**

This is a **CRASH** severity finding — the most valuable thing you can discover. When this happens:

1. Record the exact action that caused the crash (tool name, all arguments)
2. Record the screen state before the crash (last interface and screen)
3. Record the sequence of actions leading to the crash (last 5-10 actions)
4. Note: the MCP server will need to be restarted since the connection is dead

## Finding Severity Levels

| Severity | Meaning | Examples |
|----------|---------|----------|
| **CRASH** | App died. MCP connection lost. | Tool call fails with connection error after an action |
| **ERROR** | Action failed unexpectedly | `elementNotFound` when element was just visible, `elementDeallocated` during interaction |
| **ANOMALY** | Unexpected behavior | Element disappears after unrelated action, value changes without interaction, screen layout breaks visually |
| **INFO** | Worth noting | Dead-end screens with no back navigation, elements with no actions, unusual accessibility tree structure |

## Finding Format

When you discover something, record it in this format:

## [SEVERITY] Brief description

**Screen**: [screen fingerprint or description]
**Action**: [exact tool call that triggered it]
**Expected**: [what you expected to happen]
**Actual**: [what actually happened]
**Steps to Reproduce**:
1. [navigation steps to reach the screen]
2. [the triggering action]
**Notes**: [any additional context]

## Strategy System

Strategy files in `references/strategies/` define exploration approaches. When a user specifies a strategy with `/fuzz`, read the corresponding file from `references/strategies/` and follow its instructions for:
- How to select which element to interact with next
- Which actions to try and in what order
- When to move to the next screen vs. keep exploring the current one
- What specific anomalies to look for

The default strategy is `systematic-traversal`.

## Exploration Heuristics

When deciding what to do next, prefer actions that:
1. **Haven't been tried** — untested elements and actions first
2. **Navigate somewhere new** — buttons, links, and navigation elements over static content
3. **Affect state** — adjustable elements (sliders, toggles, pickers) over labels
4. **Might break things** — edge cases: rapid taps, extreme values, unusual gestures
5. **Exercise different gesture types** — don't just tap everything; try swipes, long presses, pinches

## Back Navigation

When an action navigates to a new screen and you need to go back:
1. Look for elements with labels like "Back", "Cancel", "Close", "Done", or a back arrow
2. Try swiping right from the left edge (iOS back gesture): `swipe(startX: 0, startY: 400, direction: "right", distance: 200)`
3. Look for elements at the top-left of the screen (navigation bar back button area)
4. As a last resort, the interface tree structure may reveal navigation containers

## Error Recovery

When you encounter non-fatal errors, read `references/troubleshooting.md` for recovery steps. Don't give up on the first error — many issues are recoverable.

## Reporting

When generating a report (via `/report` or at the end of a `/fuzz` session), write to `reports/` with the format:

reports/YYYY-MM-DD-HHMM-fuzz-report.md

Include:
- **Summary**: Total screens visited, actions taken, findings by severity
- **Findings**: Ordered by severity (CRASH first), each with reproduction steps
- **Screen Map**: If `/map-screens` was run, include the navigation graph
- **Coverage**: Which screens were visited, which elements were tested

## Important Rules

- **Always observe before and after every action.** Never fire blind — always get the interface/screen to verify what happened.
- **Don't assume app structure.** You don't know this app. Discover everything dynamically.
- **Record everything interesting.** When in doubt, log it as INFO. Better to over-report than miss something.
- **Handle errors gracefully.** If an action fails, that's data — record it and move on. Read `references/troubleshooting.md` for recovery steps.
- **Don't get stuck.** If you've tried everything on a screen, navigate away. If you can't navigate, report it and try a different approach.
- **Test text fields.** Use `type_text` to enter text into text fields. Try boundary values: empty strings, very long strings, special characters, emoji. Use `deleteCount` to clear and retype. Verify the returned value matches what you typed.
```

#### 2. Create `ai-fuzzer/references/troubleshooting.md`

**File**: `ai-fuzzer/references/troubleshooting.md` (new)

```markdown
# Troubleshooting

Common errors and how to recover from them during fuzzing.

## No devices found

`list_devices` returns empty or errors.

- The iOS app must be running with InsideMan embedded
- The simulator must be booted and the app must be in the foreground
- The MCP server discovers devices via Bonjour — give it 2-3 seconds after app launch
- Try calling `list_devices` again after a short wait

**If persistent**: Stop and tell the user to launch the app.

## get_interface returns empty elements

The response has `elements: []` and `tree: []`.

- The app may not have finished loading. Wait 2 seconds and call `get_interface` again.
- If you just navigated to a new screen, the accessibility tree may still be building. Retry once.
- If persistent after 3 retries: the accessibility tree may be broken. Try tapping the screen center to trigger a layout pass, then retry.
- As a last resort, navigate to a different screen and back, then retry.

**Record as**: ERROR if it never resolves on a screen that clearly has elements (verify via `get_screen`).

## get_interface times out

The tool call returns a timeout error (typically after 10 seconds).

- The app may be stuck processing a previous request.
- Try a simple action first (tap at screen center) to "wake" the app, then retry `get_interface`.
- If persistent after 3 retries: fall back to coordinate-based exploration using `get_screen` for visual observation and `tap(x, y)` for interaction.

**Record as**: ERROR with details about which screen and what preceded the timeout.

## elementNotFound

An action targeting an element by identifier or order fails because the element can't be found.

- The screen likely changed between your `get_interface` call and the action.
- Call `get_interface` again to get the current state.
- Find the element in the new interface (it may have a different order index).
- Retry the action with the updated reference.

**Record as**: ERROR only if the element was present in the interface and still can't be found after refresh.

## elementDeallocated

The element existed but its underlying object was freed.

- This happens when SwiftUI redraws the view between the interface read and the action.
- Call `get_interface` again — the element should reappear with a fresh reference.
- Retry the action.

**Record as**: ANOMALY if it happens repeatedly on the same element. This may indicate a SwiftUI lifecycle bug.

## MCP server won't start

The MCP server binary fails to launch.

- Verify the binary exists: the path in `.mcp.json` must point to a valid executable
- Rebuild if needed: `cd ButtonHeistMCP && swift build -c release`
- Check that no other MCP server instance is already running

**Action**: Stop and tell the user to rebuild the MCP server.

## App crashes (connection lost)

If any MCP tool call fails with a connection error after previously working:

1. **This is a CRASH** — the most valuable finding
2. Stop the fuzzing loop immediately
3. Record the exact action, screen state, and last 5-10 actions
4. Generate the report with what you have
5. Tell the user the app crashed and they need to relaunch it
6. The MCP server connection is dead — a new session is needed
```

#### 3. Create `ai-fuzzer/references/examples.md`

**File**: `ai-fuzzer/references/examples.md` (new)

```markdown
# MCP Tool Response Examples

Concrete examples of what ButtonHeist MCP tool responses look like and how to interpret them.

## get_interface response

Returns an `elements` array and a `tree` array. Each element has:

```
{
  "identifier": "buttonheist.actions.primaryButton",
  "label": "Primary Action",
  "value": null,
  "frameX": 16.0,
  "frameY": 352.0,
  "frameWidth": 361.0,
  "frameHeight": 44.0,
  "actions": ["activate"]
}
```

Key fields:
- **identifier**: Stable across runs. Use for targeting when available.
- **label**: Human-readable text. Use for understanding what the element is.
- **value**: Current value for adjustable elements (sliders show "50%", toggles show "0"/"1").
- **frame**: Position and size in points. Use for coordinate-based targeting.
- **actions**: Available accessibility actions. Elements with `["activate"]` are tappable. Elements with `["increment", "decrement"]` are adjustable.

## Detecting a screen transition

**Before tap**: 8 elements, identifiers include `{home, settings, profile, search}`
**After tap on "settings"**: 12 elements, identifiers include `{back, theme, notifications, privacy}`

The element sets are completely different → this is a **new screen**. Record the transition:
- From: "Main Menu" (fingerprint: {home, settings, profile, search})
- Action: tap(identifier: "settings")
- To: "Settings" (fingerprint: {back, theme, notifications, privacy})

## Detecting NO transition

**Before tap**: 8 elements including `{toggle1}` with value "0"
**After tap on toggle1**: 8 elements including `{toggle1}` with value "1"

Same elements, only a value changed → **same screen**, value updated. This is expected behavior for a toggle.

## Detecting a crash

```
Tool call: tap(identifier: "deleteButton")
Error: "MCP server disconnected" / connection refused / tool not available
```

Any MCP tool failure after the connection was previously working = **CRASH**. The app died. Record immediately.

## Detecting an anomaly

**Before tap on "saveButton"**: Elements include `{saveButton, cancelButton, nameField}`
**After tap**: Elements include `{cancelButton, nameField}` — saveButton is GONE

An element disappeared after an action that shouldn't have removed it → **ANOMALY**. Record it.

## Adjustable element values

**Slider before increment**: value "50"
**After increment**: value "60"
**After 5 more increments**: value "100" (stops increasing — hit max)
**After decrement**: value "90"

Track the value progression. If increment past max wraps to 0, that's an ANOMALY.
```

#### 4. Move strategies to references/strategies/

Move 4 files:
- `ai-fuzzer/strategies/systematic-traversal.md` → `ai-fuzzer/references/strategies/systematic-traversal.md`
- `ai-fuzzer/strategies/boundary-testing.md` → `ai-fuzzer/references/strategies/boundary-testing.md`
- `ai-fuzzer/strategies/gesture-fuzzing.md` → `ai-fuzzer/references/strategies/gesture-fuzzing.md`
- `ai-fuzzer/strategies/state-exploration.md` → `ai-fuzzer/references/strategies/state-exploration.md`

No content changes to strategy files — just the move.

Delete the empty `ai-fuzzer/strategies/` directory after moving.

#### 5. Delete `ai-fuzzer/CLAUDE.md`

Remove the old file. Its content has been incorporated into `SKILL.md` (trimmed).

### Success Criteria:

#### Automated Verification:
- [x] `ai-fuzzer/SKILL.md` exists and starts with valid YAML frontmatter containing `name` and `description`
- [x] `ai-fuzzer/CLAUDE.md` does not exist
- [x] `ai-fuzzer/references/troubleshooting.md` exists
- [x] `ai-fuzzer/references/examples.md` exists
- [x] `ai-fuzzer/references/strategies/systematic-traversal.md` exists
- [x] `ai-fuzzer/references/strategies/boundary-testing.md` exists
- [x] `ai-fuzzer/references/strategies/gesture-fuzzing.md` exists
- [x] `ai-fuzzer/references/strategies/state-exploration.md` exists
- [x] `ai-fuzzer/strategies/` directory does not exist
- [x] `SKILL.md` does NOT contain a "Your Tools" section listing all 17 MCP tools
- [x] `SKILL.md` references `references/strategies/` not `strategies/`
- [x] `SKILL.md` references `references/troubleshooting.md`

**Implementation Note**: After completing this phase and all verification passes, proceed to Phase 2.

---

## Phase 2: Fix Settings + Harden Commands

### Overview
Fix broken permissions so the fuzzer can run autonomously, and add device verification to every command so they fail fast when the app isn't running.

### Changes Required:

#### 1. Fix `ai-fuzzer/.claude/settings.local.json`

**File**: `ai-fuzzer/.claude/settings.local.json`
**Changes**: Replace stale tool names with all 17 correct MCP tool names.

```json
{
  "permissions": {
    "allow": [
      "mcp__buttonheist__list_devices",
      "mcp__buttonheist__get_interface",
      "mcp__buttonheist__get_screen",
      "mcp__buttonheist__tap",
      "mcp__buttonheist__long_press",
      "mcp__buttonheist__swipe",
      "mcp__buttonheist__drag",
      "mcp__buttonheist__pinch",
      "mcp__buttonheist__rotate",
      "mcp__buttonheist__two_finger_tap",
      "mcp__buttonheist__draw_path",
      "mcp__buttonheist__draw_bezier",
      "mcp__buttonheist__activate",
      "mcp__buttonheist__increment",
      "mcp__buttonheist__decrement",
      "mcp__buttonheist__perform_custom_action",
      "mcp__buttonheist__type_text"
    ]
  },
  "enableAllProjectMcpServers": true
}
```

#### 2. Add device verification to all 5 commands

Add the following block as the first step (before any observation) in each command file. In files that already have a "Step 0" (like `fuzz.md` which has "Step 0: Load Strategy"), insert this as a new step before the existing Step 0, and renumber subsequent steps.

**Block to add** (after the YAML frontmatter and title):

```markdown
## Step 0: Verify Connection

1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app and try again
3. Print the connected device name and app name for confirmation
```

**Files to modify**:
- `ai-fuzzer/.claude/commands/fuzz.md` — Insert before current "Step 0: Load Strategy" (renumber: Load Strategy becomes Step 1, Initial Observation becomes Step 2, etc.)
- `ai-fuzzer/.claude/commands/explore.md` — Insert before "Step 1: Observe the Current Screen" (renumber all steps +1)
- `ai-fuzzer/.claude/commands/map-screens.md` — Insert before "Step 1: Start Screen" (renumber all steps +1)
- `ai-fuzzer/.claude/commands/stress-test.md` — Insert before "Step 1: Identify Targets" (renumber all steps +1)
- `ai-fuzzer/.claude/commands/report.md` — Insert before "Step 1: Gather Context" (renumber all steps +1)

#### 3. Update strategy path references in commands

In `ai-fuzzer/.claude/commands/fuzz.md`, update the strategy loading path:

**Old** (line 15): `Read the corresponding strategy file from `strategies/[name].md`. If no strategy specified, read `strategies/systematic-traversal.md`.`

**New**: `Read the corresponding strategy file from `references/strategies/[name].md`. If no strategy specified, read `references/strategies/systematic-traversal.md`.`

### Success Criteria:

#### Automated Verification:
- [x] `.claude/settings.local.json` contains `mcp__buttonheist__get_interface` (not `get_snapshot`)
- [x] `.claude/settings.local.json` contains `mcp__buttonheist__get_screen` (not `get_screenshot`)
- [x] `.claude/settings.local.json` lists exactly 17 tool permissions
- [x] All 5 command files contain "Verify Connection" and `list_devices`
- [x] `fuzz.md` references `references/strategies/` not `strategies/`

---

## Phase 3: Improve Fuzz Intelligence

### Overview
Make `/fuzz` smarter: auto-select strategy based on app characteristics, and refine findings after the main loop.

### Changes Required:

#### 1. Add context-aware strategy auto-selection to `fuzz.md`

**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Where**: In the strategy loading step (formerly Step 0, now Step 1 after Phase 2 renumbering). Add auto-selection logic when no strategy is specified.

Add after the line about reading `references/strategies/systematic-traversal.md`:

```markdown
### Strategy Auto-Selection

If no strategy was specified in `$ARGUMENTS`, choose based on the initial observation (after Step 2):

1. Count the interactive elements on the first screen (elements with actions or that are tappable)
2. Select strategy:
   - **> 3 navigation elements** (tabs, list cells, buttons with navigation labels): use `state-exploration` — map the app structure first
   - **> 5 adjustable elements** (sliders, steppers, pickers): use `boundary-testing` — test value extremes
   - **< 5 total interactive elements**: use `gesture-fuzzing` — go deep on each element with every gesture type
   - **Otherwise** (default): use `systematic-traversal` — breadth-first coverage
3. Print the auto-selected strategy and reasoning
4. Read the corresponding strategy file from `references/strategies/`
```

#### 2. Add iterative refinement pass to `fuzz.md`

**File**: `ai-fuzzer/.claude/commands/fuzz.md`
**Where**: After the main fuzzing loop (Step 3/Step 4 after renumbering), before the report generation step. Add as a new step.

```markdown
## Step N: Refinement Pass

If any ERROR or ANOMALY findings were discovered during the main loop:

1. **Reproduce**: For each finding, navigate back to the screen where it occurred
2. **Confirm**: Attempt to reproduce the exact same action 3 times
3. **Vary**: Try variations of the triggering action:
   - Same element, different action type (tap vs activate vs long_press)
   - Adjacent elements (order +/- 1)
   - Same action after arriving via a different navigation path
4. **Classify**: Update each finding's confidence:
   - **Reproducible**: Triggered on 2+ of 3 attempts
   - **Intermittent**: Triggered on 1 of 3 attempts
   - **Not reproduced**: Could not trigger again (may have been transient)
5. Remove findings that were "Not reproduced" from the final report (mention them in a "Transient observations" section instead)
```

### Success Criteria:

#### Automated Verification:
- [x] `fuzz.md` contains "Strategy Auto-Selection" section
- [x] `fuzz.md` contains "Refinement Pass" section
- [x] `fuzz.md` mentions `state-exploration`, `boundary-testing`, `gesture-fuzzing` in auto-selection logic
- [x] `fuzz.md` mentions "Reproducible" and "Intermittent" confidence levels

---

## Testing Strategy

### Functional Testing:
Since this is agent instruction content (markdown files), not code, testing means verifying:
1. All file paths referenced in SKILL.md and commands actually exist
2. Strategy file paths in commands match actual locations
3. Permission tool names match actual MCP tool names
4. YAML frontmatter parses correctly

### End-to-End Testing:
After all phases complete, the fuzzer should be testable by:
1. `cd ai-fuzzer && claude`
2. The agent should see SKILL.md content in its context
3. `/fuzz` should work: verify connection, load strategy, observe, fuzz, refine, report
4. `/explore` should work with device verification
5. All MCP tools should auto-allow without interactive permission prompts

## References

- Research: `thoughts/shared/research/2026-02-17-fuzzer-skills-guide-evaluation.md`
- Previous report: `ai-fuzzer/reports/2026-02-13-explore-report.md`
- PDF source: "The Complete Guide to Building Skills for Claude"

---
date: 2026-02-17T14:10:06Z
researcher: Claude
git_commit: cbcafba22644a09386d629287f64891c504428cd
branch: RoyalPineapple/ai-fuzz-framework
repository: minnetonka
topic: "Evaluate AI Fuzzer Against 'The Complete Guide to Building Skills for Claude'"
tags: [research, codebase, ai-fuzzer, skills, claude-code, progressive-disclosure]
status: complete
last_updated: 2026-02-17
last_updated_by: Claude
---

# Research: Evaluate AI Fuzzer Against Skills Guide

**Date**: 2026-02-17T14:10:06Z
**Researcher**: Claude
**Git Commit**: cbcafba22644a09386d629287f64891c504428cd
**Branch**: RoyalPineapple/ai-fuzz-framework
**Repository**: minnetonka

## Research Question

Read the PDF "The Complete Guide to Building Skills for Claude" and evaluate the existing AI fuzzer to see if it can be improved by incorporating any advised techniques.

## Summary

The AI fuzzer is a well-structured agent using `.claude/commands/` (slash commands) and a strategy file system for progressive disclosure. It already follows several skill-building best practices: YAML frontmatter on commands, modular strategy files loaded on demand, and a clear step-by-step workflow. However, the guide identifies several concrete improvements that would make the fuzzer more reliable, token-efficient, and easier to distribute.

The biggest wins are: (1) converting from commands to the Skills format for better trigger matching and distribution, (2) trimming the always-loaded CLAUDE.md and moving tool-reference content into on-demand files, (3) adding concrete examples with expected MCP tool outputs, (4) adding a troubleshooting/error-recovery section, and (5) fixing stale permission names in settings.

## Current Architecture

### File Inventory (1,085 total lines)

| File | Lines | Role | When Loaded |
|------|-------|------|-------------|
| `CLAUDE.md` | 165 | Core agent instructions | **Always** (every conversation) |
| `.claude/commands/fuzz.md` | 124 | `/fuzz` command | On `/fuzz` invocation |
| `.claude/commands/explore.md` | 96 | `/explore` command | On `/explore` invocation |
| `.claude/commands/map-screens.md` | 121 | `/map-screens` command | On `/map-screens` invocation |
| `.claude/commands/report.md` | 131 | `/report` command | On `/report` invocation |
| `.claude/commands/stress-test.md` | 147 | `/stress-test` command | On `/stress-test` invocation |
| `strategies/systematic-traversal.md` | 65 | Default strategy | On demand from `/fuzz` |
| `strategies/boundary-testing.md` | 80 | Boundary strategy | On demand from `/fuzz` |
| `strategies/gesture-fuzzing.md` | 73 | Gesture strategy | On demand from `/fuzz` |
| `strategies/state-exploration.md` | 83 | State strategy | On demand from `/fuzz` |
| `.claude/settings.local.json` | 13 | Permissions | Always |
| `.mcp.json` | 11 | MCP server config | Always |
| `README.md` | 142 | Human docs | Never (by agent) |

### What It Does Well

1. **Commands have YAML frontmatter with `description`** — Each command file has a description that helps Claude understand when to invoke it. This mirrors the Skills guide's emphasis on description as trigger.

2. **Strategy files are progressive disclosure** — The strategy system (`strategies/*.md`) is an excellent example of the guide's "Third Level" progressive disclosure. They're loaded on demand by `/fuzz` based on user arguments, not preloaded.

3. **Well-defined workflow** — The core loop (OBSERVE -> REASON -> ACT -> VERIFY -> RECORD) is concrete and actionable. The step-by-step structure in each command follows the guide's advice to "be specific and actionable."

4. **Modular command structure** — Five specialized commands (`fuzz`, `explore`, `map-screens`, `stress-test`, `report`) each handle one workflow. This matches the guide's pattern of focused, single-purpose skills.

5. **Finding severity classification** — CRASH > ERROR > ANOMALY > INFO with structured format. Good domain-specific intelligence.

6. **Clear element targeting documentation** — Three targeting methods (identifier, order, coordinates) are well-documented in CLAUDE.md.

## Detailed Findings: Gaps and Improvements

### 1. Convert from Commands to Skills Format

**Guide recommendation**: Skills use `SKILL.md` with YAML frontmatter (name, description, instructions) and live in a distributable folder with scripts/, references/, assets/ subdirectories.

**Current state**: The fuzzer uses `.claude/commands/*.md` files, which are Claude Code slash commands, not Skills. Commands work but have limitations:
- Commands are project-local (`.claude/commands/`), not distributable as standalone packages
- Commands lack the `name` and `instructions` YAML fields that Skills use for better trigger matching
- Commands cannot bundle resources (scripts, reference data) in a self-contained way

**What to change**: Convert each command to a Skill:
```
ai-fuzzer/
  SKILL.md          <- merged from CLAUDE.md (slim core) + fuzz.md (default behavior)
  scripts/           <- (future: helper scripts if needed)
  references/
    strategies/      <- move strategy files here
    tool-reference.md <- extracted from CLAUDE.md tool table
  assets/            <- (future: example reports, screenshots)
```

The SKILL.md `description` field would be the trigger:
```yaml
name: iOS App Fuzzer
description: >
  Autonomous iOS app fuzzer using ButtonHeist MCP tools. Use this when you want to
  fuzz-test an iOS app, explore screens for bugs, map app navigation, stress-test
  UI elements, or generate fuzzing reports. Requires ButtonHeist MCP server and an
  iOS app with InsideMan embedded.
```

### 2. Trim Always-Loaded Content (Token Economy)

**Guide recommendation**: Keep SKILL.md under 5,000 words. Use progressive disclosure so rarely-needed content isn't loaded every time.

**Current state**: `CLAUDE.md` (165 lines) is loaded into every conversation in the `ai-fuzzer/` directory, even if the user just wants to chat or read a report. It contains:
- Tool documentation (17 tools, ~30 lines) — duplicates what the MCP server already provides
- Core loop explanation (~10 lines) — good, keep this
- State tracking (~10 lines) — good, keep this
- Finding severity table (~10 lines) — good, keep this
- Finding format template (~15 lines) — could move to references/
- Strategy system explanation (~8 lines) — good, keep this
- Exploration heuristics (~8 lines) — good, keep this
- Back navigation tips (~6 lines) — good, keep this
- Reporting instructions (~15 lines) — could move to report command

**What to change**: The "Your Tools" section (lines 7-44) documents all 17 MCP tools with descriptions. This is 38 lines that duplicate what the MCP server's tool definitions already provide to Claude. Remove this entire section — Claude already sees tool descriptions from the MCP server's tool list.

The finding format template (lines 99-114) could move to a `references/finding-template.md` file loaded only when recording a finding.

This would cut CLAUDE.md from ~165 lines to ~90 lines.

### 3. Add Concrete Examples with Expected Outputs

**Guide recommendation**: "Include examples whenever possible. Show the expected input and output for common scenarios."

**Current state**: The commands describe steps procedurally but never show what MCP tool responses look like. For example, `/explore` says "Call `get_interface` to get the full element hierarchy" but doesn't show an example response.

**What to change**: Add a `references/examples.md` file with concrete tool call/response examples:

```markdown
## Example: get_interface response
Elements array with fields:
- identifier: "loginButton"
- label: "Log In"
- value: nil
- frameX: 20.0, frameY: 640.0, frameWidth: 353.0, frameHeight: 44.0
- actions: ["activate"]

## Example: Detecting a screen transition
Before tap: 8 elements, identifiers include {home, settings, profile}
After tap: 12 elements, identifiers include {back, username, email, save}
-> This is a NEW screen (different element set). Record transition.

## Example: Detecting a crash
Tool call: tap(identifier: "deleteButton")
Response: Error - connection refused / MCP server disconnected
-> This is a CRASH. Record the action and last 5-10 steps.
```

This helps the agent handle edge cases correctly without guessing.

### 4. Add Troubleshooting / Error Recovery Section

**Guide recommendation**: "Plan for errors. Include fallback approaches and error handling instructions."

**Current state**: Each command has a "Crash Handling" section for the fatal case (app crash kills MCP connection), but there's no guidance for recoverable errors:
- `get_interface` returning empty elements (happened in the 2026-02-13 exploration — see `reports/2026-02-13-explore-report.md`)
- `get_interface` timing out (10-second timeout, also happened)
- `list_devices` finding no devices
- `elementNotFound` errors when an element was just visible
- `elementDeallocated` during interaction
- MCP server failing to start

**What to change**: Add a troubleshooting section to CLAUDE.md (or as a `references/troubleshooting.md`):

```markdown
## Troubleshooting

### No devices found
- Check the app is running: `list_devices` should show at least one entry
- Check the simulator is booted and the app is in foreground
- The MCP server needs Bonjour to discover devices

### get_interface returns empty elements
- The app may not have finished loading. Wait 2 seconds and retry.
- If persistent: the accessibility tree may be broken. Try navigating
  to a different screen and back.

### get_interface times out
- The app may be stuck processing a previous request.
- Try a simple action (tap at screen center) to "wake" the app, then retry.
- If persistent after 3 retries: report as ERROR and fall back to
  coordinate-based exploration using get_screen for visual observation.

### elementNotFound / elementDeallocated
- The screen may have changed between get_interface and the action.
- Re-read the interface and retry with the updated element reference.
```

### 5. Fix Stale Permission Names in Settings

**Current state** (`.claude/settings.local.json`):
```json
{
  "permissions": {
    "allow": [
      "mcp__buttonheist__get_screenshot",
      "mcp__buttonheist__get_snapshot",
      "mcp__buttonheist__tap"
    ]
  }
}
```

The tool names `get_screenshot` and `get_snapshot` don't match the actual tools `get_screen` and `get_interface`. This means these permissions are no-ops and every tool call still requires interactive approval.

**What to change**: Update to match actual tool names, and add all 17 tools to auto-allow for autonomous fuzzing:
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
  }
}
```

### 6. Add Device Verification Step to Commands

**Guide recommendation (Sequential Workflow Orchestration pattern)**: "Chain tools together in a specific order where each step validates before proceeding."

**Current state**: The `/fuzz` command jumps straight to `get_screen` + `get_interface` in Step 1 without verifying the MCP connection is live.

**What to change**: Add a Step 0.5 to each command:
```markdown
## Step 0: Verify Connection
1. Call `list_devices` — confirm at least one device is connected
2. If no devices found: stop and tell the user to launch the app
3. Print the connected device name and app for confirmation
```

This prevents the fuzzer from running blind when the app isn't running.

### 7. Apply Iterative Refinement Pattern

**Guide recommendation**: "After initial results, refine the approach based on what was found."

**Current state**: The `/fuzz` command runs one pass and generates a report. It doesn't adapt based on intermediate findings.

**What to change**: After the main fuzz loop, add a "refinement pass":
```markdown
## Step 5: Refinement Pass (if findings > 0)
If any ERROR or ANOMALY findings were discovered:
1. Re-visit the screens where findings occurred
2. Try variations of the triggering action:
   - Different timing (faster/slower)
   - Adjacent elements
   - Same action after different navigation paths
3. Attempt to reproduce each finding 3 times to confirm reliability
4. Update finding confidence: "reproducible" or "intermittent"
```

This improves finding quality and reduces false positives.

### 8. Add Context-Aware Strategy Selection

**Guide recommendation (Context-Aware Tool Selection pattern)**: "Dynamically choose tools based on the current context rather than following a fixed sequence."

**Current state**: Strategy is chosen by the user via arguments or defaults to `systematic-traversal`. The agent doesn't adapt strategy based on what it sees.

**What to change**: Add auto-strategy logic to `/fuzz`:
```markdown
## Strategy Auto-Selection (when no strategy specified)
After the initial observation (Step 1), choose strategy based on app characteristics:
- If > 20 interactive elements on first screen: `systematic-traversal` (breadth)
- If > 5 adjustable elements (sliders, steppers): `boundary-testing`
- If > 3 navigation elements (tabs, list cells): `state-exploration` (map first)
- If < 5 interactive elements: `gesture-fuzzing` (go deep on each)
```

## Code References

- `ai-fuzzer/CLAUDE.md:7-44` — Tool documentation section (candidate for removal)
- `ai-fuzzer/CLAUDE.md:46-58` — Core loop definition (keep as-is)
- `ai-fuzzer/CLAUDE.md:79-97` — Crash detection and severity levels (keep)
- `ai-fuzzer/CLAUDE.md:116-124` — Strategy system (keep, enhance with auto-selection)
- `ai-fuzzer/.claude/commands/fuzz.md:19-29` — Step 1 missing device verification
- `ai-fuzzer/.claude/commands/fuzz.md:42-79` — Main fuzz loop (add refinement pass after)
- `ai-fuzzer/.claude/settings.local.json:3-5` — Stale permission names
- `ai-fuzzer/reports/2026-02-13-explore-report.md:32-44` — get_interface timeout anomaly (motivates troubleshooting section)

## Impact Assessment

| Improvement | Effort | Impact | Priority |
|-------------|--------|--------|----------|
| Fix stale permissions in settings.local.json | 5 min | High (blocks autonomous operation) | **P0** |
| Add device verification step | 10 min | Medium (prevents blind runs) | **P1** |
| Remove duplicate tool docs from CLAUDE.md | 10 min | Medium (saves ~38 lines of tokens) | **P1** |
| Add troubleshooting/error recovery | 20 min | High (addresses known failure modes) | **P1** |
| Add examples with expected outputs | 30 min | Medium (improves agent accuracy) | **P2** |
| Add iterative refinement pass | 15 min | Medium (improves finding quality) | **P2** |
| Add context-aware strategy selection | 15 min | Low-Medium (nice-to-have) | **P3** |
| Convert to Skills format | 1-2 hr | Low (commands work fine for now) | **P3** |

## Architecture Documentation

The fuzzer uses a two-tier progressive disclosure architecture:

```
Tier 1 (always loaded):
  CLAUDE.md — Core identity, loop, severity levels, heuristics
  .mcp.json — MCP server config
  settings.local.json — Permissions

Tier 2 (loaded on demand):
  .claude/commands/*.md — Specific workflows (loaded when user types /fuzz etc.)
  strategies/*.md — Exploration strategies (loaded by /fuzz based on arguments)
```

This maps closely to the Skills guide's 3-level progressive disclosure, with:
- Tier 1 = SKILL.md frontmatter + core body (Level 1 + 2)
- Tier 2 = referenced files (Level 3)

The main structural gap vs. Skills format is that Tier 1 contains too much reference material (tool docs) that should live in Tier 2, and the system doesn't auto-select behavior based on context.

## Related Research

- `ai-fuzzer/reports/2026-02-13-explore-report.md` — Previous exploration session showing the `get_interface` timeout issues that motivate the troubleshooting section recommendation.

## Open Questions

1. **Should the fuzzer convert to Skills format now or later?** The current `.claude/commands/` approach works. Skills would mainly help with distribution (sharing the fuzzer with other projects) and trigger matching (auto-invoking without `/` prefix). Worth deferring unless distribution is a near-term goal.

2. **Should strategies auto-compose?** The guide's Multi-MCP Coordination pattern suggests combining tools dynamically. Could the fuzzer run multiple strategies in sequence (e.g., systematic-traversal for coverage, then boundary-testing on elements that showed anomalies)?

3. **Should the fuzzer persist state across sessions?** Currently each `/fuzz` run starts fresh. Persisting coverage data (which screens/elements have been tested) would allow incremental fuzzing. The guide doesn't address persistence, but it's a natural extension of the iterative refinement pattern.

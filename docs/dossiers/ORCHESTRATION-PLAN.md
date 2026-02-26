# Orchestration Plan — Parallel Implementation of All Crew Improvement Plans

## Overview

This document is an executable outer loop. It spawns parallel Opus sub-agents via the `Task` tool, each implementing one plan from the `docs/dossiers/` stack. Agents run in isolated git worktrees so they don't conflict. Between batches, their branches are merged, builds are verified, and the next batch launches.

7 batches. ~13 plans. The outer loop runs until the stack is empty.

## Execution Model

```
┌─────────────────────────────────────────────┐
│                 OUTER LOOP                   │
│                                              │
│  for each batch:                             │
│    1. Spawn parallel agents (worktrees)      │
│    2. Wait for all agents to complete        │
│    3. Merge worktree branches sequentially   │
│    4. Run full build verification            │
│    5. Commit verified state                  │
│    6. Proceed to next batch                  │
│                                              │
│  on failure:                                 │
│    - Report which agent failed and why       │
│    - Fix or retry before proceeding          │
└─────────────────────────────────────────────┘
```

### Agent Configuration

Every sub-agent uses:
- `subagent_type: "general-purpose"` (access to all tools)
- `model: "opus"`
- `isolation: "worktree"` (isolated git copy)

### Agent Prompt Template

Each agent receives a prompt structured as:

```
You are implementing a performance improvement plan for the ButtonHeist codebase.

PLAN FILE: docs/dossiers/{XX-NAME-PLAN.md}
SCOPE: {phase scope — "all phases" or "Phase N only"}

Instructions:
1. Read the plan file completely
2. Read all files mentioned in the plan
3. Implement each phase sequentially
4. After each phase, run build verification:
   {relevant build commands}
5. Fix any build errors before moving on
6. Do NOT pause for manual verification — execute all phases consecutively
7. Commit your changes with a descriptive message when done

IMPORTANT:
- Follow the plan's intent, but adapt to what you find in the code
- If something doesn't match the plan, document what you found and proceed with your best judgment
- Do not modify files outside your plan's scope
- {batch-specific constraints}
```

### Build Verification Commands

**iOS framework builds (after any InsideJob/Wheelman/Score/Muscle changes):**
```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build
```

**CLI build (after CLI/TheFence changes):**
```bash
cd ButtonHeistCLI && swift build -c release
```

**MCP build (after MCP changes):**
```bash
cd ButtonHeistMCP && swift build -c release
```

**Full test suite (between batches):**
```bash
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScoreTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test
xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJobTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

---

## Batch 1: Self-Contained (No Dependencies)

**Agents: 2 (parallel)**
**Risk: Minimal** — zero shared files, zero dependencies

### Agent 1A: ThePlant

```
Plan: docs/dossiers/06-THEPLANT-PLAN.md
Scope: All phases
Files: InsideJob+AutoStart.swift, ThePlantAutoStart.m
Build verify: xcodebuild ... -scheme InsideJob -destination 'generic/platform=iOS' build
```

### Agent 1B: TheScore Codable Fix

```
Plan: docs/dossiers/07-THESCORE-PLAN.md
Scope: Phase 3 ONLY (ElementAction Codable edge case)
Files: Elements.swift
Build verify: xcodebuild ... -scheme TheScore build && xcodebuild ... -scheme TheScoreTests test
```

### Batch 1 Gate
- [x] Merge Agent 1A branch (implemented directly — worktree permissions issue)
- [x] Merge Agent 1B branch (implemented directly — worktree permissions issue)
- [x] Run: InsideJob build + TheScore build + TheScore tests
- [ ] Commit: "Batch 1: ThePlant @objc migration + TheScore Codable fix"

---

## Batch 2: Core Infrastructure

**Agents: 3 (parallel)**
**Risk: Medium** — no shared files between these three plans, but significant internal complexity

### Agent 2A: TheMuscle

```
Plan: docs/dossiers/02-THEMUSCLE-PLAN.md
Scope: Phases 1-5 ONLY (NOT Phase 6 — subscriptions move comes in Batch 3)
Constraint: Do NOT modify InsideJob.swift. Phase 6 is deferred.
Files: TheMuscle.swift, WIRE-PROTOCOL.md
Build verify: xcodebuild ... -scheme InsideJob -destination 'generic/platform=iOS' build
```

### Agent 2B: TheWheelman

```
Plan: docs/dossiers/08-WHEELMAN-PLAN.md
Scope: Phases 1-5 (actor rewrite, USB fix, vendorid removal, server transport)
Constraint: Phase 5 creates the server-side API that InsideJob will consume in Batch 3.
             Do NOT modify InsideJob.swift yet.
             Phase 6 (Bonjour session broadcast) and Phase 7 (tests) can be included if clean.
Files: SimpleSocketServer.swift, USBDeviceDiscovery.swift, DeviceDiscovery.swift, new transport types
Build verify: xcodebuild ... -scheme Wheelman build && xcodebuild ... -scheme WheelmanTests test
```

### Agent 2C: TheFingerprints

```
Plan: docs/dossiers/05-FINGERPRINTS-PLAN.md
Scope: Phases 1-2 (rename + minimum display time)
Constraint: Phase 3 (compositing coordination) deferred to Batch 4 with TheStakeout.
             Do NOT modify Stakeout.swift.
Files: Fingerprints.swift
Build verify: xcodebuild ... -scheme InsideJob -destination 'generic/platform=iOS' build
```

### Batch 2 Gate
- [ ] Merge Agent 2A branch (TheMuscle)
- [ ] Merge Agent 2B branch (TheWheelman)
- [ ] Merge Agent 2C branch (TheFingerprints)
- [ ] Run: Full framework build (all 4 schemes) + Wheelman tests + TheScore tests
- [ ] Commit: "Batch 2: TheMuscle session simplification + TheWheelman actor rewrite + TheFingerprints rename"

---

## Batch 3: The Big Extraction (InsideJob)

**Agents: 1 (sequential — heavy file coordination)**
**Risk: High** — creates TheBagman, moves code across 8+ files, coordinates with Batches 1-2 outputs

### Agent 3A: InsideJob Full Plan

```
Plan: docs/dossiers/01-INSIDEJOB-PLAN.md
Scope: All 6 phases
Context: TheMuscle (Batch 2) is already simplified. TheWheelman (Batch 2) has server transport API ready.
Phase 1: Move networking to TheWheelman's new server transport API
Phase 2: Move subscriptions to TheMuscle (completes TheMuscle Phase 6 simultaneously)
Phase 3: Create TheBagman — the big extraction
Phases 4-6: Cleanup, singleton fix, linter suppression removal
Build verify: Full build after each phase. All 4 framework schemes + tests.
```

### Batch 3 Gate
- [ ] Merge branch to main
- [ ] Run: Full framework build + ALL tests (InsideJob, Wheelman, TheScore, ButtonHeist)
- [ ] Commit: "Batch 3: InsideJob extraction — TheBagman created, networking to Wheelman, subscriptions to Muscle"

---

## Batch 4: Consumers

**Agents: 2 (parallel)**
**Risk: Medium** — TheSafecracker depends on TheBagman (Batch 3). Stakeout+Score share a file but are grouped.

### Agent 4A: TheSafecracker

```
Plan: docs/dossiers/03-THESAFECRACKER-PLAN.md
Scope: All 6 phases
Context: TheBagman exists (Batch 3). TheSafecracker+Elements.swift may already be deleted by Batch 3.
         If already deleted, skip Phase 1 deletion and focus on remaining phases.
Files: TheSafecracker*.swift, InsideJob.swift (orchestration changes only)
Build verify: xcodebuild ... -scheme InsideJob -destination 'generic/platform=iOS' build
```

### Agent 4B: TheStakeout + TheScore (coordinated)

```
Plans: docs/dossiers/04-STAKEOUT-PLAN.md AND docs/dossiers/07-THESCORE-PLAN.md
Scope: Stakeout all phases + TheScore Phase 2 (InteractionEvent) + Phase 4 (test coverage)
Context: TheFingerprints minimum display time is guaranteed (Batch 2).
         ServerMessages.swift change is shared — implement once for both plans.
Constraint: TheScore Phase 5 (docs) deferred to Batch 7.
Files: Stakeout.swift, ServerMessages.swift, Elements.swift, RecordingPayloadTests.swift, ActionCommandTests.swift
Build verify: Full build + TheScore tests + InsideJob tests
```

### Batch 4 Gate
- [ ] Merge Agent 4A branch (TheSafecracker)
- [ ] Merge Agent 4B branch (TheStakeout + TheScore)
- [ ] Run: Full framework build + ALL tests
- [ ] Commit: "Batch 4: TheSafecracker pure fingers + TheStakeout rename + InteractionEvent diffs"

---

## Batch 5: The Atomic Name Swap

**Agents: 1 (MUST be single agent — atomic rename)**
**Risk: High** — cascading rename across entire codebase, two types swapping names

### Agent 5A: TheClient → TheMastermind + TheMastermind → TheFence

```
Plans: docs/dossiers/09-THECLIENT-PLAN.md AND docs/dossiers/10-THEFENCE-PLAN.md
Scope: Phase 1 (rename) from BOTH plans as a single atomic operation.
       Then remaining phases from both plans.

CRITICAL ORDERING:
1. First rename TheMastermind.swift → TheFence.swift (and all MastermindX → FenceX types)
2. Then rename TheClient.swift → TheMastermind.swift
3. Update ALL references across the entire codebase in the same commit
4. Then implement remaining phases (discovery move, connection move, dispatch fix, etc.)

Context: TheWheelman (Batch 2) has discovery/connection APIs ready to consume.

Files: TheMastermind.swift, TheClient.swift, MastermindCommandCatalog.swift,
       DeviceConnector.swift, all CLI/MCP/test files with references
Build verify: ALL schemes + CLI build + MCP build + ALL tests
```

### Batch 5 Gate
- [ ] Merge branch to main
- [ ] Run: Full build (all 4 framework schemes + CLI + MCP) + ALL tests
- [ ] Commit: "Batch 5: TheClient → TheMastermind, TheMastermind → TheFence"

---

## Batch 6: Outer Layer

**Agents: 2 (parallel)**
**Risk: Low** — mostly deletions and reference updates

### Agent 6A: CLI

```
Plan: docs/dossiers/11-CLI-PLAN.md
Scope: All 4 phases
Context: FenceError exists (Batch 5). Watch mode removal is confirmed.
Constraint: DeviceConnector.swift CLIError→FenceError may already be done by Batch 5 Agent 5A.
            If so, skip that step.
Files: CLIRunner.swift (delete), WatchCommand.swift (delete), DeviceConnector.swift, ActionCommandTests.swift
Build verify: cd ButtonHeistCLI && swift build -c release
```

### Agent 6B: MCP

```
Plan: docs/dossiers/12-MCP-PLAN.md
Scope: All 4 phases
Context: TheFence exists (Batch 5).
Files: main.swift (MCP), ToolDefinitions.swift, shared version constant location
Build verify: cd ButtonHeistMCP && swift build -c release
```

### Batch 6 Gate
- [ ] Merge Agent 6A branch (CLI)
- [ ] Merge Agent 6B branch (MCP)
- [ ] Run: CLI build + MCP build + full framework build + ALL tests
- [ ] Commit: "Batch 6: CLI watch mode removed + MCP validation and TheFence alignment"

---

## Batch 7: Documentation

**Agents: 1 (low risk, sequential)**
**Risk: Minimal** — docs only

### Agent 7A: Documentation Sweep

```
Plans: docs/dossiers/00-OVERVIEW-PLAN.md + docs/dossiers/07-THESCORE-PLAN.md Phase 5
Scope: CLAUDE.md dossier maintenance section + API.md + WIRE-PROTOCOL.md updates
Context: All code changes are complete. Docs must reflect final state.
Constraint: Read the actual codebase to verify docs match — don't just copy from plans.
Files: CLAUDE.md, docs/API.md, docs/WIRE-PROTOCOL.md
Build verify: No build needed. Verify docs are internally consistent.
```

### Batch 7 Gate
- [ ] Merge branch to main
- [ ] Final commit: "Batch 7: Documentation updated to reflect all crew improvements"

---

## Outer Loop Pseudocode

```
batches = [batch_1, batch_2, batch_3, batch_4, batch_5, batch_6, batch_7]

for batch in batches:
    # 1. Launch agents
    agents = []
    for agent_spec in batch.agents:
        agent = Task(
            subagent_type="general-purpose",
            model="opus",
            isolation="worktree",
            run_in_background=True,
            prompt=build_prompt(agent_spec)
        )
        agents.append(agent)

    # 2. Wait for all agents
    for agent in agents:
        result = TaskOutput(agent.task_id, block=True, timeout=600000)
        if result.failed:
            STOP — report failure, fix, retry

    # 3. Merge worktree branches
    for agent in agents:
        git merge agent.branch --no-ff
        if conflict:
            resolve_conflict()  # manual or automated

    # 4. Build verification
    run_build_verification(batch.verify_commands)
    if build_fails:
        STOP — diagnose, fix, re-verify

    # 5. Commit batch
    git commit -m "Batch {N}: {description}"

print("All batches complete.")
```

## Failure Handling

| Failure Type | Response |
|-------------|----------|
| Agent build failure | Agent should fix in-worktree. If it can't, the outer loop retries with more context. |
| Merge conflict | Resolve manually. Conflicts indicate a shared-file issue missed in planning. |
| Test failure post-merge | Diagnose which agent's changes broke it. Resume that agent with fix instructions. |
| Agent timeout | Check progress via `TaskOutput(block=false)`. Resume or restart. |

## Estimated Complexity per Batch

| Batch | Agents | Parallel? | Risk | Est. Scope |
|-------|--------|-----------|------|-----------|
| 1 | 2 | Yes | Low | 2-3 files each |
| 2 | 3 | Yes | Medium | 5-10 files each, actor rewrite |
| 3 | 1 | No | High | 8+ files, creates TheBagman |
| 4 | 2 | Yes | Medium | 4-6 files each |
| 5 | 1 | No | High | Cascading rename, 20+ files |
| 6 | 2 | Yes | Low | 3-4 files each, mostly deletions |
| 7 | 1 | No | Minimal | 3 doc files |

## Progress Tracking

Use the TaskCreate/TaskUpdate tools to track batch completion:
- One task per batch
- Mark in_progress when agents launch
- Mark completed when batch gate passes
- Block later batches on earlier ones

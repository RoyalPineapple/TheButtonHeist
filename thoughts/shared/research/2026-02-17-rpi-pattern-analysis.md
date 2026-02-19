---
date: 2026-02-17T15:47:25Z
researcher: Claude
git_commit: 15030cb9977c366edb8e16f32264a21a5cce6ed5
branch: RoyalPineapple/ai-fuzz-framework
repository: RoyalPineapple/accra
topic: "RPI (Research, Plan, Implement) pattern analysis — lessons for fuzzer agent architecture"
tags: [research, rpi, agent-architecture, fuzzer, sub-agents, context-engineering]
status: complete
last_updated: 2026-02-17
last_updated_by: Claude
---

# Research: RPI Pattern Analysis for Fuzzer Agent Architecture

**Date**: 2026-02-17T15:47:25Z
**Researcher**: Claude
**Git Commit**: 15030cb
**Branch**: RoyalPineapple/ai-fuzz-framework
**Repository**: RoyalPineapple/accra
**Source**: https://github.com/squareup/rpi

## Research Question

What can we learn from Square's RPI (Research, Plan, Implement) framework to restructure the AI fuzzer as an agent that delegates to sub-agents? How does information flow between RPI's commands and agents, and how should we apply this pattern to fuzzing?

## Summary

RPI's core insight is **compression and distillation** — each phase produces a focused artifact that curates the relevant context for the next phase. Commands (opus) orchestrate, agents (sonnet) do focused work. The fuzzer can adopt this pattern, but the interactive MCP-tool-dependent nature of fuzzing means the main agent must stay in the loop for all tool calls. Sub-agents should handle analysis, strategy selection, and report generation — not individual actions.

## RPI Framework Structure

### Repository Layout

```
squareup/rpi/
├── AGENTS.md           # Installation + structure docs (shared across CLAUDE.md, GEMINI.md)
├── CLAUDE.md           # Same as AGENTS.md
├── GEMINI.md           # Same as AGENTS.md
├── README.md           # Philosophy + overview
├── agents/
│   ├── codebase-analyzer.md       # HOW code works (Read, Grep, Glob, LS)
│   ├── codebase-locator.md        # WHERE code lives (Grep, Glob, LS — no Read)
│   ├── codebase-pattern-finder.md # Find patterns/examples (Grep, Glob, Read, LS)
│   ├── thoughts-analyzer.md       # Extract insights from research docs
│   ├── thoughts-locator.md        # Find relevant research docs
│   └── web-search-researcher.md   # External web research
├── commands/
│   ├── research_codebase.md       # Phase 1: Research
│   ├── create_plan.md             # Phase 2: Plan
│   ├── implement_plan.md          # Phase 3: Implement
│   └── iterate_plan.md            # Update existing plans
└── script/
    └── install                    # zsh installer
```

### Key Design Patterns

#### 1. Model Hierarchy: Opus Orchestrates, Sonnet Executes

- **Commands** use `opus` model — they make high-level decisions, decompose problems, synthesize findings
- **Agents** use `sonnet` model — they do focused, bounded work (search, analyze, locate)
- This is cost-efficient: the expensive model only runs for orchestration, not for every file read

#### 2. Compression/Distillation Pipeline

Each phase produces a compressed artifact that curates context for the next:

```
Codebase (1M+ lines)
    ↓ /research_codebase
Research Doc (focused report with file:line refs)
    ↓ /create_plan
Implementation Plan (phased steps with success criteria)
    ↓ /implement_plan
Working Code (verified against success criteria)
```

The key insight: **"How do you best take a 1M+ line codebase and find, extract, and represent the pieces that are relevant to the problem at hand."**

#### 3. Agent Specialization (Single Responsibility)

Each agent has ONE job and explicitly refuses to do anything else:

| Agent | Job | Tools | Anti-Pattern Avoided |
|-------|-----|-------|---------------------|
| `codebase-locator` | Find WHERE files live | Grep, Glob, LS | Never reads file contents |
| `codebase-analyzer` | Explain HOW code works | Read, Grep, Glob, LS | Never suggests improvements |
| `codebase-pattern-finder` | Find similar implementations | Read, Grep, Glob, LS | Never recommends one pattern over another |
| `thoughts-locator` | Find relevant research docs | Grep, Glob, LS | Never analyzes contents |
| `thoughts-analyzer` | Extract insights from docs | Read, Grep, Glob, LS | Never summarizes — curates |
| `web-search-researcher` | Find external information | WebSearch, WebFetch, etc. | Always cites sources with links |

The "documentarian, not critic" philosophy prevents agents from going off on tangents. They describe what IS, not what should be.

#### 4. Structured Output Formats

Every agent has a defined output format with specific sections. This makes the output predictable and parseable by the orchestrating command:

- `codebase-analyzer` → Overview, Entry Points, Core Implementation (with file:line), Data Flow, Key Patterns, Configuration, Error Handling
- `thoughts-analyzer` → Document Context, Key Decisions, Critical Constraints, Technical Specifications, Actionable Insights, Still Open/Unclear, Relevance Assessment

#### 5. Persistent Artifacts

All outputs go to predictable locations:
- Research → `thoughts/shared/research/YYYY-MM-DD-description.md`
- Plans → `thoughts/shared/plans/YYYY-MM-DD-description.md`
- Knowledge → `.agents/knowledge/`

These persist across sessions and can be consumed by any phase.

#### 6. YAML Frontmatter for Agent Metadata

```yaml
---
name: codebase-analyzer
description: [human-readable description]
tools: Read, Grep, Glob, LS
model: sonnet
---
```

This declarative format makes agents self-describing and installable.

## How Information Flows in RPI

```
User Question
    │
    ▼
/research_codebase (opus)
    ├── spawns codebase-locator (sonnet) → file paths
    ├── spawns codebase-analyzer (sonnet) → implementation details
    ├── spawns codebase-pattern-finder (sonnet) → usage examples
    ├── spawns thoughts-locator (sonnet) → related research
    └── synthesizes all findings → research document
         │
         ▼
/create_plan (opus)
    ├── reads research document
    ├── spawns agents for additional investigation
    ├── interactive discussion with user
    └── produces implementation plan
         │
         ▼
/implement_plan (opus)
    ├── reads plan
    ├── reads all referenced files
    ├── implements phase by phase
    ├── runs success criteria checks
    └── pauses for human verification between phases
```

The critical pattern: **each phase consumes the artifact of the previous phase, not the raw inputs.** The plan doesn't read the whole codebase — it reads the research document. The implementation doesn't research the codebase — it follows the plan.

## Current Fuzzer Structure

### Layout

```
ai-fuzzer/
├── SKILL.md                          # Core agent instructions (identity, loop, rules)
├── README.md
├── .claude/commands/
│   ├── fuzz.md                       # Main fuzzing loop
│   ├── explore.md                    # Screen deep-dive
│   ├── map-screens.md                # Navigation mapping
│   ├── stress-test.md                # Element stress testing
│   ├── reproduce.md                  # Finding reproduction
│   └── report.md                     # Report generation
└── references/
    ├── strategies/                   # 6 strategy files
    ├── trace-format.md               # Trace file format spec
    ├── interesting-values.md         # Test input dictionary
    ├── action-patterns.md            # Interaction templates
    ├── simulator-lifecycle.md        # xcrun simctl reference
    ├── simulator-snapshots.md        # State save/restore
    ├── troubleshooting.md            # Error recovery
    └── examples.md                   # Usage examples
```

### Current Architecture: Monolithic Command

Currently, `/fuzz` is a single monolithic command that:
1. Connects to the device
2. Observes the screen
3. Selects a strategy
4. Runs the fuzzing loop (observe → reason → act → verify → record)
5. Records findings
6. Runs refinement pass
7. Generates report

All reasoning happens in the main agent's context. There are no sub-agents.

### Key Difference from RPI

RPI operates on a **static codebase** — file contents don't change during analysis. The fuzzer operates on a **live app** — state changes with every interaction. This means:

- RPI agents can work independently in parallel (reading different files)
- Fuzzer actions are sequential and stateful (each action depends on the result of the previous one)
- RPI agents don't need tool access beyond file reading
- The fuzzer agent needs MCP tools (ButtonHeist) that are only available to the main agent, not sub-agents

## Applying RPI Patterns to the Fuzzer

### What Works Directly

#### 1. Compression/Distillation Between Phases

The fuzzer already has natural phases that could produce compressed artifacts:

```
App (unknown)
    ↓ /explore or initial observation
Screen Map + Element Catalog (compressed understanding)
    ↓ Strategy selection + scoring
Prioritized Action Plan
    ↓ /fuzz
Findings + Traces
    ↓ /reproduce
Verified Findings with Reproduction Status
    ↓ /report
Final Report
```

Each phase should produce a focused document that curates context for the next.

#### 2. Agent Specialization for Analysis Tasks

Sub-agents can handle reasoning-heavy tasks that don't require MCP tools:

| Proposed Agent | Job | Inputs | Output |
|---------------|-----|--------|--------|
| `screen-analyzer` | Analyze a screen's element tree | `get_interface` JSON output | Screen fingerprint, element catalog, scoring, navigation suggestions |
| `finding-analyzer` | Determine if before/after state constitutes a finding | Before/after interface state | Finding classification (CRASH/ERROR/ANOMALY/INFO/none) with reasoning |
| `strategy-advisor` | Recommend a strategy based on app characteristics | Screen map, element counts, coverage data | Recommended strategy with rationale |
| `coverage-analyzer` | Analyze coverage data and suggest next targets | Session notes (Coverage, Screens, Transitions) | Prioritized list of screens/elements to target next |
| `report-generator` | Generate a structured report from session data | Session notes, findings, coverage | Formatted report document |
| `trace-reviewer` | Analyze a trace for patterns and anomalies | Trace file | Pattern analysis, timing anomalies, action sequence insights |

#### 3. Persistent Artifacts Already Exist

The fuzzer already writes to `session/` (notes + traces) and `reports/`. These serve the same role as RPI's `thoughts/shared/` — persistent, cross-session artifacts that any phase can consume.

### What Needs Adaptation

#### 1. The Main Loop Must Stay in the Main Agent

Unlike RPI where sub-agents can work independently, the fuzzer's main loop (observe → act → verify) requires MCP tools at every step. Sub-agents can't call `get_interface`, `activate`, etc.

**Solution**: The main agent handles the tight loop, but delegates analysis to sub-agents at phase boundaries:

```
Main Agent (opus, has MCP tools):
    ├── Calls get_interface, activate, etc.
    ├── Maintains the fuzzing loop
    └── At key moments, delegates to sub-agents:
        ├── "Analyze this screen" → screen-analyzer (sonnet)
        ├── "Is this a finding?" → finding-analyzer (sonnet)
        ├── "What should I fuzz next?" → coverage-analyzer (sonnet)
        └── "Generate the report" → report-generator (sonnet)
```

#### 2. Sub-Agent Frequency: Per-Phase, Not Per-Action

Spawning a sub-agent for every action (100+ per session) would be too slow. Instead, use sub-agents at phase boundaries:

- **Session start**: `strategy-advisor` analyzes initial screen → recommends strategy
- **Every ~20 actions**: `coverage-analyzer` reviews progress → suggests next targets
- **Per finding**: `finding-analyzer` classifies the finding
- **Session end**: `report-generator` produces the final report
- **On reproduce**: `trace-reviewer` analyzes the trace before replay

#### 3. Context Must Be Serialized for Sub-Agents

Sub-agents don't share the main agent's context. They need self-contained inputs:

```
Main agent collects:
  - Current get_interface output (JSON)
  - Session notes (markdown)
  - Coverage data (from notes)
  - Last 10 actions (from trace)

Packages this as a prompt to the sub-agent:
  "Here's the current screen state [JSON], the session coverage [markdown],
   and the last 10 actions [trace entries]. What element should I target next?"
```

This serialization IS the compression step — it forces the main agent to curate what's relevant.

### Proposed Restructured Architecture

```
ai-fuzzer/
├── SKILL.md                          # Core agent identity + rules
├── .claude/
│   ├── commands/                     # User-invocable commands (like RPI commands)
│   │   ├── fuzz.md                   # Orchestrates the fuzzing session
│   │   ├── explore.md                # Deep-dive exploration
│   │   ├── reproduce.md              # Finding reproduction
│   │   └── report.md                 # Report generation
│   └── agents/                       # Sub-agents (like RPI agents)
│       ├── screen-analyzer.md        # Analyze element trees
│       ├── finding-analyzer.md       # Classify findings
│       ├── strategy-advisor.md       # Recommend strategies
│       ├── coverage-analyzer.md      # Identify coverage gaps
│       └── report-generator.md       # Generate reports
├── references/                       # Reference material (unchanged)
│   ├── strategies/
│   ├── trace-format.md
│   └── ...
└── session/                          # Session artifacts (unchanged)
```

### Information Flow in the New Architecture

```
User: /fuzz
    │
    ▼
fuzz.md (main agent, opus, has MCP tools)
    │
    ├── Step 1: Observe (get_interface, get_screen)
    │
    ├── Step 2: Delegate → strategy-advisor (sonnet)
    │   Input: element tree, element counts, prior session summaries
    │   Output: recommended strategy + rationale
    │
    ├── Step 3: Fuzzing loop (main agent handles all MCP calls)
    │   ├── Every 20 actions: Delegate → coverage-analyzer (sonnet)
    │   │   Input: session notes (coverage, screens, transitions)
    │   │   Output: prioritized target list
    │   ├── On potential finding: Delegate → finding-analyzer (sonnet)
    │   │   Input: before state, action, after state
    │   │   Output: finding classification + severity
    │   └── Continue loop...
    │
    ├── Step 4: Refinement (main agent replays, delegates analysis)
    │
    └── Step 5: Delegate → report-generator (sonnet)
        Input: session notes, findings, coverage data
        Output: formatted report document
```

## Key Takeaways from RPI

1. **Context engineering > prompt engineering.** The quality of the input determines the quality of the output. Curate aggressively.

2. **Phases produce artifacts, not just actions.** Each phase's output is a compressed, curated document that serves as input to the next phase.

3. **Agents do one thing well.** Single-responsibility agents with constrained tool access and defined output formats are more reliable than generalist agents.

4. **Expensive models orchestrate, cheaper models execute.** Use opus for decisions, sonnet for analysis. The cost structure favors this split.

5. **Persistent artifacts enable cross-session learning.** Session notes, traces, and reports persist and can be consumed by future sessions.

6. **Declarative agent definitions.** YAML frontmatter (name, description, tools, model) makes agents self-describing, installable, and portable.

## Code References

- RPI source: https://github.com/squareup/rpi
- `commands/research_codebase.md` — orchestrator pattern, spawns 3-6 parallel sub-agents
- `commands/implement_plan.md` — plan-follower pattern, phase-by-phase with success criteria checks
- `agents/codebase-analyzer.md` — focused agent pattern, strict output format, "documentarian not critic"
- Current fuzzer: `ai-fuzzer/SKILL.md` — monolithic agent, no sub-agent delegation
- Current fuzzer: `ai-fuzzer/.claude/commands/fuzz.md` — monolithic fuzzing loop

## Open Questions

1. **Should sub-agents be in `.claude/agents/` (Skills format) or a custom directory?** Claude Code doesn't currently have a standard for sub-agent definitions within a Skill. RPI installs agents to `~/.claude/agents/` globally. For the fuzzer, project-local agents in `ai-fuzzer/.claude/agents/` may be more appropriate but may require manual wiring.

2. **How to pass MCP tool output to sub-agents?** The `get_interface` response is JSON. Sub-agents would receive this as part of their prompt. Need to determine the right level of detail — full JSON vs. summarized.

3. **Sub-agent latency budget.** Each sub-agent spawn adds ~5-15 seconds. For a 100-action session, calling sub-agents every 20 actions = 5 sub-agent calls = ~60-75 seconds of overhead. Acceptable?

4. **Can sub-agents write to session notes/traces?** Currently only the main agent writes. If sub-agents generate findings or coverage analysis, the main agent would need to incorporate their output into the session files.

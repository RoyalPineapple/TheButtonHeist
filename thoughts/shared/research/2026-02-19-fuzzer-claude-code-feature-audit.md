---
date: "2026-02-19T13:16:35Z"
researcher: Claude
git_commit: 9f6a89a
branch: RoyalPineapple/diverse-fuzz-tests
repository: beirut
topic: "AI Fuzzer Claude Code Feature Audit: Commands vs Skills vs Agents"
tags: [research, codebase, ai-fuzzer, claude-code, skills, commands, agents]
status: complete
last_updated: 2026-02-19
last_updated_by: Claude
---

# Research: AI Fuzzer Claude Code Feature Audit

**Date**: 2026-02-19T13:16:35Z
**Git Commit**: 9f6a89a
**Branch**: RoyalPineapple/diverse-fuzz-tests
**Repository**: beirut

## Research Question

How is the AI fuzzer set up in terms of Claude Code features? What are the differences between skills, agents, and commands? Is the current distribution of features the most effective?

## Summary

The fuzzer uses **3 of the 6** available Claude Code customization mechanisms: slash commands (6 files in `.claude/commands/`), a SKILL.md persona file, and MCP server configuration. It does **not** use custom subagents, `.claude/rules/` files, or skill directory structure with supporting files. The current architecture works, but there are structural mismatches between what each Claude Code feature is designed for and how the fuzzer deploys them.

## Claude Code Feature Taxonomy

| Feature | What It Controls | Invoked By | Context Isolation |
|---------|-----------------|------------|-------------------|
| **CLAUDE.md** | Persistent instructions/memory loaded at session start | Auto-loaded | None (system prompt) |
| **`.claude/rules/`** | Modular topic-specific rules, can be scoped to file patterns | Auto-loaded | None (system prompt) |
| **Skills** (SKILL.md dirs) | Reusable prompts/workflows; can include supporting files in the directory | User (`/name`) or Claude (auto) | Optional (`context: fork`) |
| **Subagents** (`.claude/agents/`) | Specialized delegated tasks with own context, tools, model, memory | Claude (delegation) | Always (own context window) |
| **Commands** (`.claude/commands/`) | Legacy prompt templates; now treated as skills internally | User (`/name`) | None (inline) |
| **`.mcp.json`** | External tool servers | Auto-connected at startup | Per-server process |
| **`settings.local.json`** | Permissions, hooks, model config | Auto-loaded | None (config) |

**Key distinctions:**

- **Commands** are single-file prompt templates. They're now treated as skills internally — identical in behavior. Limitations: no supporting file directory, no `context: fork`.
- **Skills** are directories with a SKILL.md plus supporting files (templates, scripts, references). They support `context: fork` for subagent execution, `user-invocable: false` for background knowledge, and `disable-model-invocation` to prevent auto-triggering.
- **Subagents** run in their own context window. They can have restricted tools, different models (Haiku for speed/cost), persistent cross-session memory, and preloaded skills. They cannot spawn child subagents.

## Current Fuzzer Architecture

### What exists today

| Feature | Files | Role |
|---------|-------|------|
| **SKILL.md** | `ai-fuzzer/SKILL.md` (564 lines) | Agent persona — the fuzzer's entire operating brain |
| **Commands** | 6 files in `ai-fuzzer/.claude/commands/` | `/fuzz`, `/fuzz-explore`, `/fuzz-map-screens`, `/fuzz-report`, `/fuzz-reproduce`, `/fuzz-stress-test` |
| **MCP config** | `ai-fuzzer/.mcp.json` | Configures `buttonheist` MCP server (stdio transport) |
| **Permissions** | `ai-fuzzer/.claude/settings.local.json` | Pre-approves all 17 MCP tools, enables all project MCP servers |
| **References** | 11 files in `ai-fuzzer/references/` | Strategy files, value dictionaries, patterns, examples, troubleshooting, nav graph, trace format, simulator docs, screen intent catalog |
| **Session data** | `ai-fuzzer/fuzz-sessions/` (gitignored) | Session notes + trace files (agent's external memory) |
| **Reports** | `ai-fuzzer/reports/` | Generated findings reports |

### Data flow during a session

1. Claude Code reads `.mcp.json` → spawns MCP server
2. `settings.local.json` → pre-approves all tool calls
3. SKILL.md is the active agent persona throughout
4. User invokes `/fuzz` (or other command) → command prompt loaded
5. Command reads `references/nav-graph.md` (persistent cross-session state)
6. Command reads `references/strategies/[name].md` (strategy-specific guidance)
7. During fuzzing: reads `references/screen-intent.md` and `references/interesting-values.md` on demand
8. Writes session notes every 5 actions, trace entries every 3-5 actions
9. At session end: merges new discoveries into `references/nav-graph.md`

### What's NOT used

| Feature | Available Since | Not Used |
|---------|----------------|----------|
| **Custom subagents** (`.claude/agents/`) | Claude Code v2+ | No subagents defined |
| **`.claude/rules/`** | Claude Code v2+ | No rules files |
| **Skill directories** | Claude Code v2.1.3 | SKILL.md exists but commands are in `.claude/commands/`, not `.claude/skills/` |
| **`context: fork`** | Claude Code v2.1.3 | No forked skill execution |
| **Persistent subagent memory** | Claude Code v2+ | Not used — nav-graph.md serves this role manually |

## How Features Map to Current Usage

### SKILL.md (564 lines) — Agent Persona

The SKILL.md is the project's **top-level identity file**. It defines:
- Black-box observer constraint
- Core loop (OBSERVE → IDENTIFY INTENT → PLAN → EXECUTE → RECORD)
- Delta interpretation rules
- Navigation planning algorithm
- Session notes format and update protocol
- Coverage metrics
- Crash detection protocol
- Finding severity levels and format
- Observable invariants (6)
- Screen intent recognition
- Novelty/variation directives
- Strategy system overview
- Element scoring heuristics
- Back navigation decision tree
- Error recovery delegation

At 564 lines, it contains both **stable identity** (who the fuzzer is, its invariants, its operating constraints) and **operational procedures** (session notes format, trace protocol, navigation algorithm). These are two different concerns.

### Commands — Session Workflows

Each command is a step-by-step workflow for a specific fuzzing activity:

| Command | Lines | Arguments | Purpose |
|---------|-------|-----------|---------|
| `/fuzz` | 194 | strategy, max iterations | Full autonomous fuzzing loop with refinement |
| `/fuzz-explore` | 137→149 | none | Deep-dive on current screen |
| `/fuzz-map-screens` | 145 | none | Build navigation graph |
| `/fuzz-stress-test` | 166 | element or "all" | Rapid-fire stability testing |
| `/fuzz-report` | 144 | none | Generate report from session notes |
| `/fuzz-reproduce` | 168 | finding ID | Replay trace to verify reproducibility |

Commands reference SKILL.md by section name (e.g., "see 'Screen Intent Recognition' in SKILL.md") and read reference files by explicit path (e.g., `references/strategies/[name].md`).

### Reference Files — Supporting Knowledge

11 reference files serve different roles:

**Read during fuzzing (by commands)**:
- `references/nav-graph.md` — read/write every session (persistent state)
- `references/strategies/*.md` — read at session start
- `references/screen-intent.md` — read per new screen
- `references/interesting-values.md` — read per text field
- `references/trace-format.md` — read when creating trace files
- `references/troubleshooting.md` — read on errors

**Background knowledge (not explicitly read by commands)**:
- `references/action-patterns.md` — composable interaction templates
- `references/examples.md` — MCP response interpretation examples

**Human-only reference**:
- `references/simulator-lifecycle.md` — setup commands
- `references/simulator-snapshots.md` — snapshot management

## Architecture Observations

### The fuzzer operates as a single-context agent

Everything runs in one conversation context: the SKILL.md persona, the command's step-by-step workflow, and all reference file reads. There's no context isolation — a 500-action `/fuzz` session accumulates all reference material, session notes, trace entries, and tool call results in the same context window. This is why the session notes mechanism exists: it's a manual external-memory system to survive context compaction.

### Commands are de facto skills without the directory structure

The 6 command files in `.claude/commands/` are treated as skills by Claude Code internally. But they don't leverage skill features:
- No supporting file directory (references live in `references/`, not alongside the command)
- No `context: fork` for isolated execution
- No `disable-model-invocation` / `user-invocable` control
- No `allowed-tools` restrictions in frontmatter

### SKILL.md plays a dual role

SKILL.md functions as both:
1. **Agent identity** (who the fuzzer is, what it can observe, what invariants it checks)
2. **Operational manual** (session notes format, trace protocol, navigation algorithm, update frequency rules)

In the Claude Code feature model, the identity part naturally belongs in SKILL.md, while the operational procedures could be split into reference files or rules.

### Reference files are an ad-hoc knowledge base

The `references/` directory is a custom convention — Claude Code has no special handling for it. Files are read because commands explicitly say "read `references/X.md`". Two reference files (`action-patterns.md` and `examples.md`) are never explicitly read by any command — they're background knowledge that relies on SKILL.md's instructions being in context for the agent to know they exist.

### nav-graph.md is manual persistent memory

`references/nav-graph.md` serves the role that Claude Code's subagent persistent memory feature (`memory: project`) was designed for: accumulating knowledge across sessions. Currently it's managed manually by command instructions that say "read at start, merge at end."

## Code References

- `ai-fuzzer/SKILL.md` — Agent persona (564 lines)
- `ai-fuzzer/.claude/commands/fuzz.md` — Main fuzzing command (194 lines)
- `ai-fuzzer/.claude/commands/fuzz-explore.md` — Screen explorer (149 lines)
- `ai-fuzzer/.claude/commands/fuzz-map-screens.md` — Navigation mapper (145 lines)
- `ai-fuzzer/.claude/commands/fuzz-stress-test.md` — Stress tester (166 lines)
- `ai-fuzzer/.claude/commands/fuzz-report.md` — Report generator (144 lines)
- `ai-fuzzer/.claude/commands/fuzz-reproduce.md` — Finding reproducer (168 lines)
- `ai-fuzzer/.mcp.json` — MCP server config
- `ai-fuzzer/.claude/settings.local.json` — Permission allowlist
- `ai-fuzzer/references/` — 11 reference files (strategies, values, patterns, examples, troubleshooting, nav graph, trace format, simulator docs, screen intent)

## Related Research

- `thoughts/shared/research/2026-02-12-ai-fuzzing-framework-research.md`
- `thoughts/shared/research/2026-02-17-fuzzer-skills-guide-evaluation.md`
- `thoughts/shared/research/2026-02-17-fuzzing-beyond-randomness.md`
- `thoughts/shared/research/2026-02-19-pr-review-ai-fuzz-framework.md`

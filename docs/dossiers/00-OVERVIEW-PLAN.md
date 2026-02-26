# Overview - Performance Improvement Plan

## Keep Dossiers in Repo

- [ ] **Add dossier maintenance section to `CLAUDE.md`** — instruct agents to keep `docs/dossiers/` up to date when making architectural changes

## Code Philosophy (Applies to ALL Crew Members)

These principles override any existing shortcuts in the codebase:

1. **No linter suppressions.** If code doesn't pass linting, fix the code. Remove every `swiftlint:disable` in the codebase. The purpose of constraints is to produce better code.

2. **Use real Swift 6 concurrency.** No `@unchecked Sendable` with manual locks. No `@MainActor` where it doesn't belong. Leverage the concurrency system properly — actors, structured concurrency, `Sendable` checking.

3. **Use language-provided solutions.** Don't roll our own when Swift/Foundation provides the answer, regardless of how tricky the official approach is to get right.

## Cross-Cutting Concerns to Address

Each of these should be resolved as part of the relevant crew member's plan:

| # | Concern | Owner | Plan File |
|---|---------|-------|-----------|
| 1 | Documentation drift (API.md, WIRE-PROTOCOL.md) | TheScore + InsideJob | `07-THESCORE-PLAN.md` |
| 2 | Duplicate error types (FenceError vs CLIError) | TheFence + CLI | `10-THEFENCE-PLAN.md` |
| 3 | Inconsistent timeouts | TheFence | `10-THEFENCE-PLAN.md` |
| 4 | `vendorid` TXT key ghost | Wheelman | `08-WHEELMAN-PLAN.md` |
| 5 | Token logged in plaintext | InsideJob | **ACCEPTED** — useful for programmatic connection |
| 6 | No InsideJob unit tests | InsideJob | `01-INSIDEJOB-PLAN.md` |
| 7 | USBDeviceDiscovery blocks main thread | Wheelman | `08-WHEELMAN-PLAN.md` |
| 8 | Interaction log payload unbounded | Stakeout + TheScore | `04-STAKEOUT-PLAN.md` |

## Crew Roster (Post-Improvement)

| Current Name | New Name | Role |
|-------------|----------|------|
| InsideJob | InsideJob | Message dispatch + crew wiring (thin coordinator) |
| TheMuscle | TheMuscle | Auth + session locking |
| TheSafecracker | TheSafecracker | Pure touch injection (fingers only) |
| Stakeout | TheStakeout | Screen recording pipeline |
| Fingerprints | TheFingerprints | Visual touch overlay |
| ThePlant | ThePlant | ObjC auto-start bridge |
| TheScore | TheScore | Shared wire protocol types |
| Wheelman | TheWheelman | All networking (TCP, Bonjour, USB) |
| TheClient | **TheMastermind** | Observable session orchestrator (SwiftUI API) |
| TheMastermind | **TheFence** | Command dispatch for CLI/MCP |
| *(new)* | **TheBagman** | Element storage + UI observation + screen capture |
| ButtonHeistCLI | ButtonHeistCLI | CLI (watch mode removed) |
| ButtonHeistMCP | ButtonHeistMCP | MCP server |

## Implementation Order

Plans sorted by dependency chain — earlier batches must complete before later ones can start. Plans within a batch can be parallelized.

### Batch 1: Self-Contained (no dependencies)

| Plan | Complexity | Notes |
|------|-----------|-------|
| **06-THEPLANT** | Trivial (2 files) | Replace `@_cdecl` with `@objc`. Zero entanglement. |
| **07-THESCORE** Phase 3 only | Low (1 file) | Fix `ElementAction` Codable edge case. Isolated fix. |

### Batch 2: Core Infrastructure (unblocks everything)

These are the foundations that most other plans depend on. Can be worked in parallel, but each has internal phase ordering.

| Plan | Complexity | Unblocks | Shared File Coordination |
|------|-----------|----------|--------------------------|
| **02-THEMUSCLE** Phases 1-5 | Medium-high (8 phases, major rewrite) | InsideJob Phase 2, TheWheelman Phase 6 | `TheMuscle.swift` with Plan 01 Phase 2 |
| **08-WHEELMAN** | High (7 phases, actor rewrite) | Plans 09, 10 (discovery/connection APIs), Plan 01 Phase 1 | `InsideJob.swift` with Plan 01 |
| **05-FINGERPRINTS** | Low-medium (5 phases) | Plan 04 Phase 2 (compositing removal) | `Fingerprints.swift` with Plan 04 |

### Batch 3: The Big Extraction

InsideJob's three extraction phases. Must be done sequentially within the plan, and coordinates with Batches 2 results.

| Plan | Complexity | Depends On | Shared File Coordination |
|------|-----------|------------|--------------------------|
| **01-INSIDEJOB** Phase 1 | Medium | Plan 08 Phase 5 (Wheelman receives networking) | Joint work with Plan 08 |
| **01-INSIDEJOB** Phase 2 | Medium | Plan 02 Phase 6 (TheMuscle receives subscriptions) | Joint work with Plan 02 |
| **01-INSIDEJOB** Phase 3 | High | Phases 1-2 complete | Creates TheBagman — unblocks Plan 03 |
| **01-INSIDEJOB** Phases 4-6 | Low | Phase 3 complete | Cleanup and linter fixes |

### Batch 4: Consumers of TheBagman + TheFingerprints

These plans consume the new types and guarantees created in Batches 2-3.

| Plan | Complexity | Depends On | Shared File Coordination |
|------|-----------|------------|--------------------------|
| **03-THESAFECRACKER** | Medium (6 phases) | Plan 01 Phase 3 (TheBagman exists) | `TheSafecracker+Elements.swift` deletion shared with Plan 01 |
| **04-STAKEOUT** + **07-THESCORE** Phase 2 | Medium (coordinated) | Plan 05 Phase 2 (min display time) | `ServerMessages.swift` — same change, do together |

### Batch 5: The Name Swap (atomic)

**Critical:** Plans 09 and 10 must be implemented as a single atomic commit. TheClient → TheMastermind cannot happen while the name TheMastermind is still in use by the old type.

| Plan | Complexity | Depends On |
|------|-----------|------------|
| **09-THECLIENT** + **10-THEFENCE** | High (combined 13 phases, cascading rename) | Plan 08 (TheWheelman APIs exist for discovery/connection move) |

### Batch 6: Outer Layer

Depend on TheFence existing and the rename being complete.

| Plan | Complexity | Depends On | Shared File Coordination |
|------|-----------|------------|--------------------------|
| **11-CLI** | Low (4 phases, 2 deletions) | Plan 10 (FenceError exists) | `DeviceConnector.swift` — same change as Plan 10 Phase 4 |
| **12-MCP** | Low (4 phases) | Plan 10 (TheFence exists) | `main.swift` — version constant with Plan 11 |

### Batch 7: Documentation

| Plan | Complexity | Notes |
|------|-----------|-------|
| **00-OVERVIEW** | Trivial | CLAUDE.md addition. Do last so it reflects the final state. |
| **07-THESCORE** Phase 5 | Low | Update API.md + WIRE-PROTOCOL.md. Do last since 3 other plans also touch these docs. |

## Shared File Conflicts (Resolve Together)

These file conflicts mean the listed plans should be done in the same PR or in immediate sequence:

| File | Plans | Resolution |
|------|-------|-----------|
| `InsideJob.swift` | 01, 03, 04, 05, 08 | Plan 01 owns. Others consume after extraction. |
| `TheMuscle.swift` | 01 Phase 2, 02 Phase 6 | Do together — subscriptions move is one action. |
| `ServerMessages.swift` | 04 Phase 4, 07 Phase 2 | Plan 04 owns. Plan 07 acknowledges ("per Stakeout plan"). |
| `DeviceConnector.swift` | 10 Phase 4, 11 Phase 2 | Plan 10 owns. Plan 11 acknowledges ("per TheFence plan"). |
| `ActionCommandTests.swift` | 07 Phase 4, 11 Phase 3 | Identical change — whichever lands first satisfies both. |
| `docs/WIRE-PROTOCOL.md` | 02, 07, 09 | Do in Batch 7 after all protocol changes are settled. |
| `InsideJob+AutoStart.swift` | 01 Phase 5, 06 Phase 1 | Plan 06 first (trivial), Plan 01 Phase 5 after. |

## CLAUDE.md Addition

Add the following to CLAUDE.md:

```markdown
## Dossier Maintenance

Crew member dossiers live in `docs/dossiers/`. When a PR changes a crew member's responsibilities, adds/removes types, or changes architecture:
- Update the relevant dossier file
- Update `00-OVERVIEW.md` if module dependencies change
- Keep diagrams current
```

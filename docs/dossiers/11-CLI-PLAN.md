# ButtonHeistCLI - Performance Improvement Plan

## Summary

Remove watch mode. Fix all flagged items. Consolidate error types.

## Phase 1: Remove Watch Mode

**Decision:** Remove watch mode entirely. Session mode covers the same use case.

- [x] **Delete `CLIRunner.swift`**
- [x] **Delete `WatchCommand.swift`**
- [x] **Remove watch command registration** from `main.swift`
- [x] **Remove dead `CLIOptions` struct** from `main.swift`
- [x] **Remove dead `ExitCode` enum** from `CLIUtilities.swift`
- [x] **Build passes** after phase

## Phase 2: Fix `CLIError` Duplication

Per TheFence plan (`10-THEFENCE-PLAN.md`): delete `CLIError`, use `FenceError` everywhere.

- [x] **Replace `CLIError` references** in `DeviceConnector.swift` with `FenceError` (done by Batch 5)
- [x] **Delete `CLIError` definition** (done by Batch 5)
- [x] **Build passes** after phase

## Phase 3: Fix Test Issues

- [x] **Remove leading space in import** (`ActionCommandTests.swift:3`)
- [x] **Add `.typeText` test case** (done by Batch 4B)
- [x] **Add `.editAction` test case** (done by Batch 4B)
- [x] **Add `.resignFirstResponder` test case** (done by Batch 4B)
- [x] **Add `.waitForIdle` test case** (done by Batch 4B)
- [x] **Tests pass**

### Files affected:
- `ButtonHeistCLI/Tests/ActionCommandTests.swift`

## Phase 4: Consider `--timeout` Flag

Low priority — only implement if users request it.

- [x] **Evaluate adding `--timeout` to `ConnectionOptions`** for per-invocation override
  - **Decision:** Deferred. Individual commands already have per-command `--timeout` flags (e.g. `ActionCommand` defaults to 10s). `DeviceConnector` already accepts `discoveryTimeout` and `connectionTimeout`. A global override adds no clear value.

## Verification

- [x] Watch mode removed (CLIRunner.swift and WatchCommand.swift deleted)
- [x] `CLIError` deleted, using `FenceError`
- [x] All `ActionMethod` cases tested
- [x] Import formatting fixed
- [x] CLI builds: `cd ButtonHeistCLI && swift build -c release`

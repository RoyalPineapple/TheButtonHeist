# ButtonHeistCLI - Performance Improvement Plan

## Summary

Remove watch mode. Fix all flagged items. Consolidate error types.

## Phase 1: Remove Watch Mode

**Decision:** Remove watch mode entirely. Session mode covers the same use case.

- [ ] **Delete `CLIRunner.swift`**
- [ ] **Delete `WatchCommand.swift`**
- [ ] **Remove watch command registration** from `main.swift`
- [ ] **Build passes** after phase

## Phase 2: Fix `CLIError` Duplication

Per TheFence plan (`10-THEFENCE-PLAN.md`): delete `CLIError`, use `FenceError` everywhere.

- [ ] **Replace `CLIError` references** in `DeviceConnector.swift` with `FenceError`
- [ ] **Delete `CLIError` definition** (if not already done by TheFence plan)
- [ ] **Build passes** after phase

## Phase 3: Fix Test Issues

- [ ] **Remove leading space in import** (`ActionCommandTests.swift:3`)
- [ ] **Add `.typeText` test case** (`ActionCommandTests.swift:488-512`)
- [ ] **Add `.editAction` test case**
- [ ] **Add `.resignFirstResponder` test case**
- [ ] **Add `.waitForIdle` test case**
- [ ] **Tests pass**

### Files affected:
- `ButtonHeistCLI/Tests/ActionCommandTests.swift`

## Phase 4: Consider `--timeout` Flag

Low priority — only implement if users request it.

- [ ] **Evaluate adding `--timeout` to `ConnectionOptions`** for per-invocation override

## Verification

- [ ] Watch mode removed (CLIRunner.swift and WatchCommand.swift deleted)
- [ ] `CLIError` deleted, using `FenceError`
- [ ] All `ActionMethod` cases tested
- [ ] Import formatting fixed
- [ ] CLI builds: `cd ButtonHeistCLI && swift build -c release`

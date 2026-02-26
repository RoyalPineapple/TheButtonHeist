# TheMastermind → TheFence - Performance Improvement Plan

## Summary

Rename to **TheFence**. Strip out duplicated networking/session logic. Fix the massive dispatch method. Eliminate duplicate error types. Add tests.

## Phase 1: Rename to TheFence

**Decision:** Rename to **TheFence**. The name "TheMastermind" is freed for TheClient (see `09-THECLIENT-PLAN.md`).

- [ ] **Rename `TheMastermind.swift` → `TheFence.swift`**
- [ ] **Rename `MastermindCommandCatalog.swift` → `CommandCatalog.swift`**
- [ ] **Rename `MastermindResponse` → `FenceResponse`**
- [ ] **Rename `MastermindError` → `FenceError`**
- [ ] **Update all references** in CLI, MCP, tests, docs
- [ ] **Build passes** after phase

## Phase 2: Remove Duplicated Networking/Session Logic

- [ ] **Move auto-discovery** (`start()`, discovery loop) → TheWheelman
- [ ] **Move auto-reconnect** (60-attempt loop) → TheWheelman
- [ ] **Move connection timeout loops** → TheWheelman
- [ ] **TheFence keeps:** command dispatch, response formatting, arg parsing helpers
- [ ] **Build passes** after phase

## Phase 3: Fix the Dispatch Method

**Problem:** 320-line switch with `swiftlint:disable cyclomatic_complexity function_body_length`.

- [ ] **Extract `handleGetInterface(args)`**
- [ ] **Extract `handleGetScreen(args)`**
- [ ] **Extract `handleGesture(command, args)`** for tap/long_press/swipe/drag/pinch/rotate/etc.
- [ ] **Extract `handleAccessibilityAction(command, args)`** for activate/increment/decrement/custom
- [ ] **Extract remaining command handlers**
- [ ] **Switch becomes thin router** (under 50 lines)
- [ ] **Remove `swiftlint:disable`**
- [ ] **Build passes** after phase

## Phase 4: Eliminate Duplicate Error Types

- [ ] **Delete `CLIError` definition**
- [ ] **Update `DeviceConnector.swift`** to use `FenceError`
- [ ] **Build passes** after phase

## Phase 5: Standardize Timeouts

- [ ] **Define named timeout constants:**
   ```swift
   enum Timeouts {
       static let action: UInt64 = 15_000_000_000
       static let longAction: UInt64 = 30_000_000_000
       static let interfaceRequest: UInt64 = 10_000_000_000
   }
   ```
- [ ] **Document why they differ**
- [ ] **Build passes** after phase

## Phase 6: Fix `requestInterface` Continuation Pattern

- [ ] **Replace custom `withCheckedThrowingContinuation`** with standard `waitFor*` pattern
- [ ] **TheFence asks TheWheelman/session** for interface via async API
- [ ] **Build passes** after phase

## Phase 7: Add Tests

- [ ] **Argument parsing tests** — `stringArg`, `intArg`, `doubleArg` coercion
- [ ] **Response formatting tests** — `humanFormatted()` and `jsonDict()` for all cases
- [ ] **Command routing tests** — each command routes to right handler
- [ ] **Error case tests** — unknown command, missing required args
- [ ] **Tests pass**

### Files:
- New: `ButtonHeist/Tests/ButtonHeistTests/TheFenceTests.swift`

## Verification

- [ ] Type renamed to TheFence throughout codebase
- [ ] `CLIError` deleted
- [ ] `swiftlint:disable` removed from dispatch method
- [ ] Dispatch method under 50 lines (thin router)
- [ ] Auto-discovery/reconnect delegated to TheWheelman
- [ ] Timeout constants named and documented
- [ ] Unit tests for arg parsing and response formatting
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`

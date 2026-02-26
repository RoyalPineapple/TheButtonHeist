# TheMastermind → TheFence - Performance Improvement Plan

## Summary

Rename to **TheFence**. Strip out duplicated networking/session logic. Fix the massive dispatch method. Eliminate duplicate error types. Add tests.

## Phase 1: Rename to TheFence

**Decision:** Rename to **TheFence**. The name "TheMastermind" is freed for TheClient (see `09-THECLIENT-PLAN.md`).

- [x] **Rename `TheMastermind.swift` → `TheFence.swift`**
- [x] **Rename `MastermindCommandCatalog.swift` → `CommandCatalog.swift`**
- [x] **Rename `MastermindResponse` → `FenceResponse`**
- [x] **Rename `MastermindError` → `FenceError`**
- [x] **Update all references** in CLI, MCP, tests, docs
- [x] **Build passes** after phase

## Phase 2: Remove Duplicated Networking/Session Logic

- [ ] **Move auto-discovery** (`start()`, discovery loop) → TheWheelman
- [ ] **Move auto-reconnect** (60-attempt loop) → TheWheelman
- [ ] **Move connection timeout loops** → TheWheelman
- [ ] **TheFence keeps:** command dispatch, response formatting, arg parsing helpers
- [ ] **Build passes** after phase

> **Deferred:** Overlaps with Plan 09 Phases 2-3 (move discovery/connection to TheWheelman). Should be done together to avoid double-move.

## Phase 3: Fix the Dispatch Method

**Problem:** 320-line switch with `swiftlint:disable cyclomatic_complexity function_body_length`.

- [x] **Extract `handleGetInterface(args)`**
- [x] **Extract `handleGetScreen(args)`**
- [x] **Extract `handleGesture(command, args)`** for tap/long_press/swipe/drag/pinch/rotate/etc.
- [x] **Extract `handleAccessibilityAction(command, args)`** for activate/increment/decrement/custom
- [x] **Extract remaining command handlers**
- [x] **Switch becomes thin router** (under 50 lines)
- [x] **Remove `swiftlint:disable`**
- [x] **Build passes** after phase

## Phase 4: Eliminate Duplicate Error Types

- [x] **Delete `CLIError` definition**
- [x] **Update `DeviceConnector.swift`** to use `FenceError`
- [x] **Build passes** after phase

## Phase 5: Standardize Timeouts

- [x] **Define named timeout constants:**
   ```swift
   enum Timeouts {
       static let action: UInt64 = 15_000_000_000
       static let longAction: UInt64 = 30_000_000_000
       static let interfaceRequest: UInt64 = 10_000_000_000
   }
   ```
- [x] **Document why they differ**
- [x] **Build passes** after phase

## Phase 6: Fix `requestInterface` Continuation Pattern

- [x] **Replace custom `withCheckedThrowingContinuation`** with standard `waitFor*` pattern
- [x] **TheFence asks TheMastermind** for interface via `waitForInterface()` async API
- [x] **Build passes** after phase

## Phase 7: Add Tests

- [x] **Response formatting tests** — `humanFormatted()` and `jsonDict()` for key cases
- [x] **Command routing tests** — help, quit execute correctly
- [x] **Error case tests** — missing command field, FenceError descriptions
- [x] **Timeout constants tests**
- [x] **Tests pass**

### Files:
- New: `ButtonHeist/Tests/ButtonHeistTests/TheFenceTests.swift`

## Verification

- [x] Type renamed to TheFence throughout codebase
- [x] `CLIError` deleted
- [x] `swiftlint:disable` removed from dispatch method
- [x] Dispatch method under 50 lines (thin router)
- [ ] Auto-discovery/reconnect delegated to TheWheelman (deferred — see Phase 2 note)
- [x] Timeout constants named and documented
- [x] Unit tests for response formatting and error cases
- [x] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`

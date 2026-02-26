# TheClient → TheMastermind - Performance Improvement Plan

## Summary

Rename TheClient to **TheMastermind**. Audit responsibilities — it's doing too much, mixing network coordination, observable state, async waits, and display logic. Slice it into focused pieces.

## Phase 1: Rename to TheMastermind

**Decision:** Rename to **TheMastermind**. The old TheMastermind type is being renamed to TheFence (see `10-THEFENCE-PLAN.md`), freeing this name.

- [ ] **Rename `TheClient.swift` → `TheMastermind`** class
- [ ] **Update all references** in ButtonHeist framework, CLI, MCP, tests, docs
- [ ] **Build passes** after phase

## Phase 2: Move Device Discovery to TheWheelman

**Current:** TheClient owns `DeviceDiscovery` and wraps it with `startDiscovery()` / `stopDiscovery()`.

- [ ] **Move `DeviceDiscovery` ownership** to TheWheelman
- [ ] **Move `discoveredDevices` management** to TheWheelman
- [ ] **Move `isDiscovering` state** to TheWheelman
- [ ] **TheMastermind observes** TheWheelman's discovery results as `@Observable` state
- [ ] **Build passes** after phase

### Files affected:
- `TheClient.swift` — remove discovery ownership
- Wheelman types — expose discovery API

## Phase 3: Move Connection Management

- [ ] **Move connection lifecycle** (connect/disconnect) → TheWheelman
- [ ] **Move keepalive pings** → TheWheelman
- [ ] **Decide auto-subscribe ownership** → TheMuscle or TheMastermind
- [ ] **TheMastermind keeps:** `@Observable` connection state, callback API, thin `send()` passthrough
- [ ] **Build passes** after phase

## Phase 4: Fix `didResume` Race Condition

**Bug:** `waitForActionResult`, `waitForScreen`, `waitForRecording` use `var didResume = false` accessed from both MainActor callback and potentially off-MainActor timeout Task.

- [ ] **Add `@MainActor` to timeout Task** in `waitForActionResult`
- [ ] **Add `@MainActor` to timeout Task** in `waitForScreen`
- [ ] **Add `@MainActor` to timeout Task** in `waitForRecording`
- [ ] **Build passes** after phase

## Phase 5: Remaining Responsibilities Audit

After Phases 2-3, what's left forms a coherent "observable session view" type:

- [ ] **Verify Observable state** (`@Observable`) — connection state, interface, screen, server info
- [ ] **Verify async wait methods** — `waitForActionResult`, `waitForScreen`, `waitForRecording`
- [ ] **Verify display name disambiguation** — `displayName(for:)`
- [ ] **Verify callback API** — `onConnected`, `onInterfaceUpdate`, etc.
- [ ] **Confirm TheMastermind is the SwiftUI-friendly API surface**

## Phase 6: Fix Keepalive Interval Documentation

- [ ] **Update WIRE-PROTOCOL.md** — document actual 3s interval (not 30s)
- [ ] **Or update code** to match docs — but 3s is more appropriate for 30s lease

## Verification

- [ ] Type renamed to TheMastermind throughout codebase
- [ ] Device discovery owned by TheWheelman, not TheMastermind
- [ ] Connection lifecycle owned by TheWheelman
- [ ] `didResume` race fixed with `@MainActor` on timeout Tasks
- [ ] WIRE-PROTOCOL.md keepalive interval matches implementation
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build`

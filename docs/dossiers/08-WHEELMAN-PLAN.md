# Wheelman → TheWheelman - Performance Improvement Plan

## Summary

Rename. Rewrite SimpleSocketServer with Swift 6 strict concurrency. Fix USB discovery. Absorb networking code from InsideJob. Consider Bonjour broadcast behavior during sessions.

## Phase 1: Rename to TheWheelman

- [ ] **Rename module references** throughout codebase and documentation
- [ ] **Build passes** after phase

## Phase 2: Rewrite SimpleSocketServer with Swift 6 Concurrency

**Goal:** Replace `@unchecked Sendable` + `NSLock` with proper Swift concurrency primitives.

- [ ] **Convert `SimpleSocketServer` to `actor`** — remove manual locking
- [ ] **Actor-isolate all mutable state** (`connections`, `authenticatedClients`, `messageTimes`)
- [ ] **Use `AsyncStream` or structured concurrency** for connection handling
- [ ] **Fix listener semaphore timeout** → `withCheckedThrowingContinuation`
- [ ] **Fix rate limiting** → actor-isolated state
- [ ] **No `@unchecked Sendable`** anywhere in Wheelman
- [ ] **Build passes** after phase

### Files affected:
- `SimpleSocketServer.swift` — full rewrite as actor

## Phase 3: Fix USB Discovery

- [ ] **Move subprocess execution to background context** — no main thread blocking
- [ ] **Consider making `USBDeviceDiscovery` an actor**
- [ ] **Check GitHub issues for USB reliability** and address
- [ ] **Build passes** after phase

### Files affected:
- `USBDeviceDiscovery.swift`

## Phase 4: Remove `vendorid` Ghost

- [ ] **Check if `vendorIdentifier` is used anywhere downstream**
- [ ] **Remove `vendorid` read from `DeviceDiscovery.swift:64,68`** (if unused)
- [ ] **Remove `vendorIdentifier` from `DiscoveredDevice`** (if unused)
- [ ] **Build passes** after phase

## Phase 5: Absorb Server-Side Networking from InsideJob

- [ ] **Create `ServerTransport` type** (or integrate into actor-based `SimpleSocketServer`)
- [ ] **Move Bonjour `NetService` setup** from InsideJob
- [ ] **Move port binding and advertisement** from InsideJob
- [ ] **Provide message callbacks** to InsideJob
- [ ] **Build passes** after phase

### Files affected:
- New or modified Wheelman types
- `InsideJob.swift` — delegates to Wheelman for transport

## Phase 6: Bonjour Broadcast Behavior During Sessions

- [ ] **Add `sessionactive` key to TXT record**
- [ ] **TheWheelman updates TXT record** when TheMuscle reports session state changes
- [ ] **Build passes** after phase

## Phase 7: Add Tests for Discovery

- [ ] **`DeviceDiscovery` TXT record parsing tests**
- [ ] **`USBDeviceDiscovery` subprocess output parsing tests**
- [ ] **`DiscoveredDevice` matching/filtering tests**
- [ ] **Tests pass**

### Files:
- Expand `ButtonHeist/Tests/WheelmanTests/`

## Verification

- [ ] Module renamed to TheWheelman
- [ ] `SimpleSocketServer` is an `actor`, no `@unchecked Sendable`, no `NSLock`
- [ ] USB discovery does not block main thread
- [ ] `vendorid` ghost resolved
- [ ] Bonjour TXT record includes session state
- [ ] No `swiftlint:disable` in Wheelman files
- [ ] Tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme WheelmanTests test`

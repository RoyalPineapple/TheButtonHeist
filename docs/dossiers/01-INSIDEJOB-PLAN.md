# InsideJob - Performance Improvement Plan

## Summary

InsideJob is doing too much. The plan is to extract responsibilities into focused types, leaving InsideJob as a thin coordinator that wires the crew together.

## Phase 1: Extract Networking to Wheelman

- [ ] **Move TCP server code to Wheelman** — `SimpleSocketServer` creation, port binding, `advertiseService()` logic
- [ ] **Move Bonjour code** — `NetService` setup and TXT record publishing
- [ ] **Move `wireServer()` callback bridging**
- [ ] **InsideJob receives a "server handle"** from Wheelman and passes it message handlers
- [ ] **Remove dead `shouldBindToLoopback`** computed property
- [ ] **Build passes** after phase

### Files affected:
- `InsideJob.swift` — remove server setup, Bonjour code, `shouldBindToLoopback`
- `Wheelman/` — new type to encapsulate server-side networking
- Remove dead `shouldBindToLoopback` computed property entirely

## Phase 2: Extract Client Subscriptions to TheMuscle

- [ ] **Move `subscribedClients: Set<String>`** to TheMuscle
- [ ] **Move subscribe/unsubscribe handling** to TheMuscle
- [ ] **Move `broadcastToSubscribed` helper** to TheMuscle
- [ ] **InsideJob delegates** "broadcast this data to subscribers" to TheMuscle
- [ ] **Build passes** after phase

### Files affected:
- `InsideJob.swift` — remove `subscribedClients`, subscribe/unsubscribe cases delegate to TheMuscle
- `TheMuscle.swift` — add subscription tracking alongside auth tracking

## Phase 3: Extract TheBagman

**Goal:** Create **TheBagman** — the crew member who holds and manipulates the mcguffin (the buttons). TheBagman owns the full lifecycle of the heist's target: reading the UI, storing element references, computing diffs, detecting animations, and capturing visual state.

### What TheBagman owns:

**Element storage & safe access (from TheVault concept):**
- [ ] `interactiveObjects: [Int: WeakObject]` — weak references to live accessibility objects
- [ ] `resolveElement(target:) -> (HeistElement, ActivationPoint)?` — safe lookup
- [ ] `activate(at:)`, `increment(at:)`, `decrement(at:)`, `customAction(name:at:)` — all accessibility actions
- [ ] Live object pointers NEVER leave TheBagman
- [ ] Element resolution logic from `TheSafecracker+Elements.swift` moved here
- [ ] `ElementStore` protocol replaced with concrete `TheBagman` type

**UI observation (from TheLookout concept):**
- [ ] **Window enumeration:** `getTraversableWindows()`
- [ ] **Accessibility parsing:** `refreshAccessibilityData()`, `convertElement()`, `traitNames()`, `computeDelta()`, `snapshotElements()`, `convertHierarchyNode()`
- [ ] **Animation detection:** `hasActiveAnimations()`, `waitForAnimationsToSettle()`, `actionResultWithDelta()`
- [ ] **Screen capture:** `captureScreen()`, `captureScreenForRecording()`, `captureActionFrame()`

- [ ] **TheBagman.swift created** with all above responsibilities
- [ ] **Build passes** after phase

### What stays in InsideJob:
- Message dispatch (the switch statement)
- Polling orchestration (`InsideJob+Polling.swift`)
- Recording start/stop handlers (delegates to TheStakeout)
- Wiring the crew together on init

### Files affected:
- New file: `TheBagman.swift`
- `TheSafecracker+Elements.swift` — delete, element resolution moves to TheBagman
- `TheSafecracker+Actions.swift` — receives coordinates from TheBagman
- `InsideJob+Accessibility.swift` → all methods move to TheBagman
- `InsideJob+Animation.swift` → all methods move to TheBagman
- `InsideJob+Screen.swift` → capture methods move to TheBagman
- `InsideJob+Polling.swift` → calls TheBagman instead of `self`
- Remove `ElementStore` protocol

## Phase 4: Fix Medium Priority Items

- [ ] **Remove `shouldBindToLoopback`** — delete the dead computed property
- [ ] **Name the magic nanosecond literals:**
   ```swift
   private static let debounceInterval: UInt64 = 300_000_000  // 300ms
   private static let defaultPollingInterval: UInt64 = 1_000_000_000  // 1s
   ```
- [ ] **Add unit tests** for delta computation (extractable from UIKit via TheBagman)

## Phase 5: Fix Low Priority Items

- [ ] **Fix singleton** — `InsideJob.shared` should be a `let`, second `configure()` is no-op or assert
- [ ] **Keep TCP teardown/resume** on background/foreground — correct iOS behavior

## Phase 6: Remove `handleClientMessage` Linter Suppression

- [ ] **Break switch into grouped handlers** if still complex after Phases 1-3
- [ ] **Remove `swiftlint:disable`** — code must pass linting

## Verification

- [ ] All `swiftlint:disable` removed from InsideJob files
- [ ] InsideJob.swift under 200 lines (currently ~400)
- [ ] Delta computation has unit tests
- [ ] `ElementStore` protocol deleted
- [ ] `shouldBindToLoopback` deleted
- [ ] Singleton not replaceable
- [ ] TheBagman owns all element storage, observation, animation detection, and screen capture
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build`

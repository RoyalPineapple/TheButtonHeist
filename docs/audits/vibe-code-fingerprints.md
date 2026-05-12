# Vibe-code fingerprints — audit

Scope: structural fingerprints of agent-written code that don't earn their keep. Targets `.swift` files in `ButtonHeist/Sources/`, `ButtonHeist/Tests/`, `ButtonHeistCLI/Sources/`, `ButtonHeistMCP/Sources/` (228 files).
Date: 2026-05-12.
Audit-only — no source changes. Findings that the existing SwiftLint rules (`agent_callback_bridge_task`, `agent_unannotated_callback`, `agent_unchecked_sendable_no_comment`, `agent_main_actor_value_type`) already enforce are excluded.

## Summary by category

| Shape | Findings | Severity profile |
|-------|---------:|------------------|
| 1. Defensive optionality (state-as-optional) | 7 | 3 high, 3 medium, 1 low |
| 2. Single-conformer protocols | 0 | — (both `DeviceConnecting` and `DeviceDiscovering` have 2+ production conformers) |
| 3. Hedge comments | 5 | 0 high, 4 medium, 1 low |
| 4. Caches doing function work | 2 | 1 medium, 1 low |
| 5. Task bridge anti-patterns the lint regex misses | 10+ | 3 high, ~7 medium |
| 6. Adapter/converter types between near-identical types | 1 cluster | 1 medium |
| 7. `Result<T, E>` with impossible cases | 0 | — (every `Result` in production uses `Result<T, Error>`) |
| 8. `default: fatalError("can't happen")` / cousins | 1 | 1 medium |
| Bonus: docstring restating signature | 1 cluster (~9 sites) | 1 low |
| Bonus: `// MARK: -` followed by 1 declaration | 2 in one file | 1 low |
| Bonus: test-scaffolding `Box<T>: @unchecked Sendable` | 5 sites | 1 low |
| Bonus: `_ = self` to silence unused-self warning | 1 | 1 low |
| Bonus: entry/exit logging | 2 | 1 low |
| Bonus: stored `_` / unused init params | 0 | — |

Total: **34 individual findings** across **8 shapes** (plus bonuses).

The lint rules already cover the highest-volume cases (single-line `Task { @MainActor in self.foo(...) }`, `var on*` without isolation, unjustified `@unchecked Sendable`). Everything below is what slipped past.

---

## Shape 1 — Defensive optionality

`var foo: Foo? = nil` set later in a phase that the type doesn't model. Each is a hidden state machine.

### 1.1 — `TheInsideJob._shared` (high)

`ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:22`

```swift
private static var _shared: TheInsideJob?
```

The "configured / not configured" boolean encoded as nullable storage. Set-only-once enforced at runtime in `configure(...)` with a `if _shared != nil { warning }` (lines 38-41). CLAUDE.md says: "Prefer making impossible states unrepresentable over guarding against them at runtime." Either the singleton is lazy (`static let shared = TheInsideJob()`) and there is no configure-after-create concern, or `configure` returns the instance and `shared` is the only way to mutate.

### 1.2 — `TheInsideJob.idleTimerBaseline` (high)

`ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:90`

```swift
private var idleTimerBaseline: Bool?
```

Used as a "have we engaged idle-timer protection?" sentinel (lines 557-568). Two-state machine encoded as `Bool?`: `nil` = not engaged, non-nil = engaged with the prior baseline value. Should be `enum IdleTimerProtection { case off, engaged(baseline: Bool) }` per CLAUDE.md "Explicit State Machines".

### 1.3 — `ReachabilityResolver` continuation+pendingResult pair (high)

`ButtonHeist/Sources/TheButtonHeist/TheHandoff/DiscoveredDevice.swift:282-284`

```swift
private final class ReachabilityResolver {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var pendingResult: Bool?
```

Two optionals co-varying to encode three states: `(nil, nil)` idle, `(c, nil)` waiting, `(nil, x)` resolved-but-no-awaiter. Canonical "two fields = state machine" smell flagged in CLAUDE.md (Explicit State Machines, third rule). Should be `enum State { case idle, awaiting(CheckedContinuation<Bool, Never>), resolved(Bool) }`.

### 1.4 — `ActiveSession.heistRecording` (medium)

`ButtonHeist/Sources/TheButtonHeist/TheBookKeeper/TheBookKeeper.swift:31`

```swift
struct ActiveSession: @unchecked Sendable {
    ...
    var heistRecording: HeistRecording?
}
```

A session is in one of two phases: heist-recording or not. The optional encodes that phase. Could be lifted into `enum SessionPhase { case active(ActiveSession), recording(ActiveSession, HeistRecording) }`, or `ActiveSession` could split into two case-specific structs and become an associated value on `phase`.

### 1.5 — `TheBrains.lastSentState` (medium)

`ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains.swift:271`

```swift
private(set) var lastSentState: SentState?
```

`nil` means "never sent" — every read site has to guard for it. The state machine has exactly two phases (pre-first-send vs sending) and could be `enum BroadcastHistory { case fresh, sent(SentState) }`, or `SentState` could carry an `initial` sentinel.

### 1.6 — `TheGetaway.completedRecording` (medium)

`ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway.swift:37`

```swift
var completedRecording: Result<RecordingPayload, Error>?
```

Triply-nullable: `nil` (no recording), `.success(...)` (recorded), `.failure(...)` (failed). The "no recording yet" state should be its own enum case — and combined with the active recording, this is really a recording-lifecycle state machine that needs an explicit type.

### 1.7 — `TheFence.lastActionResult` (low)

`ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift:820`

```swift
var lastActionResult: ActionResult?
```

Mostly innocuous — only read for display. Worth a glance but lowest priority of the set.

---

## Shape 2 — Single-conformer protocols

**No findings.** Both `DeviceConnecting` and `DeviceDiscovering` have multiple production conformers (`DeviceConnection`, plus `DeviceDiscovery` / `USBDeviceDiscovery`). CLAUDE.md's "Mocking Strategy" rule justifies the protocols even if they had only one production conformer each, but they don't, so the question is moot.

---

## Shape 3 — Hedge comments

Comments that admit "this case can happen but we're papering over it." Each one is either an honest miss (delete the comment, write the case) or a tell that the prior author didn't trust the structure.

### 3.1 — "Defensive — tests reuse `wireTransport`" (medium)

`ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway.swift:122-124`

```swift
// Cancel any prior consumer (defensive — a single transport instance
// is only wired once in production, but tests reuse `wireTransport`).
eventConsumerTask?.cancel()
```

Production says "this never happens", tests force it to. The fact that tests need to call it twice means the production single-call assumption is brittle. Either `wireTransport` is idempotent (then the comment is wrong, the cancel is correct, and the docstring should say "idempotent: cancels any prior consumer"), or it's not (then production has the same bug as tests, just masked).

### 3.2 — "Defensive — a fresh connect should..." (medium)

`ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift:136`

```swift
// Tear down any prior consumer (defensive — a fresh connect should
```

Same shape as 3.1. The cancel should either be the documented public contract ("connect is idempotent — prior in-flight consumer is cancelled") or removed because the precondition is enforced elsewhere.

### 3.3 — "Defensive: parser produced an element with no heistId" (medium)

`ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift:141`

```swift
// Defensive: parser produced an element with no heistId — emit
```

If the parser can do this, it's part of the contract; document it on the parser. If it can't, delete the guard. Worth checking which it is.

### 3.4 — "Defensive: if every window is a passthrough..." (medium)

`ButtonHeist/Tests/TheInsideJobTests/TheTripwireTests.swift:890`

```swift
// Defensive: if every window is a passthrough, fall back to the full
```

In tests this one is a labeled assumption — but the production code being tested has the same fallback. Either the fallback is the canonical path (rename, don't apologize for it), or it's a recovery path for an impossible case (delete).

### 3.5 — "Should never happen on supported iOS versions" (low)

`ButtonHeist/Sources/TheInsideJob/TheSafecracker/KeyboardBridge.swift:22`

```swift
/// selector is missing (should never happen on supported iOS versions).
```

This is a docstring on the ObjC runtime bridge. The "should never happen" hedge is fine here — the iOS runtime can in fact change — but the code should fail loudly (it does), so the comment is just documentation. Lowest priority.

---

## Shape 4 — Caches doing function work

### 4.1 — `TheFence.lastInterfaceCache` (medium)

`ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence.swift:174`

```swift
private var lastInterfaceCache: [String: HeistElement] = [:]
```

Used in `recordHeistEvidence`, `elementDisappeared` expectation checks, and a few diagnostic paths (read at 405, 521, 528; written at 542-544, 576-578, 634). The cache exists because TheFence doesn't trust `actionTracker`/`interfaceTracker` to remember the last interface for downstream consumers. Question: can the most recent `Interface` value live on the relevant tracker (or in `playbackPhase`) instead of being a separate stored mirror? If yes, this stored property is duplication. If no — i.e. the cache really does survive across actions in a way the trackers don't — then the comment at line 172 needs to say "this is the only durable post-action interface snapshot" rather than "Cached interface elements".

### 4.2 — `TheStash.wireTree` / `wireTreeHash` (low)

`ButtonHeist/Sources/TheInsideJob/TheStash/TheStash.swift:476-482`

```swift
func wireTree() -> [InterfaceNode] {
    WireConversion.toWireTree(from: currentScreen)
}
func wireTreeHash() -> Int {
    wireTree().hashValue
}
```

Not a stored cache — but every caller computes the tree twice if they need both the value and the hash. Worth checking whether call sites memoize, or whether this should return `(tree, hash)` to avoid the second walk.

---

## Shape 5 — Task bridge anti-patterns the lint regex misses

CLAUDE.md's `agent_callback_bridge_task` rule matches only single-line `Task\s*\{\s*@MainActor\s+in\s+self\.\w+\(...\)\s*\}`. The multi-line variant, the `[weak self]` variant, and the network-queue (non-@MainActor) variant all slip through.

### 5.1 — `TheGetaway.wireTransport` — multi-line @MainActor callbacks (high)

`ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway.swift:93-101`

```swift
let onAuthenticated: @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void = { [weak self] clientId, respond in
    Task { @MainActor [weak self] in
        self?.handleClientConnected(clientId, respond: respond)
    }
}
let onSessionActiveChanged: @Sendable (Bool) -> Void = { [weak self] isActive in
    Task { @MainActor [weak self] in
        self?.transport?.updateTXTRecord([TXTRecordKey.sessionActive.rawValue: isActive ? "1" : "0"])
    }
}
```

Two callback-to-Task bridges, multi-line so the regex misses them. Same anti-pattern: no handle, no cancellation, no ordering guarantee. Should be expressed by annotating the callbacks' isolation in their declared closure types (in `TheMuscle.installCallbacks`) and calling directly.

### 5.2 — `TheMuscle.showApprovalAlert` — bridge inside a bridge (high)

`ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift:711-725`

```swift
private func showApprovalAlert(clientId: Int) {
    let presenter = alerts
    Task { @MainActor [weak self] in
        presenter.presentApproval(
            clientId: clientId,
            onAllow: { [weak self] in
                Task { await self?.approveClient(clientId) }
            },
            onDeny: { [weak self] in
                Task { await self?.denyClient(clientId) }
            }
        )
        _ = self
    }
}
```

Three nested unstored Tasks. The outer one is a `[weak self]` variant of the lint-flagged shape (so it slips). The inner `Task { await self?.approveClient(...) }` ones are fire-and-forget actor hops. And the comment-explained `_ = self` is a workaround for an unused-self warning that signals the design problem rather than fixing it. Replace the alert callbacks with `@ButtonHeistActor`-typed closures so they can be called directly.

### 5.3 — `TheInsideJob.handlePulseTransition` (high)

`ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:291-296`

```swift
private func handlePulseTransition(_ transition: TheTripwire.PulseTransition) {
    if case .settled = transition, getaway.hierarchyInvalidated {
        let getaway = self.getaway
        Task { await getaway.broadcastIfChanged() }
    }
}
```

Unstored Task on a hot pulse-transition path. If broadcast falls behind, multiple in-flight Tasks pile up. Either serialize through an actor mailbox or store the handle on `pollingPhase`.

### 5.4 — `SimpleSocketServer` — fire-and-forget from NWConnection callbacks (medium)

`ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer.swift:158, 220, 341, 350, 357, 360, 362, 426, 437, 487, 497`

Eleven sites of `Task { await self.foo(...) }` from `NWListener` / `NWConnection` callbacks, none stored. The actor handoff is the point — but the lack of a stored handle means none of these can be cancelled when `stop()` runs. On listener teardown, in-flight removes/sends still fire against a torn-down server.

Example (line 158):

```swift
newListener.newConnectionHandler = { [weak self] connection in
    guard let self else { return }
    Task { await self.handleNewConnection(connection) }
}
```

If the server has stopped between `newConnectionHandler` firing and the Task running, `handleNewConnection` runs against `.stopped` and the guards inside are doing the work the handle should have. Track these via a `Set<Task<Void, Never>>` and cancel on `stop()`.

### 5.5 — `TheGetaway.broadcastHierarchyIfChanged` mid-function task (medium)

`ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway.swift:426-427`

```swift
if let stakeout {
    Task { await stakeout.noteScreenChange() }
}
```

Single unstored Task in a hot path. Each broadcast spawns one. CLAUDE.md "Task Lifetime Tracking" applies.

### 5.6 — `TheMuscle.makeReleaseTimer` / `sessionReleaseTimeout` task (medium)

`ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift:631-635`

```swift
Task { [weak self, sessionReleaseTimeout] in
    guard await Task.cancellableSleep(for: .seconds(sessionReleaseTimeout)) else { return }
    guard !Task.isCancelled else { return }
    await self?.releaseSession()
}
```

Returned and stored at the call site (per the function name) — so this is OK only if every caller stores it. Worth confirming `makeReleaseTimer`'s callers always assign to a tracked field.

### 5.7 — `AutoStart.start()` (medium)

`ButtonHeist/Sources/TheInsideJob/Lifecycle/AutoStart.swift:71-87`

```swift
Task { @MainActor in
    autoStartLogger.debug("MainActor task executing...")
    ...
    try await TheInsideJob.shared.start()
    TheInsideJob.shared.startPolling(interval: interval)
    ...
}
```

Auto-start fires a Task and forgets. If the app starts and immediately shuts down (suspend/resign during launch), the start runs against a terminated lifecycle. Acceptable because auto-start is one-shot at process start, but worth converting to `Task.detached` with a documented "fire at launch, never tracked" rationale, or storing on a dedicated `AutoStart` actor that owns the handle.

### 5.8 — `pendingResult: Bool?` resolver — see Shape 1.3

The `Box<T>` test resolvers (Shape "Bonus" below) are the test-side equivalent of the same problem.

---

## Shape 6 — Adapter/converter types between near-identical types

### 6.1 — `WireConversion` / `TheStash.toWire` facade chain (medium)

`ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift:73, 112, 119, 128`
`ButtonHeist/Sources/TheInsideJob/TheStash/TheStash.swift:465-477`

`AccessibilityElement` (parser) → `convert` → `HeistElement` (wire), then `ScreenElement` (internal, wraps `AccessibilityElement` + `heistId`) → `toWire` → `HeistElement`. The chain currently has three layers:

1. `WireConversion.convert(_ element: AccessibilityElement) -> HeistElement`
2. `WireConversion.toWire(_ entry: ScreenElement) -> HeistElement` (wraps `convert` + adds heistId)
3. `TheStash.toWire(_ entry: ScreenElement) -> HeistElement` (calls 2 with no other work)

And the same for the plural array overloads. `TheStash`'s `toWire` overloads add zero behavior over `WireConversion.toWire`. Either fold the call sites to go straight to `WireConversion` (and delete the facade), or — if the facade is for actor-isolation reasons — document that and consolidate `ScreenElement` / `HeistElement` so the conversion is a single named step rather than a three-name chain.

The CLAUDE.md "Currency Types: Elements and Targets" section explicitly names this: "Do not create wrapper structs, snapshot types, or intermediate representations to hold subsets of these types." `ScreenElement` is a wrapper of `AccessibilityElement + heistId` that arguably violates this rule — but only audit it; the conversion-by-facade is the cheaper fix.

---

## Shape 7 — `Result<T, E>` with impossible cases

**No findings.** Every `Result` in production uses `Result<T, Error>` (the `Error` existential), never a domain-specific Error type with impossible cases. The four authoritative error types from CLAUDE.md (`ServerError`, `ConnectionError`, `FenceError`, `BookKeeperError`) are all thrown, not wrapped in `Result`.

---

## Shape 8 — `default: fatalError("can't happen")` / cousins

### 8.1 — `NetDeltaAccumulator.preconditionFailure("guarded above")` (medium)

`ButtonHeist/Sources/TheButtonHeist/TheFence/NetDeltaAccumulator.swift:42-52`

```swift
precondition(
    !postDeltas.contains(where: \.isScreenChanged),
    "post-screen-change slice must not contain another screen change"
)
let postDeltas = postDeltas.filter { delta in
    switch delta {
    case .noChange(let payload): return !payload.transient.isEmpty
    case .elementsChanged: return true
    case .screenChanged:
        preconditionFailure("guarded above")
    }
}
```

This is the canonical "I just proved this case can't happen with a precondition, but the type system doesn't know" smell. The fix is to make the input type exclude `.screenChanged` — e.g. an `enum NonScreenChangeDelta` that the caller constructs, with the precondition becoming a compile-time-enforced type narrowing. The cheap form: pass `[ElementsChangedPayload]` instead of `[InterfaceDelta]` and convert at the boundary.

No `default: fatalError` / `default: break "shouldn't happen"` found in production. The seven `fatalError` calls in source (excluding tests) are all `init(coder:)` NSCoder boilerplate in `TestApp/` — fine.

---

## Bonus shapes

### B1 — `MARK: -` followed by a single declaration (low)

`ButtonHeist/Sources/TheInsideJob/Server/AlertPresenter.swift:20-26`

```swift
// MARK: - Properties

private weak var presentedAlert: UIAlertController?

// MARK: - Init

init() {}
```

Two single-declaration MARK sections in a row inside the same 80-line file. Inline both — the section ceremony is heavier than the code.

### B2 — Test-scaffolding `Box<T>: @unchecked Sendable` (low)

`ButtonHeist/Tests/TheInsideJobTests/TheStakeoutTests.swift:12`
`ButtonHeist/Tests/TheInsideJobTests/TheMuscleTests.swift:14, 146`
`ButtonHeist/Tests/TheInsideJobTests/TheGetawayTests.swift:219`
`ButtonHeist/Tests/TheInsideJobTests/WaitForIntegrationTests.swift:37`
`ButtonHeist/Tests/ButtonHeistTests/AuthFailureTests.swift:11`

Five+ test files define a `private final class Box: @unchecked Sendable { ... var items: [T] = []; let lock = NSLock() }` test scaffold. Each is its own one-off with a `// swiftlint:disable:this agent_unchecked_sendable_no_comment` and a paragraph of justification. CLAUDE.md hints at the cleanup: "could be replaced with `nonisolated(unsafe)` or just a `@MainActor` shared instance." A shared test helper (`TestObservationBox<T>` in `ButtonHeistTests/TestSupport`) would consolidate the justification into one comment and eliminate the per-file lint-disables.

### B3 — `_ = self` to silence unused-self warning (low)

`ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift:721-724`

```swift
// Silence the unused-self warning: `self` is captured to anchor
// the alert presentation to TheMuscle's lifetime, but the alert
// outlives the immediate scope through `presenter`.
_ = self
```

This is a hack to keep `[weak self]` in the capture list without using `self` in the body. The reasoning ("anchor the alert presentation to TheMuscle's lifetime") doesn't hold — `weak self` *cannot* anchor anything; that's what weak means. Either capture nothing (you don't need `self`), or capture `self` strongly and document the lifetime extension, or move the alert outside this Task entirely (see Shape 5.2). The `_ = self` is the trail of an argument that didn't finish.

### B4 — Docstrings restating the function name (low)

`ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift:111, 118, 125`
`ButtonHeist/Sources/TheScore/HeistPlayback.swift:139, 229`

```swift
/// Convert a ScreenElement to its wire representation.
static func toWire(_ entry: ScreenElement) -> HeistElement {

/// Convert a snapshot to wire format. Use at serialization boundaries.
static func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
```

The signature already says "ScreenElement → HeistElement". The docstring adds zero info. CLAUDE.md "DocC Documentation" says explicitly: "Do NOT document properties where the type and name say it all." Same rule applies to functions whose signature is the documentation.

### B5 — Entry/exit logging boilerplate (low)

`ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:395, 402`

```swift
insideJobLogger.info("App entering background, suspending server")
...
insideJobLogger.info("App entering foreground, resuming server")
```

These are paired entry-log statements describing the function the runtime is calling. The lifecycle phase change is already captured by `serverPhase` transitions; the log is paraphrasing the call. Either log the *transition* (with both old and new phase) at the point `serverPhase` is mutated, or drop these.

---

## Recommendations

One sentence per cluster:

1. **Defensive optionality (7):** convert each `var foo: Foo?` to an explicit phase enum where `Foo` is the non-empty associated value of the active case — `_shared`, `idleTimerBaseline`, `ReachabilityResolver`, and `heistRecording` are the highest-leverage; the others can wait.
2. **Single-conformer protocols (0):** no action.
3. **Hedge comments (5):** either delete the comment + guard (case can't happen) or promote the guard to documented contract (case is part of the API); the four "Defensive — tests do X" comments in production code are the priority.
4. **Caches doing function work (2):** confirm whether `lastInterfaceCache` duplicates state already kept by `playbackPhase`/trackers, and consider returning `(tree, hash)` from `wireTree`/`wireTreeHash` to avoid the double walk.
5. **Task bridge anti-patterns (10+):** the lint regex needs widening (multi-line, `[weak self]`-prefixed, non-`@MainActor`) and the existing offenders need to either annotate callbacks' isolation in their closure types (Shapes 5.1, 5.2) or store and cancel the Task on lifecycle exit (Shapes 5.3-5.5, 5.7).
6. **Adapter/converter clusters (1):** drop the `TheStash.toWire` facades and route call sites directly to `WireConversion`; flag `ScreenElement` for follow-up audit against the "Currency Types" rule.
7. **`Result<T, impossible>` (0):** no action.
8. **`default: fatalError` cousins (1):** narrow `NetDeltaAccumulator`'s post-screen-change input type so the impossible case isn't representable.
9. **Single-declaration MARK / docstring restates / entry-exit logs / `_ = self` / per-file Box (B1-B5):** consolidate `Box<T>` into a shared test helper, delete docstrings that restate signatures, delete the entry-exit pair in `TheInsideJob` (or move to a single phase-transition log), inline the AlertPresenter single-prop MARKs, and resolve the `_ = self` workaround by fixing the underlying lifetime model.

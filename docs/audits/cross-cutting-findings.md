# Cross-cutting integration audit

Scope: post-0.2.23 cleanup batch (Programs 1a/1b/1c/1d/2/3/4).
Date: 2026-05-11.

## Summary

Eleven findings, all narrowly scoped: 0 critical, 7 recommended, 4 optional. The two big-ticket items are (1) `handleStartRecording` has a multi-`await` TOCTOU that lets a second `start_recording` interleave between the phase check and the phase write, orphaning a `TheStakeout` instance; and (2) the lint rule `agent_unannotated_public_callback` is `public`-only, so internal callbacks installed on `@ButtonHeistActor`-isolated types compile without isolation annotations and rely on the reader to know the class isolation rule. Recording-bug-pattern hunt came back clean — every wire-message arm in `DeviceConnection.handleMessage` and `TheHandoff.handleServerMessage` now delegates correctly to the broadcast/callback path post #348. Recommendation: land all recommended findings as small follow-up PRs after 0.2.24 ships; none gate the release.

## Findings

### Finding 1: `handleStartRecording` TOCTOU between phase check and phase write
**Severity:** recommended
**Scope:** State-machine coherence across actor boundaries (audit area 3)
**Location:** `ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway+Recording.swift:16-48`
**Description:** Line 17 reads `recordingPhase`, lines 30 and 41 each suspend on actor hops to `TheStakeout`, and line 42 writes `recordingPhase = .recording(stakeout: recorder)`. Between the read and the write there are two `await` points. If a second `start_recording` command arrives while the first is suspended on `await recorder.startRecording`, the second can re-enter `handleStartRecording`, observe `recordingPhase == .idle` (the first hasn't written yet), construct a second `TheStakeout`, and race to write. Result: one `TheStakeout` instance is orphaned but its `onRecordingComplete` is still wired through `[weak self]` to `deliverRecordingResult`, which will reset `recordingPhase = .idle` and broadcast a `.recording(payload)` from the wrong session.
**Recommended fix:** Either (a) write a sentinel phase like `.starting` synchronously before the first `await`, or (b) move the `if case .recording` check after `recorder.startRecording` succeeds and treat a non-idle phase at write time as the canonical conflict signal. Option (a) is simpler.

### Finding 2: `agent_unannotated_public_callback` lint rule has internal-callback blind spot
**Severity:** recommended
**Scope:** CLAUDE.md rule vs reality (audit area 4)
**Location:** `.swiftlint.yml:126-130`; counter-examples at `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceConnection.swift:92,94`, `ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery.swift:111`, `ButtonHeist/Sources/TheButtonHeist/TheHandoff/USBDeviceDiscovery.swift:23`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift:156`, `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheSafecracker.swift:112`
**Description:** The rule regex `public\s+var\s+on\w+:\s*\(\([^)]*\)\s*->\s*Void\)\?` matches only `public` callbacks. Post-#353 demotions, the canonical `onEvent` / `onSend` / `onTransition` etc. callbacks are all `internal`, so the rule no longer covers them. They compile correctly because the enclosing class carries `@ButtonHeistActor` and the closure inherits that isolation, but the CLAUDE.md spirit ("isolation lives in the closure type, not in a docstring or class-level inference") is violated for every internal callback in the codebase. None of these were flagged because the rule's `public` keyword filter exists.
**Recommended fix:** Drop `public` from the regex (`var\s+on\w+:\s*\(\([^)]*\)\s*->\s*Void\)\?`), then annotate the ~7 affected internal callbacks (`(@ButtonHeistActor (...) -> Void)?`). Alternatively, document the convention "callbacks on `@ButtonHeistActor`-isolated types omit the annotation because the class isolation propagates" in CLAUDE.md and keep the rule public-only.

### Finding 3: `recordAndBroadcast` triple-hops `TheStakeout` for one logical interaction
**Severity:** recommended
**Scope:** Actor × callback × Task-lifetime (audit area 1) plus state-machine coherence (audit area 3)
**Location:** `ButtonHeist/Sources/TheInsideJob/TheGetaway/TheGetaway.swift:373-380`
**Description:** Three sequential awaits on `stakeout`: `await stakeout.isRecording`, `await stakeout.recordingElapsed`, `await stakeout.recordInteraction(event:)`. Between any of these hops the stakeout can transition from `.recording` to `.finalizing` (e.g. the inactivity monitor fires `stopRecording`), and the interaction is silently dropped or — worse — the `recordingElapsed` is read from a stale session at the moment `isRecording` returned `true`. The current actor implementations no-op gracefully (`recordingElapsed` returns 0 and `recordInteraction` early-returns when not recording), so the behaviour is benign but undeclared.
**Recommended fix:** Add `func recordInteractionIfRecording(command:result:)` on `TheStakeout` that does the `isRecording` check, `recordingElapsed` read, and `recordInteraction` append in one actor-isolated method. Reduces 3 hops to 1, eliminates the TOCTOU.

### Finding 4: Fire-and-forget tearDown loses the Task handle
**Severity:** recommended
**Scope:** Task lifetime tracking (audit area 4)
**Location:** `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift:248` and `:421`
**Description:** `Task { await muscle.tearDown() }` spawned during `stop()` and `suspend()` is not stored or awaited. `tearDown()` cancels every `lockoutTasks` entry and dismisses the alert, but the calling site returns before `tearDown` finishes. If `stop()` is followed immediately by `start()`, the new actor instance has nothing to do with the old `lockoutTasks`, but the still-running tearDown completes asynchronously after the new server is up, which is a violation of the CLAUDE.md "Task lifetime tracking" rule. Production impact is small (the muscle instance is replaced, not reused), but it's exactly the pattern Program 2 wanted to root out.
**Recommended fix:** Convert `stop()` and `suspend()` to `async` and `await muscle.tearDown()` directly. There are no callers in synchronous-only contexts (every reasonable caller is already inside a Task or async function).

### Finding 5: Fire-and-forget Tasks in `ServerTransport` nonisolated bridges have no FIFO guarantee
**Severity:** recommended
**Scope:** Actor × callback × Task-lifetime (audit area 1)
**Location:** `ButtonHeist/Sources/TheInsideJob/Server/ServerTransport.swift:316-333` (`send`, `broadcastToAll`, `markAuthenticated`, `disconnect`)
**Description:** Each method spawns an unstructured `Task { [server] in await server.foo(...) }` and returns synchronously. Swift makes no FIFO guarantee for unstructured Tasks targeting the same actor — two `send(data, to: 7)` calls in a row may execute out of order. This is the same issue called out in the #352 review under "outbound message ordering" but lives one layer deeper, inside the nonisolated wrapper that `TheGetaway+TheMuscle` ultimately calls into. The `broadcastToSubscribed` for-loop on TheMuscle (line 277-281) iterates over clients and calls the `sendToClient` closure for each; with N subscribers, N independent Tasks are spawned with no inter-Task ordering.
**Recommended fix:** Make `ServerTransport.send` and `broadcastToAll` `async`. Update `TheMuscle.broadcastToSubscribed` to take an `async` send closure and `await` each call in the for-loop. This is the structural fix #352 deferred; it eliminates the FIFO race for both broadcasts and per-client sends.

### Finding 6: `dismissAlert` spawns an untracked `Task { @MainActor in ... }`
**Severity:** optional
**Scope:** Task lifetime tracking (audit area 4)
**Location:** `ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift:716-721`
**Description:** `dismissAlert` is called from `tearDown()` and `handleClientDisconnected`. It spawns a Task hopping to MainActor to call `presenter.dismiss()`. The Task handle is dropped. The presenter is captured strongly so the Task can complete even after TheMuscle deallocates. The CLAUDE.md "Task lifetime tracking" rule explicitly calls out this pattern. The behavioural impact is nil (the dismiss is idempotent and the presenter outlives any reasonable timing), so this is style-grade.
**Recommended fix:** Make `AlertPresenter.dismiss()` callable from any isolation context (it already is `@MainActor`); have `TheMuscle.dismissAlert` be `async` and `await alerts.dismiss()` directly, eliminating the bridge.

### Finding 7: `TheStakeout.onRecordingComplete` is mutable internal despite having a dedicated setter
**Severity:** optional
**Scope:** Callback isolation discipline / API hygiene (audit area 4)
**Location:** `ButtonHeist/Sources/TheInsideJob/TheStakeout/TheStakeout.swift:96`
**Description:** Property is declared `var onRecordingComplete: (@MainActor @Sendable (...) -> Void)?`. There is also a dedicated `setOnRecordingComplete(_:)` setter at line 140. Callers are supposed to use the setter (the actor isolation requires `await`), but nothing prevents an `await stakeout.onRecordingComplete = ...` assignment. Same shape was already noted in the #351 review's deferred follow-ups but has not been applied.
**Recommended fix:** Change to `private(set) var onRecordingComplete: ...` so callers must use `setOnRecordingComplete`.

### Finding 8: `SimpleSocketServer.ServerError` shares a name with `TheScore.ServerError`
**Severity:** optional
**Scope:** One error type per logical domain (audit area 4)
**Location:** `ButtonHeist/Sources/TheInsideJob/Server/SimpleSocketServer.swift:525` vs `ButtonHeist/Sources/TheScore/ServerMessages.swift:192`
**Description:** Two unrelated types share the name `ServerError`. The TheScore one is the wire payload broadcast to clients; the SimpleSocketServer one is internal lifecycle errors (`failedToBindPort`, `alreadyRunning`). They live in different modules and never collide in a single import scope (SimpleSocketServer is module-internal), but the CLAUDE.md "One Error Type Per Logical Domain" list (post-#354) does not mention `SimpleSocketServer.ServerError`. Either it should be added to the list as a per-module private error, or renamed (e.g. `SocketServerError`) to avoid the shared name.
**Recommended fix:** Rename to `SocketServerError` for clarity and consistency with the CLAUDE.md error-type policy. Cheap mechanical change.

### Finding 9: `TheStakeoutError` and `TLSIdentityError` are not enumerated in the CLAUDE.md error policy
**Severity:** optional
**Scope:** One error type per logical domain (audit area 4)
**Location:** `ButtonHeist/Sources/TheInsideJob/TheStakeout/TheStakeout.swift:75`, `ButtonHeist/Sources/TheInsideJob/Server/TLSIdentity.swift:347`
**Description:** CLAUDE.md lists 4 authoritative error types post-#354 (ServerError, ConnectionError, FenceError, BookKeeperError). `TheStakeoutError` and `TLSIdentityError` (both private module-internal) are not mentioned. Both genuinely cover distinct domains (recording lifecycle, TLS identity setup) and are correct to keep separate, but the policy section reads as exhaustive when it isn't. Same for `DisconnectReason` at `DeviceConnection.swift:19` — it's technically an Error but it's a value type observed via callback, not thrown.
**Recommended fix:** Update the CLAUDE.md "One Error Type Per Logical Domain" section to add a short "Per-module private errors auditable here:" footnote with the additional types and a one-line rationale for each.

### Finding 10: Switch over `ConnectionEvent` does not handle every case explicitly
**Severity:** optional
**Scope:** Recording-bug-pattern hunt (audit area 5)
**Location:** `ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff.swift:489-514`
**Description:** The DeviceConnection event handler in TheHandoff switches on event with explicit arms for `.transportReady`, `.connected`, `.disconnected`, `.message` — exhaustive today. No `default` arm. This is fine for now, but the original recording-bug pattern (#348) was a switch where one arm did a side effect without delegating to the common broadcast path. The current switch's `.transportReady` arm is `break` (no-op), which is the same shape: a discriminated case that does not delegate to a common path. Today that's correct, but if `.transportReady` ever needs to signal upstream (e.g. for a "discovered → ready" state), the `break` is the kind of thing the recording bug taught us to flag.
**Recommended fix:** None today. File as a watch item: every new `ConnectionEvent` case needs an explicit decision about whether it broadcasts to `onEvent`/`onDisconnected`/etc., not just an `assertNever` or `break`.

### Finding 11: `handleServerMessage` `.serverHello` and `.authRequired` deliberately drop messages
**Severity:** optional
**Scope:** Recording-bug-pattern hunt (audit area 5)
**Location:** `ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff.swift:583`
**Description:** `case .serverHello, .authRequired: break` in `handleServerMessage`. These two messages are the auth handshake that DeviceConnection consumes internally (auto-respond), so by the time TheHandoff sees them it has no work to do. But the recording bug was `case .pong: logger.debug(...)` followed by no further action — same shape: a wire case where the handler is a no-op. Today it's correct because the auth handshake is fully owned by DeviceConnection. If future work shifts auth responsibility upstream to TheHandoff (e.g. a re-auth flow), the `break` will silently swallow the message. Worth a one-line comment noting "intentional no-op, consumed in DeviceConnection".
**Recommended fix:** Add a `// Consumed by DeviceConnection.handleMessage — no upstream observer for these.` comment above the case so the intent is auditable.

## What was *not* found

I specifically checked for and did NOT find:

- **Test compile/run breakage from #353 demotions interacting with actor isolation.** `ButtonHeistTests` and `TheInsideJobTests` use `@testable import` correctly. Tests assign to actor-isolated state via the proper setter pattern (`await muscle.installCallbacks(...)`) — no property-assignment-of-isolated-state hangovers were found.
- **`@_spi` or convenience-init test-only workarounds** introduced since the #353 review's optional. Aside from the documented `convenience init()` already noted, no new escape hatches snuck in.
- **`Task { @MainActor in self.foo(...) }` single-line bridges** in production source. The `agent_callback_bridge_task` lint rule's regex turns up zero hits. The two `Task { @MainActor [weak self] in self?.handleClientConnected(...) }` patterns in `TheGetaway.swift:88-94` are multi-line and capture-protected, which is the right shape.
- **`@MainActor struct` or `@MainActor enum` declarations without justification.** Every match either disables the rule with a comment (`SyntheticTouch.swift`, `KeyboardBridge.swift`, etc.) or is a caseless namespace enum.
- **Double-fire `onDisconnected`** in `forceDisconnect`. `DeviceConnection.disconnect()` synchronously cancels the consumer Task and finishes the event continuation, so the explicit `onDisconnected?(.localDisconnect)` in `TheHandoff.forceDisconnect` is the only fire.
- **Recording-bug-pattern in `DeviceConnection.handleMessage`.** Post-#348 every arm except the deliberate handshake handlers (`.serverHello`, `.protocolMismatch`, `.error(authFailure)`, `.authRequired` when autoRespondToAuthRequired, `.authApproved`, `.sessionLocked`, `.info`) calls `onEvent?(.message(...))` either explicitly or via the `default` arm. The `.pong` arm now has both the diagnostic log and the broadcast.
- **`muscle.callback = ...` style test mocking** that would have broken when TheMuscle became an actor. Tests use `installCallbacks` exclusively.
- **`ConnectionFailure` references remaining post-#354.** Verified in the PR diff; consolidation looks complete except for `ConnectionPhaseTests.swift` which is rewritten in the same PR.

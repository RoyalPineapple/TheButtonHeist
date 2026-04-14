# Lifecycle

TheInsideJob extensions for server lifecycle — pulse-driven hierarchy updates, wait handlers, screen capture, and the ObjC auto-start bridge. All files are `extension TheInsideJob`.

## Files

**`Pulse.swift`** — Hierarchy broadcast.

`scheduleHierarchyUpdate()` sets `hierarchyInvalidated = true`. `handlePulseTransition(_:)` (wired to `tripwire.onTransition`) calls `broadcastIfChanged()` on `.settled` when invalidated.

`broadcastIfChanged()`: `brains.refresh()` → clear flag → guard subscribers → `brains.selectElements()` → `brains.toWire()` → hash → guard changed → update `brains.hierarchyHash` → convert tree → broadcast `Interface` → `broadcastScreen()` → `stakeout?.noteScreenChange()`.

`makePollingTask(interval:)`: loops `tripwire.waitForAllClear(timeout: interval)`, on settle calls `broadcastIfChanged()`. The continuous background update mechanism.

`sendInterface(requestId:respond:)`: settle 0.5s → `brains.refresh()` → `brains.exploreAndPrune()` → `brains.currentInterface()` → send → update `lastSentTreeHash`/`lastSentBeforeState`/`lastSentScreenId`.

---

**`Animation.swift`** — Wait handlers.

`handleWaitForIdle`: refresh → captureBeforeState → `tripwire.waitForAllClear(timeout)` → `brains.actionResultWithDelta(before:)`.

`handleWaitForChange`: two paths:
- **Fast path**: refresh, hash, compare against `lastSentTreeHash`. If already different and expectation met → return immediately.
- **Slow path**: poll in a `while < deadline` loop — `tripwire.waitForAllClear(1s)` → `brains.refresh()` → hash → if changed, compute delta via `brains.computeDelta(before:afterSnapshot:)` → evaluate expectation → return if met. Timeout → failure with `.timeout` errorKind.

---

**`Screen.swift`** — Screen capture and recording.

`handleScreen`: `brains.captureScreen()` → PNG-encode → `ScreenPayload` → send.

`handleStartRecording`: creates `TheStakeout`, wires `captureFrame` to `brains.captureScreenForRecording()` and `onRecordingComplete` to broadcast result and cleanup. Calls `recorder.startRecording(config:)`, sets `recordingPhase` and `brains.stakeout`.

---

**`AutoStart.swift`** — ObjC bridge.

`@_cdecl("TheInsideJob_autoStartFromLoad")` — called from ThePlant's `+load`. Reads config from env vars / Info.plist (`INSIDEJOB_DISABLE`, `INSIDEJOB_TOKEN`, `INSIDEJOB_PORT`, `INSIDEJOB_POLLING_INTERVAL`). Dispatches `Task { @MainActor }` to configure, start, and begin polling.

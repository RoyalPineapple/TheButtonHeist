# Settle Loop

The tripwire and the settle loop as cooperating mechanisms: TheTripwire watches UIKit timing signals on a display-link pulse, while SettleSession proves the accessibility tree stable by fingerprinting consecutive parses. This diagram makes "settled evidence" concrete — it answers "what exactly does Button Heist mean when it says the screen settled?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/HeistIdleTracker.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift`, `ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift`

```mermaid
stateDiagram-v2
    direction TB
    state "consecutiveCycles" as cycles
    state "post-idle fingerprint" as postIdle
    state "settled(timeMs:)" as settled
    state "timedOut(timeMs:)" as timedOut
    state "cancelled(timeMs:)" as cancelled

    [*] --> cycles : action delivered
    cycles --> cycles : fingerprint unchanged, quiet +1
    cycles --> cycles : fingerprint or tripwireSignal changed, reset
    cycles --> settled : 3 consecutive quiet cycles
    cycles --> timedOut : defaultTimeoutMs = 5000
    cycles --> cancelled : context cancelled

    state "animation count > 0" as animating
    state "main run loop BeforeWaiting" as runLoopIdle

    [*] --> animating : active heist settlement
    animating --> runLoopIdle : aggregate count reaches zero
    [*] --> runLoopIdle : count already zero
    runLoopIdle --> animating : animation started before idle edge
    runLoopIdle --> postIdle : idle edge with count still zero
    postIdle --> postIdle : fingerprint changed, replace baseline
    postIdle --> settled : fingerprint repeats next frame

    settled --> [*]
    timedOut --> [*]
    cancelled --> [*]
```

`post-idle fingerprint` shares the same `timedOut` and `cancelled` edges as
`consecutiveCycles`; they are drawn once to keep the picture readable. If the
private idle tracker is unavailable, active settlement falls back to the 60 ms
AX quiet-window policy. An idle wait that consumes the authored deadline stays
timed out.

The two clocks:

```mermaid
flowchart TD
    subgraph tripwire["TheTripwire — UIKit signals"]
        ANIMATION["heist-scoped UIViewAnimationState hooks<br/>one aggregate start/stop counter"]
        ANIMATION_IDLE["animation idle edge<br/>count 1 → 0"]
        RUN_LOOP_IDLE["CFRunLoopObserver<br/>beforeWaiting"]
        PULSE["CADisplayLink pulse<br/>default 10 Hz (BH_TRIPWIRE_PULSE_HZ)"]
        SIGNAL["TripwireSignal<br/>layer scan · VC identity · window stack"]
        ANIMATION --> ANIMATION_IDLE --> RUN_LOOP_IDLE
        PULSE --> SIGNAL
    end
    subgraph settle["SettleSession — AX tree"]
        PARSE["parse cycle every<br/>defaultCycleIntervalMs = 100"]
        FP["fingerprint complete hierarchy:<br/>paths · ordering · semantic facts · containers<br/>heist ids · first responder · coarse geometry"]
        PARSE --> FP
    end
    RUN_LOOP_IDLE -- "opens active AX parse;<br/>confirm once next frame" --> PARSE
    SIGNAL -- "signal change resets<br/>the settle baseline" --> PARSE
```

Notes:

- The fingerprint (`SettleTimeline.fingerprint(of:)`) hashes hierarchy paths and ordering, every stable element semantic fact, containers, heist-id assignments, first-responder identity, and coarse geometry. Volatile `value`, shape, and activation-point facts are **skipped for elements carrying `updatesFrequently`**, so clocks and progress bars cannot hold the screen "unsettled" forever.
- A clean result carries the exact final `InterfaceObservation`; the semantic stream admits that observation only while its tripwire signal and capture identity are still current. It never reacquires or reconstructs the parser sample after settlement.
- `SettleOutcome.timedOut` is explicitly unsettled: `didSettleCleanly` is `false` and the result reports `settled: false`. It is never passed off as stable.
- `cancelled` is the third outcome — the session was torn down mid-action, distinct from `timedOut` so the caller can short-circuit instead of continuing on a dead session.
- Constants live in `SettleSession`: `defaultCyclesRequired = 3`, `defaultCycleIntervalMs = 100`, `defaultTimeoutMs = 5_000`.

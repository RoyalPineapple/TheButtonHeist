# Settle Loop

The tripwire and the settle loop as cooperating mechanisms: TheTripwire watches UIKit timing signals on one display-link pulse, while SettleSession parses concurrently and accepts the first valid UIKit-idle or semantic-stability proof. This diagram makes "settled evidence" concrete — it answers "what exactly does Button Heist mean when it says the screen settled?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/UIKitIdleTracker.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift`, `ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift`

```mermaid
stateDiagram-v2
    direction TB
    state "consecutiveCycles" as cycles
    state "parse on every heartbeat" as parsing
    state "60 ms AX quiet window" as semanticQuiet
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
    state "shared CADisplayLink heartbeat" as heartbeat

    [*] --> parsing : active heist settlement
    parsing --> parsing : fingerprint changed
    parsing --> semanticQuiet : fingerprint unchanged
    semanticQuiet --> parsing : fingerprint or tripwireSignal changed
    semanticQuiet --> settled : unchanged for 60 ms
    parsing --> animating : animation start observed
    animating --> runLoopIdle : aggregate count reaches zero
    parsing --> runLoopIdle : count already zero after first heartbeat
    runLoopIdle --> animating : animation started before idle edge
    runLoopIdle --> heartbeat : idle edge with count still zero
    heartbeat --> settled : parse first future native-rate tick

    settled --> [*]
    timedOut --> [*]
    cancelled --> [*]
```

The active proof race shares the same `timedOut` and `cancelled` edges as
`consecutiveCycles`; they are drawn once to keep the picture readable. If the
private idle tracker is unavailable or a cosmetic animation repeats forever,
the 60 ms AX quiet-window proof can still settle. Both proofs use the single CADisplayLink heartbeat;
immediate demand boosts it from the ambient rate to the active screen maximum
until the next tick. An idle wait that consumes the authored deadline stays timed out.

The two clocks:

```mermaid
flowchart TD
    subgraph tripwire["TheTripwire — UIKit signals"]
        ANIMATION["runtime-installed UIViewAnimationState hooks<br/>lifecycle-wide aggregate counter"]
        ANIMATION_IDLE["animation idle edge<br/>count 1 → 0"]
        RUN_LOOP_IDLE["CFRunLoopObserver<br/>beforeWaiting"]
        PULSE["one CADisplayLink heartbeat<br/>ambient 10 Hz · immediate native maximum"]
        SIGNAL["TripwireSignal<br/>layer scan · VC identity · window stack"]
        ANIMATION --> ANIMATION_IDLE --> RUN_LOOP_IDLE
        PULSE --> SIGNAL
    end
    subgraph settle["SettleSession — AX tree"]
        PARSE["parse throughout animation<br/>on immediate heartbeat demand"]
        FP["fingerprint complete hierarchy:<br/>paths · ordering · semantic facts · containers<br/>heist ids · first responder · coarse geometry"]
        PARSE --> FP
    end
    RUN_LOOP_IDLE -- "admit first parse from an<br/>explicitly future heartbeat" --> PARSE
    PULSE --> PARSE
    SIGNAL -- "signal change resets<br/>the settle baseline" --> PARSE
```

Notes:

- The fingerprint (`SettleTimeline.fingerprint(of:)`) hashes hierarchy paths and ordering, every stable element semantic fact, containers, heist-id assignments, first-responder identity, and coarse geometry. Volatile `value`, shape, and activation-point facts are **skipped for elements carrying `updatesFrequently`**, so clocks and progress bars cannot hold the screen "unsettled" forever.
- A clean result carries the exact final `InterfaceObservation`; the semantic stream admits that observation only while its tripwire signal and capture identity are still current. It never reacquires or reconstructs the parser sample after settlement.
- `SettleOutcome.timedOut` is explicitly unsettled: `didSettleCleanly` is `false` and the result reports `settled: false`. It is never passed off as stable.
- `cancelled` is the third outcome — the session was torn down mid-action, distinct from `timedOut` so the caller can short-circuit instead of continuing on a dead session.
- Constants live in `SettleSession`: `defaultCyclesRequired = 3`, `defaultCycleIntervalMs = 100`, `defaultTimeoutMs = 5_000`.

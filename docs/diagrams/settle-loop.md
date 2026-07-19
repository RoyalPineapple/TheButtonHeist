# Settle Loop

The tripwire and the settle loop as cooperating mechanisms: TheTripwire watches UIKit timing signals on a display-link pulse, while SettleSession proves the accessibility tree stable by fingerprinting consecutive parses. This diagram makes "settled evidence" concrete — it answers "what exactly does Button Heist mean when it says the screen settled?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift`, `ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift`

```mermaid
stateDiagram-v2
    direction TB
    state "consecutiveCycles" as cycles
    state "quietWindow" as quiet
    state "settled(timeMs:)" as settled
    state "timedOut(timeMs:)" as timedOut
    state "cancelled(timeMs:)" as cancelled

    [*] --> cycles : action delivered
    cycles --> cycles : fingerprint unchanged, quiet +1
    cycles --> cycles : fingerprint or tripwireSignal changed, reset
    cycles --> settled : 3 consecutive quiet cycles
    cycles --> timedOut : defaultTimeoutMs = 5000
    cycles --> cancelled : context cancelled

    [*] --> quiet : quiet-window mode
    quiet --> settled : window elapsed unchanged

    settled --> [*]
    timedOut --> [*]
    cancelled --> [*]
```

`quietWindow` shares the same `timedOut` and `cancelled` edges as
`consecutiveCycles`; they are drawn once to keep the picture readable.

The two clocks:

```mermaid
flowchart TD
    subgraph tripwire["TheTripwire — UIKit signals"]
        PULSE["CADisplayLink pulse<br/>default 10 Hz (BH_TRIPWIRE_PULSE_HZ)"]
        SIGNAL["TripwireSignal<br/>layer scan · VC identity · window stack"]
        PULSE --> SIGNAL
    end
    subgraph settle["SettleSession — AX tree"]
        PARSE["parse cycle every<br/>defaultCycleIntervalMs = 100"]
        FP["fingerprint complete hierarchy:<br/>paths · ordering · semantic facts · containers<br/>heist ids · first responder · coarse geometry"]
        PARSE --> FP
    end
    SIGNAL -- "signal change resets<br/>the settle baseline" --> PARSE
```

Notes:

- The fingerprint (`SettleTimeline.fingerprint(of:)`) hashes hierarchy paths and ordering, every stable element semantic fact, containers, heist-id assignments, first-responder identity, and coarse geometry. Volatile `value`, shape, and activation-point facts are **skipped for elements carrying `updatesFrequently`**, so clocks and progress bars cannot hold the screen "unsettled" forever.
- A clean result carries the exact final `InterfaceObservation`; the semantic stream admits that observation only while its tripwire signal and capture identity are still current. It never reacquires or reconstructs the parser sample after settlement.
- `SettleOutcome.timedOut` is explicitly unsettled: `didSettleCleanly` is `false` and the result reports `settled: false`. It is never passed off as stable.
- `cancelled` is the third outcome — the session was torn down mid-action, distinct from `timedOut` so the caller can short-circuit instead of continuing on a dead session.
- Constants live in `SettleSession`: `defaultCyclesRequired = 3`, `defaultCycleIntervalMs = 100`, `defaultTimeoutMs = 5_000`.

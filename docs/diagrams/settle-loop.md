# Settle Loop

The tripwire and the settle loop as cooperating mechanisms: TheTripwire watches UIKit timing signals on a display-link pulse, while SettleSession proves the accessibility tree stable by fingerprinting consecutive parses. This diagram makes "settled evidence" concrete — it answers "what exactly does Button Heist mean when it says the screen settled?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ACCESSIBILITY-CONTRACT.md](../ACCESSIBILITY-CONTRACT.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/SettleTimeline.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`, `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire+Pulse.swift`, `ButtonHeist/Sources/TheScore/ButtonHeistRuntimeKnobs.swift`

```mermaid
stateDiagram-v2
    state "consecutiveCycles" as cycles
    state "quietWindow" as quiet
    state "settled(timeMs:)" as settled
    state "timedOut(timeMs:)" as timedOut
    state "cancelled(timeMs:)" as cancelled

    [*] --> cycles : action delivered — tripwire baseline captured
    [*] --> quiet : quiet-window mode (configured wait)

    cycles --> cycles : fingerprint unchanged — quiet +1
    cycles --> cycles : fingerprint changed — reset
    cycles --> cycles : tripwireSignal changed — baseline reset
    cycles --> settled : 3 consecutive quiet cycles (~300 ms floor)
    quiet --> settled : window elapsed with no change

    cycles --> timedOut : defaultTimeoutMs = 5000 elapsed
    quiet --> timedOut : defaultTimeoutMs = 5000 elapsed
    cycles --> cancelled : context cancelled
    quiet --> cancelled : context cancelled

    settled --> [*]
    timedOut --> [*]
    cancelled --> [*]
```

The two clocks:

```mermaid
flowchart TD
    subgraph tripwire["TheTripwire — UIKit signals, never reads the AX tree"]
        PULSE["CADisplayLink pulse<br/>default 10 Hz (BH_TRIPWIRE_PULSE_HZ)"]
        SIGNAL["TripwireSignal<br/>layer scan · VC identity · window stack"]
        PULSE --> SIGNAL
    end
    subgraph settle["SettleSession — AX-tree fingerprint cycles"]
        PARSE["parse cycle every<br/>defaultCycleIntervalMs = 100"]
        FP["fingerprint per element:<br/>label · identifier · traits<br/>value + coarse geometry<br/>(masked for updatesFrequently)"]
        PARSE --> FP
    end
    SIGNAL -- "signal change resets<br/>the settle baseline" --> PARSE
```

Notes:

- The fingerprint (`SettleTimeline.fingerprint(of:)`) hashes each element's `label`, `identifier`, and `traits`; `value` and coarse geometry are **skipped for elements carrying `updatesFrequently`**, so clocks and progress bars cannot hold the screen "unsettled" forever.
- `SettleOutcome.timedOut` is explicitly unsettled: `didSettleCleanly` is `false` and the receipt reports `settled: false`. It is never passed off as stable.
- `cancelled` is the third outcome — the session was torn down mid-action, distinct from `timedOut` so the caller can short-circuit instead of continuing on a dead session.
- Constants live in `SettleSession`: `defaultCyclesRequired = 3`, `defaultCycleIntervalMs = 100`, `defaultTimeoutMs = 5_000`.

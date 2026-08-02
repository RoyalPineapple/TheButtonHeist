# Heist Execution

One pure `HeistExecution` reducer advances one complete heist. It owns the
execution meaning. It returns only the next `Effect`, a `WaitRequest`, or the
final `Completion`.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md),
[WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Reducer.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+ControlFlow.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Leaf.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/HeistExecution+Host.swift`

## State Algebra

```mermaid
stateDiagram-v2
    state "ready" as Ready
    state "running" as Running
    state "awaiting failure screenshot" as FailureCapture
    state "cancelling" as Cancelling
    state "complete" as Complete

    [*] --> Ready
    Ready --> Running : start(at, timeout)
    Running --> Running : reduce(Event)
    Running --> FailureCapture : failed result needs capture
    FailureCapture --> Complete : matching capture fact
    FailureCapture --> Complete : cancellationRequested
    Running --> Cancelling : cancellationRequested
    Cancelling --> Complete : matching cleanup fact
    Running --> Complete : final result
    Complete --> Complete : any late fact
```

The private state stores control-flow progress, step results, expectation
progress, stable request IDs, and the original leaf and whole-heist deadlines.
It has no UIKit object, task, socket, closure, subscription, or notification
lease. For the same plan, start time, and ordered facts, it returns the same
decisions.

## Ordered Execution

```mermaid
sequenceDiagram
    participant Caller
    participant Host as HeistExecution.Host
    participant Execution as HeistExecution
    participant Vault as TheVault.State
    participant UIKit

    Caller->>Host: execute(HeistPlan)
    Host->>Execution: start(at, timeout)
    loop until complete
        alt perform(Effect)
            Execution-->>Host: typed Effect with stable ID
            alt snapshot or observation effect
                Host->>Vault: capture or read current truth
                Vault-->>Host: raw snapshot or evidence facts
            else action or viewport effect
                Host->>UIKit: perform requested work
                UIKit-->>Host: raw outcome
            end
            Host->>Execution: reduce(Event)
        else wait(WaitRequest)
            Execution-->>Host: stable ID + absolute deadline
            Vault-->>Host: next ordered Observation.Event
            Host->>Execution: reduce(Event)
        else complete(Completion)
            Execution-->>Host: terminal Completion
        end
    end
    Host-->>Caller: HeistResult or CancellationError
```

The host subscribes once for the heist. The Vault records each observation
event before delivery, so live execution and retained evidence share one order.
The host owns the live resources. It does not inspect reducer state.

## Observation Close

```mermaid
flowchart LR
    Reduce["HeistExecution<br/>reduce fact"] --> Sample["sampleObservationClose<br/>coverage, refresh, or next cycle"]
    Sample --> Host["Host performs one capture<br/>and keeps sealed lease"]
    Host --> Facts["raw evidence + viewport +<br/>capture and timing facts"]
    Facts --> Decide{"proof complete or<br/>deadline rule complete?"}
    Decide -- "no" --> Sample
    Decide -- "yes" --> Commit["commitObservationClose"]
    Commit --> Release["Host releases resource<br/>and returns matching fact"]
    Release --> Result["Reducer constructs LeafOutcome<br/>and projects the result"]
```

The reducer chooses the sample mode. A requested close first admits causal
coverage, then asks for deadline-bounded refreshes until the authored
expectation and structural `noChange` are proved or time expires. A deadline
close takes one next-cycle sample. It takes one more next-cycle sample only when
the first sample proves the authored part but still needs stability. The host
never evaluates an expectation or constructs `LeafOutcome`.

## Deadline Boundary

The reducer stores the original leaf and whole-heist deadlines. It gives each
boundary effect and wait the earlier absolute target. It keeps both originals
so leaf timeout, whole-heist timeout, and equal expiry stay distinct.

The host reads the clock and waits. It returns a stable-ID deadline fact. The
reducer rejects stale facts, closes active observation evidence, and decides the
timeout result. No deadline fact enters `Observation.History`.

## Failure and Cancellation

Failure screenshots are reducer finalization. If the failed result needs one,
the reducer returns `captureFailureScreenshot`, admits the matching capture
fact, and then completes. Cancellation skips a pending failure screenshot and
completes with `.cancelled`. The first admitted terminal event wins, and the
complete state absorbs every later event.

Cancellation has one typed path:

1. The host returns `cancellationRequested`.
2. The reducer returns `cancelObservation` once.
3. The host releases the keyed observation resource and returns the matching
   cleanup fact.
4. The reducer completes with `.cancelled`.
5. The host throws `CancellationError` and releases heist lifetime resources.

Cancellation during failure capture starts at step 4 because no observation
resource remains open.

No result projection performs another capture, discovery, predicate
evaluation, or history reconstruction.

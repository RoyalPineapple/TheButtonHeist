# Settlement Loop

Actions and waits use one reducer-driven settlement engine. The command is a
two-axis product: its trigger is either an action or observation, and it may
carry one resolved predicate. Readiness and an admitted observation handoff are
required for every successful result.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md),
[WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Reducer.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Execution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+ResultProjection.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/UIKitIdleTracker.swift`

## Four commands, one lifecycle

| Trigger | Predicate | Meaning | Dispatches |
| --- | --- | --- | --- |
| action | absent | perform an action and return when its UI is ready | once |
| action | present | perform an action while evaluating its attached expectation | once |
| observation | present | `waitFor` | never |
| observation | absent | observe and settle current UI | never |

```mermaid
stateDiagram-v2
    [*] --> AwaitingBaseline : capture baseline
    [*] --> Armed : supplied baseline
    [*] --> Failed : required baseline unavailable
    AwaitingBaseline --> Armed : baseline Moment committed
    AwaitingBaseline --> Failed : baseline unavailable
    Armed --> Dispatching : action trigger
    Armed --> Observing : observation trigger
    Dispatching --> Observing : dispatch completes
    Observing --> Observing : observation, announcement,<br/>predicate, or readiness event
    Observing --> NeedHandoff : readiness without eligible observation
    NeedHandoff --> Observing : handoff capture admitted
    Observing --> Completed : trigger + predicate +<br/>readiness + handoff
    NeedHandoff --> Completed : remaining evidence complete
    Dispatching --> TimedOut : absolute deadline
    Observing --> TimedOut : absolute deadline
    NeedHandoff --> TimedOut : absolute deadline
    AwaitingBaseline --> Cancelled : cancellation
    Armed --> Cancelled : cancellation
    Observing --> Cancelled : cancellation
    Completed --> [*]
    Failed --> [*]
    TimedOut --> [*]
    Cancelled --> [*]
```

## Arm before dispatch

```mermaid
sequenceDiagram
    participant Caller
    participant Executor as Settlement.Executor
    participant Store as Observation.Store
    participant Channels as Observation + announcement<br/>+ readiness + deadline
    participant UIKit as Action boundary
    participant Reducer as Settlement.Reducer

    Caller->>Executor: execute typed Command
    alt command captures its baseline
        Executor->>Store: capture and commit baseline
        Store-->>Executor: Moment
    else command supplies an exact Moment
        Executor->>Store: subscribe with replay after Moment
        Store-->>Executor: retained Events, then live delivery
    end
    Executor->>Channels: arm after baseline
    Channels-->>Reducer: channelsArmed
    alt action trigger
        Executor->>UIKit: dispatch exactly once
        UIKit-->>Reducer: dispatchCompleted
    else observation trigger
        Note over Executor,UIKit: no action and no fake no-op
    end
    loop until terminal
        Channels-->>Reducer: committed Event / announcement / readiness
        Reducer-->>Executor: typed effects
    end
    alt readiness has no eligible observation
        Reducer-->>Executor: capture one handoff
        Executor->>Store: admit and commit capture
        Store-->>Reducer: post-readiness Event
    end
    Reducer-->>Executor: Settlement.Result
    Executor-->>Caller: project action or wait result
```

Arming first closes the synchronous-change race: an announcement or hierarchy
change caused during dispatch cannot occur before its consumer exists. The
absolute deadline covers baseline, dispatch, observation effects, readiness,
predicate evaluation, and handoff; no phase receives a fresh timeout.

## Completion evidence

A successful result is constructible only when all applicable evidence agrees:

1. The trigger completed successfully. Observation triggers satisfy this
   structurally; action triggers require one successful dispatch.
2. The optional predicate is satisfied. Current-state evidence must hold in the
   returned handoff. Positive transitions and announcements may remain latched.
3. UIKit readiness is established for the current readiness generation.
4. The returned observation was admitted at or after that readiness boundary.

Readiness that arrives after the latest observation requests exactly one
handoff capture. If a qualifying observation was already admitted after the
readiness boundary, it is reused. There is no fixed 30 ms stability delay and
no blanket final predicate revalidation.

The lifecycle-wide `UIKitIdleTracker` combines the aggregate animation counter
with a main-run-loop `beforeWaiting` edge. The private start/stop hooks are
installed for the active Inside Job runtime, not around each action. Nested
heists share the outer observation demand. The existing semantic quiet-window
path remains the fallback for unavailable private tracking and cosmetic
infinite animations.

## Terminal cleanup

Terminal projection happens after structured cleanup:

1. stop accepting new sink callbacks;
2. request graceful stop for viewport-mutating observation work;
3. cancel and join owned dispatch, capture, evaluation, readiness, and deadline
   tasks;
4. consume or release child notification scopes;
5. release the outer action notification window and observation demand; and
6. emit one diagnosis derived from the canonical result.

This ordering prevents a child scope from outliving its owner, restores the
viewport before an observation-only wait returns, and guarantees no capture or
predicate work occurs after the terminal result.

# Settlement Loop

Actions, waits, and heist control flow use one reducer-driven settlement engine.
The command algebra admits exactly three operations: capture current state,
observe until a predicate is satisfied, or dispatch one action with an optional
expectation. Timed commands require readiness and an admitted observation
handoff; current-state inspection returns its one admitted capture directly.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md),
[WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Reducer.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+Execution.swift`,
`ButtonHeist/Sources/TheInsideJob/TheBrains/Settlement+ResultProjection.swift`,
`ButtonHeist/Sources/TheInsideJob/TheTripwire/UIKitIdleTracker.swift`

## Three commands, one owner

| Command | Predicate | Meaning | Dispatches |
| --- | --- | --- | --- |
| `currentState` | absent | capture one exact settled snapshot | never |
| `observation` | present | `waitFor` | never |
| `action` | optional | perform one action, optionally evaluating its expectation | once |

```mermaid
stateDiagram-v2
    state "Settlement.State.awaitingBaseline(Command)" as AwaitingBaseline
    state "Settlement.State.armed(Session)" as Armed
    state "Settlement.State.active(Session)" as Active {
        state PhaseChoice <<choice>>
        state "Session.Phase.observation(PhaseDeadline)" as Observation
        state "Session.Phase.awaitingActionDispatch" as AwaitingActionDispatch
        state "Session.Phase.actionReadiness(PhaseDeadline)" as ActionReadiness
        state "Session.Phase.actionExpectation(PhaseDeadline)" as ActionExpectation

        [*] --> PhaseChoice
        PhaseChoice --> Observation : observation command
        PhaseChoice --> AwaitingActionDispatch : action command
        Observation --> Observation : ordered nonterminal Event
        AwaitingActionDispatch --> ActionReadiness : dispatchCompleted / replace deadline
        ActionReadiness --> ActionReadiness : ordered nonterminal Event
        ActionReadiness --> ActionExpectation : first ready handoff + unmet predicate / replace deadline
        ActionReadiness --> ActionReadiness : readiness invalidated / advance generation
        ActionExpectation --> ActionExpectation : ordered nonterminal Event or generation advance
        ActionExpectation --> ActionExpectation : stale readiness deadline ignored
    }
    state "Settlement.State.terminal(Result)" as Terminal

    [*] --> AwaitingBaseline : Command captures baseline
    [*] --> Armed : Command supplies baseline
    AwaitingBaseline --> Armed : baselineAdmitted
    AwaitingBaseline --> Terminal : currentState Result, failure, or cancellation
    Armed --> Active : channelsArmed
    Armed --> Terminal : cancellation
    Active --> Terminal : requirements complete, current deadline, failure, or cancellation
    Terminal --> Terminal : later Event ignored
    Terminal --> [*] : project owned Result once
```

## Arm before dispatch

```mermaid
sequenceDiagram
    participant Caller
    participant Executor as Settlement.Executor
    participant Store as Observation.Store
    participant Channels as Observation + announcement + readiness
    participant UIKit as Action boundary
    participant Reducer as Settlement.Reducer
    participant Clock as Replaceable deadline task

    Caller->>Executor: execute Settlement.Command
    alt currentState command
        Executor->>Store: capture and admit once
        Store-->>Executor: exact current Moment
        Executor-->>Caller: Settlement.Result
    else timed command
        alt command captures its baseline
            Executor->>Store: capture and commit baseline
            Store-->>Executor: Moment
        else command supplies an exact Moment
            Executor->>Store: subscribe with replay after Moment
            Store-->>Executor: retained Events, then live delivery
        end
        Executor->>Channels: arm after baseline
        Channels-->>Reducer: Settlement.Event with Fact.channelsArmed
        alt action trigger
            Executor->>UIKit: dispatch exactly once
            UIKit-->>Reducer: Settlement.Event with Fact.dispatchCompleted
            Reducer-->>Clock: Effect.armDeadline readiness at dispatch + 5,000 ms
        else observation trigger
            Reducer-->>Clock: Effect.armDeadline at authored instant
            Note over Executor,UIKit: no action and no fake no-op
        end
        loop while Settlement.State is nonterminal
            alt observation, announcement, or readiness Event
                Channels-->>Executor: next ordered Event
            else phase deadline Event
                Clock-->>Executor: next ordered deadline Event
            end
            Executor->>Reducer: reduce Event
            Reducer-->>Executor: Decision with State and typed effects
            alt Decision requests a handoff capture
                Executor->>Store: capture, admit, commit
                Store-->>Executor: enqueue Fact.observationAdmitted
            else Decision admits actionExpectation
                Reducer-->>Clock: replace task with handoff + authored timeout
            else Decision rejects a stale deadline
                Note over Reducer,Executor: unchanged active State and no effects
            else Decision is terminal
                Note over Reducer,Executor: State.terminal owns one absorbing Result
            end
        end
        Executor-->>Caller: project owned Result once
    end
```

## Completion evidence

A successful timed result is constructible only when all applicable evidence
agrees:

1. The trigger completed successfully. Observation triggers satisfy this
   structurally; action triggers require one successful dispatch.
2. The optional predicate is satisfied. Current-state evidence must hold in the
   returned handoff. Positive transitions and announcements may remain latched.
3. UIKit readiness is established for the current readiness generation.
4. The returned observation was admitted at or after that readiness boundary.

A successful `currentState` result instead requires exactly one admitted
capture, represented as both its boundary and handoff. It arms no channels and
cannot dispatch or evaluate a predicate.

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
predicate work occurs after the absorbing terminal result.

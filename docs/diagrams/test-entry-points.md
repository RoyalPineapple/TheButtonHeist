# Test Entry Points

The four ways a test process hands control to Button Heist, and what the run loop is doing in each. "Held" is not "frozen": in every entry point the test thread keeps pumping the run loop, so timers, callbacks, and the in-app server all keep firing while the test waits. All four are `#if DEBUG` only.

**Illustrates:** [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md), [HEIST-FORMAT.md](../HEIST-FORMAT.md)
**Source of truth:** `ButtonHeist/Sources/ButtonHeistTesting/ButtonHeistTesting.swift`

## `runHeist` — async test, in-process run

```mermaid
sequenceDiagram
    participant Test as async test body
    participant BHT as runHeist
    participant Brains as TheBrains (in-process)

    Test->>BHT: await runHeist(name) { steps }
    BHT->>BHT: build HeistPlan from DSL content
    BHT->>Brains: execute plan
    Brains-->>BHT: HeistExecutionResult
    BHT-->>Test: Heist (throws Heist.Failure on failure)
    Note over Test: control returns — test continues
```

## `runHeistSync` — synchronous XCTest, run loop pumped

```mermaid
sequenceDiagram
    participant Test as synchronous test method
    participant Sync as runHeistSync
    participant RL as main RunLoop
    participant Task as main-actor Task

    Test->>Sync: runHeistSync(name) { steps }
    Sync->>Task: spawn async run, retain in HeistSyncState
    loop while state.result == nil
        Sync->>RL: RunLoop.current.run(mode .default, 0.05 s slices)
        Note over RL: run loop keeps turning —<br/>timers and callbacks still fire
    end
    Task-->>Sync: result stored (NSLock-guarded)
    Sync-->>Test: Heist? — control returns to the test
```

## `joinHeist` — park the test, hand the app to an agent

```mermaid
sequenceDiagram
    participant Test as test method
    participant Join as joinHeist
    participant Job as TheInsideJob server
    participant Agent as external agent

    Test->>Join: joinHeist(token, port,<br/>addressFamily, allowedScopes)
    Join->>Job: start fresh server, read listeningPort
    Join->>Join: print ready message
    loop forever
        Join->>Join: pump RunLoop
        Agent->>Job: connect, observe, act
    end
    Note over Test: control never returns —<br/>interactive use only, since test<br/>watchdogs will kill a parked test
```

## `withJoinedHeistSession` — scoped join

```mermaid
sequenceDiagram
    participant Test as test method
    participant With as withJoinedHeistSession
    participant Job as TheInsideJob server
    participant Agent as external agent

    Test->>With: withJoinedHeistSession(token, port) { session in ... }
    With->>Job: start server
    With-->>Test: body runs with JoinedHeistSession<br/>(listeningPort, token, readyMessage)
    Agent->>Job: connect and drive while body runs
    Test->>With: body returns
    With->>Job: stop server (defer)
    With-->>Test: body's result — control returns
```

Notes:

- `runHeist` and `runHeistSync` run the plan in-process; `joinHeist` and `withJoinedHeistSession` start a `TheInsideJob` server inside the test host so an **external** agent can connect (observation and control come from outside, over the same wire as any other client).
- `runHeistSync` exists so the test method itself can stay synchronous: it polls `HeistSyncState` in 0.05 s run-loop slices until the main-actor task publishes a result.
- Bare `joinHeist` never returns — it is for interactive sessions only. Under CI, test watchdogs will kill a parked test; use `withJoinedHeistSession` when the join must end.
- Receipts can be recorded per run via `HeistTestReceiptRecording` (`.environment`, `.failures`, `.always`).

# Recording Contract

Recording turns successful runtime evidence into a durable semantic heist test.
It is not a playback log.

The recorder observes the same dispatched and validated responses as normal
execution. It does not dispatch commands, re-run waits, resolve targets, or
store live runtime handles.

## Recording Rule

```mermaid
flowchart LR
    Request["Request intent"] --> Result["Settled action result"]
    Result --> Effect["Recording effect"]
    Effect --> Step["Semantic heist step + expectation"]
```

Every interaction during recording has one explicit effect:

| Effect | Meaning |
|--------|---------|
| append | Store one or more durable heist steps. |
| drop pending viewport movement | Discard incomplete viewport movement when later semantic intent failed to record. |
| ignore | Leave recording state unchanged, usually for pure reads. |

## What Records

- Successful semantic actions record semantic commands with minimum durable
  targets from settled evidence.
- Passed explicit expectations record as action expectations.
- Clear settled evidence can infer expectations such as target absence,
  current value/state, or screen change when no more precise outcome exists.
- Explicit mechanical or viewport commands record only when the gesture or
  viewport state is the user's durable intent.

## What Does Not Record

- Read and inspection commands.
- Failed actions.
- Actions with unmet explicit expectations.
- `scroll_to_visible` as setup for later semantic commands.
- Manual scroll before a semantic action when the semantic action is the
  durable intent.
- Ambiguous or unrecordable semantic evidence.
- Viewport geometry, capture IDs, runtime IDs, live object references, container
  handles, or capture-local IDs as semantic identity.

## Matcher Policy

Recorded semantic targets come from before-state evidence. The matcher should be
the minimum durable selector that preserves intent: useful identity first,
state only when needed, and ordinal only when semantic predicates cannot
disambiguate.

Disappearance expectations also use before-state matchers. Current-state
expectations use durable identity plus after-state value or state.

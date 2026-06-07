# Accessibility Contract Runtime

Button Heist lets callers write programs against an app's accessibility
contract.

The accessibility contract is the semantic interface the app exposes to
assistive technologies: labels, identifiers, roles, values, states, and
actions. Button Heist makes that contract executable for agents, tests, and
replay.

## Runtime Invariant

```mermaid
flowchart LR
    Contract["Accessibility contract"] --> Program["Semantic program or command"]
    Program --> Runtime["Shared action-or-wait runtime"]
    Runtime --> Evidence["Settled semantic evidence"]
    Evidence --> Projection["Validation, report, or next step"]
```

Semantic intent enters the runtime. Button Heist owns target resolution, reveal,
element inflation, action execution, settling, and evidence. The result is
settled semantic evidence, not a mechanical playback log.

## Boundaries

| Boundary | Owns | Refuses to own |
|----------|------|----------------|
| `AccessibilityPredicate` | Condition algebra for waits, expectations, and control-flow cases | Target resolution, viewport movement, command execution |
| `AccessibilityTrace` | Observed accessibility captures and capture-chain identity | Independent delta truth, repair policy, report formatting |
| `InteractionObservation` | Before/body/after evidence coordination for actions and waits | Command payload design and report adapters |
| `ElementInflation` | Semantic target to inflated live target | Public viewport instructions, predicate evaluation, durable selector choice |
| `HeistPlan` | Durable semantic program AST | Arbitrary Swift source, native loop preservation, runtime state |
| `EvidenceMinimumMatcher` | Offline matcher suggestions from settled result evidence | Runtime execution, storage, or hidden test generation |

Adapters format product results for CLI, MCP, JSON, compact text, or JUnit. They
do not decide what a semantic action means or whether a predicate is true.

## Pipeline

All executable routes enter the same machine:

1. Direct CLI/MCP command, Swift DSL, `.json` plan IR, or `.heist` artifact
   produces either a single command or a `HeistPlan`.
2. The runtime observes settled before-state when the route performs an action
   or evaluates a wait.
3. Element inflation resolves the target, reveals it if needed, acquires fresh
   live inflation evidence, and executes the accessibility operation.
4. The runtime waits for settled semantic evidence.
5. Reports, JSON, compact output, and later repair artifacts project
   from the resulting trace and execution result.

No public route asks callers to manage ordinary viewport mechanics for semantic
commands. Viewport and mechanical commands are explicit when viewport state or
the physical gesture itself is the intent. Viewport/debug commands are directly
executable for inspection, but they are not durable heist primitives.

## Conformance Cases

The product contract is healthy when these cases hold:

- A semantic activation can act on an offscreen accessible target without a
  caller-authored scroll step.
- Duplicate labels produce the minimum matcher that disambiguates semantic
  intent.
- `wait` and action expectations use the same `AccessibilityPredicate`
  evaluator.
- Unknown JSON keys fail at the contract boundary.
- Timeout diagnostics say which contract was not satisfied and what command or
  target shape is valid next.
- `AccessibilityTrace` captures are the source of truth; deltas are projections.

# Predicate truth invariants (rescued from SettlementReducerTests truth matrix)

Deleted with the evidence-kind machinery. Re-express these in the
predicate-algebra suite (task #13) as tick sequences, not evidence kinds.

| # | Invariant | Baseline -> Observed | Predicate | Expected |
|---|-----------|----------------------|-----------|----------|
| 1 | always-present exists is a level | ready -> ready | `exists(.label("Ready"))` | true |
| 2 | always-present does not appear | ready -> ready | `changed(.appeared(.label("Ready")))` | false |
| 3 | always-absent missing is a level | empty -> empty | `missing(.label("Ready"))` | true |
| 4 | always-absent does not disappear | empty -> empty | `changed(.disappeared(.label("Ready")))` | false |
| 5 | semantic value update is a transition | count=1 -> count=2 | `changed(.updated(.label("Count"), .value(before:"1", after:"2")))` | true |
| 6 | exact match is not promoted by a combined label | empty -> "Ticket saved., Dismiss" | `changed(.appeared(.label("Ticket saved.")))` | false |
| 7 | appearance before the baseline is excluded | (pre: empty) ready -> ready | `changed(.appeared(.label("Ready")))` | false |

Plus `assertTransientHistory`: empty -> ready -> empty.
- `changed(.appeared(.label("Ready")))` observed at the transient tick: true
- `exists(.label("Ready"))` at the final tick: false

Under the two-element model these fall out of the tick sequence directly:
#1/#3 are single-half; #2/#4 are the "opening half never satisfied by the
first tick" case; #7 is the baseline-is-the-first-tick rule.

## Rescued from the deleted exploration-baseline tests (2026-07-26)

`TheVault.visibleExplorationBaseline` and `interfaceMemoryBaseline` were deleted
with `ExplorationBaseline` — their `InterfaceObservation` payload was never read.
Two tests went with them. The invariant they encoded still holds, enforced now by
`SemanticObservationStore:201` (`isReplacement ? admission.tree : candidateTree`):

- **Stale discovery memory must not survive a screen change.** Off-screen
  elements discovered on the previous screen must not appear in the new screen's
  tree, even when they share a generated container name with something on it.
- **A fresh baseline is viewport-only.** What is not currently visible is not in
  it, so a later merge cannot resurrect an element that was never re-observed.

Worth re-asserting against the store directly in the predicate-algebra suite.

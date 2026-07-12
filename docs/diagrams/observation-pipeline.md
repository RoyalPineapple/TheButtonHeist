# Observation Pipeline

Button Heist retains one settled `InterfaceTree` as current semantic truth and
settled accessibility captures as temporal truth. It derives one ordered
`ChangeFact` stream for every temporal consumer. Predicates, receipts,
diagnostics, and public formatting all start from that stream. The public
`delta` is a final, lossy fold for display and transport; it is never evaluator
input.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md),
[API.md](../API.md), [WIRE-PROTOCOL.md](../WIRE-PROTOCOL.md)

**Source of truth:**
`ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+InterfaceState.swift`,
`ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift`,
`ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace.swift`,
`ButtonHeist/Sources/TheScore/Evidence/AccessibilityTrace+ChangeFacts.swift`,
`ButtonHeist/Sources/TheScore/Evidence/AccessibilityTraceDiff.swift`,
`ButtonHeist/Sources/TheScore/Core/AccessibilityPredicate+Evaluation.swift`,
`ButtonHeist/Sources/TheButtonHeist/TheFence/DeltaProjection.swift`

```mermaid
flowchart TD
    Signals["Scoped accessibility notifications<br/>screen, layout, value, announcement"] --> Settle["Settle and parse"]
    Parse["Parser read<br/>InterfaceObservation + disposable LiveCapture"] --> Settle
    Settle -- "clean proof" --> Tree["TheStash.interfaceTree<br/>sole current semantic truth"]
    Tree --> Captures["AccessibilityTrace captures<br/>durable temporal truth"]
    Captures --> Facts["Ordered ChangeFact stream<br/>sole temporal model"]

    Facts --> Evaluate["AccessibilityPredicate evaluation"]
    Captures --> Evaluate
    Evaluate --> Verdict["met or unmet<br/>noChange only for complete fact-free windows"]

    Facts --> Fold["One-way public delta fold<br/>stack facts in order, then squash"]
    Captures --> Fold
    Fold --> Public["noChange, elementsChanged, or screenChanged<br/>screen dominates"]

    Public -. "never evaluator input" .-> Stop["No reverse edge"]
```

A screen boundary is normalized into the same fact language:

```mermaid
sequenceDiagram
    participant Old as Old generation
    participant Facts as Ordered ChangeFact stream
    participant New as New generation

    Old->>Facts: elementsChanged(disappeared: every old node)
    Facts->>Facts: screenChanged marker
    New->>Facts: elementsChanged(appeared: every new node)
```

Consequences:

- `changed(.screen(...))` requires the screen marker, then evaluates its
  `exists` and `missing` assertions against the current delivered tree.
- `changed(.elements(...))` can match lifecycle facts produced by same-screen
  edits or by a screen boundary.
- Identically described nodes on opposite sides of a screen boundary still
  disappear and appear. They are not updates.
- `updated` facts can only be constructed while observing two captures in the
  same screen generation.
- Any scoped screen, layout, value, or announcement notification is edge
  evidence. It prevents a fact-free `noChange` verdict even when endpoint
  captures have equal hashes.
- Raw parser reads refresh disposable live action evidence but do not update the
  settled interface. Failed settles remain diagnostic evidence only.
- Scoped screen notification is authoritative replacement evidence. Element
  and announcement notifications stay in-generation; only empty or unknown
  notification evidence permits typed snapshot fallback.
- The public fold composes facts like stacked layers, resolves transient
  appear/disappear pairs, and lets any screen marker dominate the final kind.
  That convenience projection cannot recover the ordered history it squashed.

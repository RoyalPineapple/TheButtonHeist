# Element Inflation

How an `AccessibilityTarget` resolves in the delivered tree and, for actions,
becomes a live actionable element. The same resolver also serves predicates and
`get_interface` subtree queries.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/AccessibilityTarget.swift`, `ButtonHeist/Sources/ThePlans/Model/ElementPredicate.swift`, `ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+TargetResolution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+SemanticReveal.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation+Geometry.swift`

```mermaid
flowchart TD
    TARGET["AccessibilityTarget<br/>predicate · container · within · ref"] --> SCOPE["resolve against current<br/>delivered Interface tree"]
    SCOPE --> KIND{"target kind"}
    KIND --> MATCH["element checks<br/>label · identifier · value · hint<br/>traits · actions · content · rotors"]
    KIND --> CMATCH["container checks<br/>identifier on any container type<br/>semantic · role · scroll · modal"]
    KIND --> WITHIN["resolve container scope,<br/>then descendant target"]
    CMATCH --> RESOLVEDNODE["resolved container node"]
    WITHIN --> MATCH

    MATCH -- "0 matches" --> NOTFOUND[".notFound(TargetNotFoundFacts)<br/>reason .noMatches<br/>+ interface elements in scope as suggestions"]
    MATCH -- "1 match, no ordinal" --> RESOLVED[".resolved(InterfaceTree.Element)<br/>pin exact HeistId"]
    MATCH -- "2+ matches, no ordinal" --> AMBIG[".ambiguous(TargetAmbiguityFacts)<br/>first candidates listed —<br/>ordinal required to proceed"]
    MATCH -- "ordinal given, in range" --> RESOLVED
    MATCH -- "ordinal given, out of range" --> NOTFOUND2[".notFound<br/>reason .ordinalOutOfRange / .ordinalNegative"]

    RESOLVED --> BUDGET["derive one deadline from<br/>scroll-membership ancestor count"]
    BUDGET --> LIVE{"pinned HeistId live<br/>in latest capture?"}
    LIVE -- "yes" --> REFRESH["refresh exact HeistId"]
    LIVE -- "off-viewport,<br/>has scrollMembership" --> GRAPH["walk semantic ancestor graph<br/>outermost-first"]
    GRAPH --> ALIAS{"each path has exact current<br/>live alias / direct containment?"}
    ALIAS -- "yes" --> REVEAL["reveal ancestor, then target"]
    ALIAS -- "no" --> SCAN["bounded exploration scan<br/>for the same HeistId"]
    SCAN --> REFRESH
    REVEAL --> REFRESH
    REFRESH --> EXACT{"committed tree and live capture<br/>still contain pinned HeistId?"}
    EXACT -- "yes" --> STABLE["stabilize frame + activationPoint<br/>under the same deadline"]
    EXACT -- "no, time remains" --> WAIT["await next clean settled<br/>visible observation"]
    WAIT --> REFRESH
    STABLE -- "stable and onscreen" --> ACT["LiveActionTarget<br/>for pinned HeistId"]
    STABLE -- "deadline / offscreen" --> MISS["failure with diagnostics"]
    WAIT -- "deadline reached" --> MISS
```

Notes:

- Resolution reads the **interface tree only** (`TheStash.interfaceTree`). Live capture proves current actionability and geometry for an interface element; it is not a second search space.
- Container-only targets are valid for predicates and subtree queries. Element-
  only actions reject a resolved container with a typed target-kind error.
- Matching is **exact or miss**: string checks are case-insensitive with typography folding (smart quotes, dashes, ellipsis fold to ASCII), traits compare as sets. On a miss the resolver returns structured facts — the interface elements in scope — through the diagnostic path; substring matching is not part of resolution.
- The first successful semantic resolution pins one `HeistId`. Every reveal, refresh, geometry sample, multi-stage action handoff, and final dispatch must retain that id; the original selector is not rerun to choose a replacement.
- The handoff budget is graph-derived: `max(2, unique scroll-membership ancestors + 1)` one-second ticks. Nested reveal follows that graph outermost-first, proves each semantic path against current live containment, and shares the same deadline with geometry stabilization.
- A missing direct reveal path may trigger bounded exploration for the same pinned `HeistId`. A known target that later gains scroll membership earns at most one direct reveal attempt; content absent from settled semantic truth cannot be revealed.
- The ordinal is a disambiguator over a semantic base selector, never a selector by itself.

# Element Inflation

How an `AccessibilityTarget` resolves in the delivered tree and, for actions,
becomes a live actionable element. The same resolver also serves predicates and
`get_interface` subtree queries.

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/AccessibilityTarget.swift`, `ButtonHeist/Sources/ThePlans/Model/ElementPredicate.swift`, `ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+TargetResolution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift`

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
    MATCH -- "1 match, no ordinal" --> RESOLVED[".resolved(InterfaceTree.Element)"]
    MATCH -- "2+ matches, no ordinal" --> AMBIG[".ambiguous(TargetAmbiguityFacts)<br/>first candidates listed —<br/>ordinal required to proceed"]
    MATCH -- "ordinal given, in range" --> RESOLVED
    MATCH -- "ordinal given, out of range" --> NOTFOUND2[".notFound<br/>reason .ordinalOutOfRange / .ordinalNegative"]

    RESOLVED --> LIVE{"live geometry<br/>available?"}
    LIVE -- "visible in latest capture" --> ACT["LiveActionTarget<br/>frame + activationPoint from live element"]
    LIVE -- "off-viewport,<br/>has scrollMembership" --> REVEAL["auto-reveal scroll"]
    REVEAL -- "target becomes visible" --> ACT
    REVEAL -- "reveal path unavailable" --> WAIT["await next settled<br/>visible observation<br/>(until action deadline)"]
    WAIT -- "settled observation arrives" --> REFRESH["refresh live capture"]
    REFRESH --> RETRY["resolve against settled tree<br/>and refreshed live capture"]
    RETRY -- "visible" --> ACT
    RETRY -- "known target gains<br/>scroll membership<br/>(one attempt)" --> REVEAL
    RETRY -- "missing,<br/>time remains" --> WAIT
    WAIT -- "action deadline reached" --> MISS["failure with diagnostics"]
```

Notes:

- Resolution reads the **interface tree only** (`TheStash.interfaceTree`). Live capture proves current actionability and geometry for an interface element; it is not a second search space.
- Container-only targets are valid for predicates and subtree queries. Element-
  only actions reject a resolved container with a typed target-kind error.
- Matching is **exact or miss**: string checks are case-insensitive with typography folding (smart quotes, dashes, ellipsis fold to ASCII), traits compare as sets. On a miss the resolver returns structured facts — the interface elements in scope — through the diagnostic path; there is no fuzzy fallback.
- Reveal retries are bounded by the action deadline. Each retry awaits the next settled visible semantic observation, refreshes disposable live capture, and resolves against that settled tree plus its fresh live evidence. A known target that gains scroll membership earns at most one reveal attempt; content absent from settled semantic truth cannot be revealed.
- The ordinal is a disambiguator over a semantic base selector, never a selector by itself.

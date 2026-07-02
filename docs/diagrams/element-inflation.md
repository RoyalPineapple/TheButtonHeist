# Element Inflation

How an `ElementTarget` becomes a live, actionable element: predicate resolution against the settled world, ordinal disambiguation, near-miss diagnostics, and the auto-reveal scroll path for known-but-offscreen targets. This diagram answers "why did my selector hit, miss, or scroll?"

**Illustrates:** [ARCHITECTURE.md](../ARCHITECTURE.md), [API.md](../API.md), [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [SCOPE-AND-LIMITS.md](../SCOPE-AND-LIMITS.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/ElementTarget.swift`, `ButtonHeist/Sources/ThePlans/ElementPredicate.swift`, `ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+TargetResolution.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation.swift`

```mermaid
flowchart TD
    TARGET["ElementTarget<br/>.predicate(ElementPredicate, ordinal:)"] --> SCOPE["resolveTarget against<br/>settledSemanticScreen — the settled world"]
    SCOPE --> MATCH["evaluate checks: label · identifier · value<br/>(exact / contains / prefix / suffix,<br/>case-insensitive, typography-folded)<br/>traits · excludeTraits"]

    MATCH -- "0 matches" --> NOTFOUND[".notFound(TargetNotFoundFacts)<br/>reason .noMatches<br/>+ known elements in scope as suggestions"]
    MATCH -- "1 match, no ordinal" --> RESOLVED[".resolved(ScreenElement)"]
    MATCH -- "2+ matches, no ordinal" --> AMBIG[".ambiguous(TargetAmbiguityFacts)<br/>first candidates listed —<br/>ordinal required to proceed"]
    MATCH -- "ordinal given, in range" --> RESOLVED
    MATCH -- "ordinal given, out of range" --> NOTFOUND2[".notFound<br/>reason .ordinalOutOfRange / .ordinalNegative"]

    RESOLVED --> LIVE{"live geometry<br/>available?"}
    LIVE -- "visible in latest capture" --> ACT["LiveActionTarget<br/>frame + activationPoint from live element"]
    LIVE -- "known but offscreen,<br/>has scrollMembership" --> REVEAL["auto-reveal scroll<br/>(ElementInflation .revealing:<br/>revealPathGraceTimeout grace window,<br/>silent re-parse every 0.15 s)"]
    REVEAL -- "target becomes visible" --> ACT
    REVEAL -- "grace window exhausted" --> MISS["failure with diagnostics"]
```

Notes:

- Resolution reads the **settled world only** (`settledSemanticScreen`). Live capture proves actionability and geometry for a settled element; it is not a second search space.
- Matching is **exact or miss**: string checks are case-insensitive with typography folding (smart quotes, dashes, ellipsis fold to ASCII), traits compare as sets. On a miss the resolver returns structured facts — the known elements in scope — through the diagnostic path; there is no fuzzy fallback.
- The reveal path is bounded: lazily-instantiated content has no elements until UIKit realizes it, so a target that never enters the settled world cannot be revealed — the grace window (`revealPathGraceTimeout`, with `revealPathSilentReparseInterval = 0.15` s re-parses) covers async-loaded targets that are already known, not content that does not exist yet.
- The ordinal is a disambiguator over a semantic base selector, never a selector by itself.

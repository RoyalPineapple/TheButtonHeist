# Element Inflation

Element inflation is the runtime boundary between a durable semantic target and
a fresh live target that can be acted on now.

Callers provide semantic identity. Button Heist owns the bounded viewport and
live-geometry work required to execute that intent.

## Pipeline

1. Resolve the semantic target against current settled accessibility state.
2. Reject missing or ambiguous targets with diagnostics.
3. Reveal the resolved target when viewport movement is required.
4. Refresh semantic and live state after reveal or stale-object detection.
5. Acquire fresh live geometry and activation/action points.
6. Execute the accessibility operation or explicit mechanical gesture.
7. Return settled semantic evidence through `InteractionObservation`.

## Boundary Rules

- Predicate evaluation uses semantic observations, not live UIKit geometry.
- Live geometry is used for element inflation and explicit mechanical/viewport
  commands, not as durable semantic identity.
- Semantic reveal is product-owned viewport mechanics. It is not a public
  instruction to scroll before ordinary semantic commands.
- `activate` remains accessibility activation. It refreshes live geometry before
  one `accessibilityActivate()` call; delivery through a fresh activation point
  is part of activation when UIKit declines, not a separate user-requested tap.
- If element inflation cannot be proven, the command fails with diagnostics instead
  of acting on stale or guessed state.

## Diagnostics

Element inflation failures should name the failed boundary:

- target not found
- target ambiguous
- no reveal path
- stale refresh
- geometry not actionable

The diagnostic should include what Button Heist knows about the target and a
valid semantic correction when one is available.

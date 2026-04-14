# TheStash

Element registry, target resolution, wire conversion, and screen capture. The custodian of the live accessibility object world.

## Files

| File | Responsibility |
|------|----------------|
| `TheStash.swift` | Registry state, resolution, element actions, parse/wire facades |
| `TheStash+Matching.swift` | Element matching against `ElementMatcher` predicates |
| `TheStash+Capture.swift` | Screen capture (clean + recording overlay) |
| `WireConversion.swift` | Internal: `toWire()`, delta computation, tree conversion |
| `IdAssignment.swift` | Deterministic heistId synthesis from traits/labels |
| `ElementRegistry.swift` | Storage: `elements`, `viewportIds`, `reverseIndex` |
| `Diagnostics.swift` | Resolution error formatting, near-miss suggestions |
| `Interactivity.swift` | Element interactivity predicates |
| `ArrayHelpers.swift` | `[HeistElement]` screen name/id helpers |

## Boundaries

- Owned by TheBrains. Creates and owns TheBurglar (private — no external access).
- TheTripwire injected for window access.
- `WireConversion` is internal — callers use TheStash's instance methods (`toWire()`, `computeDelta()`, `traitNames()`).
- `ParseResult` typealias hides TheBurglar from external callers.

> Full dossier: [`docs/dossiers/13-THESTASH.md`](../../../../docs/dossiers/13-THESTASH.md)

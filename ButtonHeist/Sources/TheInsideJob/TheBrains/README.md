# TheBrains

Plans the play, sequences the crew — action execution, scroll orchestration, screen exploration, and the before/after delta cycle.

## Files

| File | Responsibility |
|------|----------------|
| `TheBrains.swift` | `BeforeState`, `actionResultWithDelta`, `refresh`, facades for TheInsideJob |
| `TheBrains+Dispatch.swift` | `executeCommand(_:)` — routes ClientMessage to handlers |
| `TheBrains+Actions.swift` | Element and coordinate action pipelines |
| `TheBrains+Scroll.swift` | Scroll, scroll-to-visible, element search, ensure-on-screen |
| `TheBrains+Exploration.swift` | Full-screen exploration with fingerprint caching |
| `TheBrains+Exploration+Manifest.swift` | Exploration bookkeeping |
| `ActionResultBuilder.swift` | Assembles `ActionResult` from interaction result + delta |

## Boundaries

- Owns TheStash and TheSafecracker (created in `init`).
- References TheTripwire (injected).
- Does NOT reference TheBurglar — parse/apply goes through TheStash's facades.
- Exposes facade methods (`selectElements()`, `currentInterface()`, `computeDelta()`, etc.) so TheInsideJob never reaches through to TheStash.

> Full dossier: [`docs/dossiers/13b-THEBRAINS.md`](../../../../docs/dossiers/13b-THEBRAINS.md)

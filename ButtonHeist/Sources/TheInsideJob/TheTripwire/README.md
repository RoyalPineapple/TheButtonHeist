# TheTripwire

Persistent UI pulse — samples all timing signals on a single ~10 Hz clock, gates settle decisions, and emits transition events.

## Files

| File | Purpose |
|------|---------|
| `TheTripwire.swift` | Pulse loop, `scanLayers()`, per-waiter settle, keyboard/VC tracking, `yieldFrames` |

## Boundaries

- Owned by TheInsideJob. Injected (not owned) into TheBrains, TheStash, and TheBurglar.
- Zero crew dependencies — pure sensor with no back-references.
- `onTransition` callback set by TheInsideJob; settle waiters managed independently per caller.
- Never reads the accessibility tree (separation from TheStash by design).

> Full dossier: [`docs/dossiers/14-THETRIPWIRE.md`](../../../../docs/dossiers/14-THETRIPWIRE.md)

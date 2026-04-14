# TheBurglar

Reads the live accessibility tree and populates TheStash's registry.

## Files

| File | Purpose |
|------|---------|
| `TheBurglar.swift` | Parse pipeline, apply pipeline, topology detection, search bar reveal |

## Boundaries

- Created and owned by TheStash. Private implementation detail — no external code references TheBurglar directly.
- `parse()` is pure (returns immutable `ParseResult`). `apply(_:to:)` mutates TheStash's registry.
- Depends on TheTripwire (injected) for `getAccessibleWindows()`.
- Has no mutable instance state.

> Full dossier: [`docs/dossiers/13a-THEBURGLAR.md`](../../../../docs/dossiers/13a-THEBURGLAR.md)

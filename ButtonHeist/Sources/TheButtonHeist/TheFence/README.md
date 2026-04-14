# TheFence

Centralized command dispatch — the single entry point between CLI/MCP and the iOS device.

Routes 41 commands, manages async request-response correlation, and formats responses for human and machine consumers.

## Files

| File | Purpose |
|------|---------|
| `TheFence.swift` | `execute(request:)`, `dispatch()`, connection management, pending request tracking |
| `TheFence+CommandCatalog.swift` | `Command` enum (41 cases) — the canonical command list |
| `TheFence+Handlers.swift` | Per-command handler implementations |
| `TheFence+Formatting.swift` | `FenceResponse` with human/JSON/compact formatting |
| `TheFence+ParameterSpec.swift` | Parameter metadata for MCP schema generation |
| `Dictionary+ArgParsing.swift` | Type-safe argument extraction from `[String: Any]` |

## Boundaries

- Owns `TheHandoff` (device connection) and `TheBookKeeper` (session I/O).
- Passes `command.rawValue` (String) to TheBookKeeper — no upstream type coupling.
- `TheFence.Command` is the source of truth for the CLI/MCP command catalog.

> Full dossier: [`docs/dossiers/10-THEFENCE.md`](../../../../docs/dossiers/10-THEFENCE.md)

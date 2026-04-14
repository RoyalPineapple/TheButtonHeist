# TheScore

Shared wire protocol — the cross-platform contract between the iOS server and macOS clients.

No UIKit, no AppKit. iOS 17.0+ / macOS 14.0+.

## What lives here

| File | Contents |
|------|----------|
| `Messages.swift` | Service type, protocol version, `WireMessageType`, `ButtonHeistActor` |
| `ClientMessages.swift` | `RequestEnvelope`, `ClientMessage` (35 cases), action target structs |
| `ServerMessages.swift` | `ResponseEnvelope`, `ServerMessage` (18 cases), `ActionResult`, `InterfaceDelta`, payloads |
| `Elements.swift` | `HeistElement`, `HeistTrait`, `ElementTarget`, `ElementMatcher`, `Interface`, `ElementNode` |
| `ConnectionScope.swift` | Connection source filtering (simulator/USB/network) |
| `HeistPlayback.swift` | `.heist` file wire types |
| `*+WireCoding.swift` | Custom flat-envelope Codable implementations |

## Rules

- No behavior, no side effects — pure type definitions and Codable conformances.
- Every type that crosses the TCP boundary lives here.
- Both modules (`TheInsideJob` and `ButtonHeist`) depend on TheScore; TheScore depends on neither.

> Full dossier: [`docs/dossiers/01-THESCORE.md`](../../../docs/dossiers/01-THESCORE.md)

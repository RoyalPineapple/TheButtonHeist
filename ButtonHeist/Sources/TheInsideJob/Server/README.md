# Server

TLS/TCP server infrastructure — listener, transport, auth, and connection scope classification.

## Files

| File | Purpose |
|------|---------|
| `SimpleSocketServer.swift` | NWListener-backed TCP/TLS server, client ID routing |
| `ServerTransport.swift` | Server networking abstraction + Bonjour advertisement |
| `TLSIdentity.swift` | ECDSA cert generation, SHA-256 fingerprint, Keychain persistence |
| `TheMuscle.swift` | Client auth, session locking, on-device approval prompts |
| `ConnectionScope+Classify.swift` | Classifies connections as simulator/USB/network |

## Boundaries

- `ServerTransport` owned by TheInsideJob, wired to TheMuscle via five closures.
- TheMuscle has zero crew dependencies — communicates entirely through injected callbacks.
- `ConnectionScope+Classify` extends the TheScore type with Network-framework-aware classification.

> Full dossiers: [`docs/dossiers/06-THEMUSCLE.md`](../../../../docs/dossiers/06-THEMUSCLE.md)

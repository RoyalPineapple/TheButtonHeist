# Sources

Button Heist is split into three framework targets. Each has its own README with a code walkthrough.

| Module | Platform | What it does |
|--------|----------|-------------|
| [`TheScore/`](TheScore/) | iOS + macOS | Wire protocol. Every type that crosses the TCP boundary lives here. No behavior — pure Codable types. |
| [`TheButtonHeist/`](TheButtonHeist/) | macOS | Client framework. CLI and MCP both enter through `TheFence.execute(request:)`. Handles discovery, connection, session logging. |
| [`TheInsideJob/`](TheInsideJob/) | iOS | Server framework. Embeds in apps to expose the accessibility hierarchy over TLS/TCP. |

## How they connect

```
┌─────────────────────┐         ┌─────────────────────┐
│   TheButtonHeist    │   TCP   │    TheInsideJob      │
│   (macOS client)    │◄───────►│    (iOS server)      │
└────────┬────────────┘         └────────┬────────────┘
         │ imports                        │ imports
         ▼                               ▼
    ┌─────────┐                     ┌─────────┐
    │TheScore │                     │TheScore │
    └─────────┘                     └─────────┘
```

TheScore is the shared contract — both sides import it, neither side imports the other. Client encodes `ClientMessage`, server decodes it, processes it, encodes `ServerMessage`, client decodes the response.

## How an activate command travels through the system

```
macOS                                          iOS
─────                                          ───
CLI/MCP
  → TheFence.execute(request:)                 ← parses "activate" to Command enum
    → TheHandoff.send(.activate(target))       ← JSON + newline over TLS

                        ─── wire ───

      SimpleSocketServer receives bytes
        → TheGetaway.handleClientMessage       ← decodes RequestEnvelope, routes by message type
          → TheBrains.executeCommand(.activate) ← refresh tree, capture before-state
            → TheStash.resolveTarget(target)   ← heistId lookup or matcher search
            → TheStash.activate(element)       ← try accessibilityActivate() on the live object
            ↓ returns false?
            → TheSafecracker.tap(at: point)    ← fallback: UITouch + IOHIDEvent + sendEvent
            → actionResultWithDelta(before:)   ← settle, re-parse, compute delta
          ← ActionResult
        → TheGetaway.sendMessage(.actionResult) ← encode ResponseEnvelope, respond

                        ─── wire ───

    ← TheHandoff.onActionResult                ← resolves PendingRequestTracker
  ← FenceResponse.action(result:)
```

## Where to start reading

**If you want to understand the protocol:** Start with [`TheScore/`](TheScore/) — read `Messages.swift` then `Elements.swift`.

**If you want to understand how commands work:** Start with [`TheButtonHeist/TheFence/`](TheButtonHeist/TheFence/) — read `TheFence+CommandCatalog.swift` then `TheFence.swift`.

**If you want to understand how the iOS server processes actions:** Start with [`TheInsideJob/TheBrains/`](TheInsideJob/TheBrains/) — read `TheBrains+Dispatch.swift`.

**If you want to understand message routing on the server:** Start with [`TheInsideJob/TheGetaway/`](TheInsideJob/TheGetaway/) — the two-level dispatch switch.

**If you want to understand touch injection:** Start with [`TheInsideJob/TheSafecracker/`](TheInsideJob/TheSafecracker/) — read `SyntheticTouch.swift`.

**If you want to understand the accessibility tree:** Start with [`TheInsideJob/TheStash/`](TheInsideJob/TheStash/) — read `TheStash.swift`, then [`TheBurglar/`](TheInsideJob/TheBurglar/).

## Deep reference

Architecture, design philosophy, diagrams, and the full picture live in [`docs/dossiers/`](../../docs/dossiers/).

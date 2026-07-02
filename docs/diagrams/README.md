# Diagrams

Architecture diagrams for Button Heist, one file per concern. Every diagram is Mermaid source derived from code — each file names the source files it was drawn from, and the docs it illustrates link back to it. A PR that changes a crew member's responsibilities, a state machine, the wire boundary, or the DSL grammar updates the affected diagram in the same PR.

## System level

- [system-topology.md](system-topology.md) — the whole machine: host tools, the wire, the `#if DEBUG` in-app server, the accessibility tree
- [crew-map.md](crew-map.md) — every module, its dependencies, and the Codable wire boundary
- [process-boundaries.md](process-boundaries.md) — in-process Button Heist vs out-of-process drivers, and where the snapshot copy is made

## The runtime loop

- [action-pipeline.md](action-pipeline.md) — one action end to end: dispatch, resolution, activation, settle, delta, receipt
- [settle-loop.md](settle-loop.md) — the tripwire and the settle loop; what "settled" means, with the constants
- [activation-policy.md](activation-policy.md) — the `activate` decision tree in VoiceOver order
- [element-inflation.md](element-inflation.md) — `ElementTarget` resolution: exact-or-miss matching, ordinals, diagnostics, auto-reveal
- [currency-types.md](currency-types.md) — the type families and the internal/wire border

## The language

- [heist-lifecycle.md](heist-lifecycle.md) — author → `HeistPlan` IR → `.heist` artifact → replay → receipt
- [dsl-grammar.md](dsl-grammar.md) — step types, action commands, passables, and the state/change predicate split
- [totality.md](totality.md) — why every heist halts: structural bounds and watchdog timeouts

## Connection and sessions

- [connection-lifecycle.md](connection-lifecycle.md) — `HandoffConnectionPhase` and the handshake: TLS-PSK, version gate, auth
- [multi-agent-isolation.md](multi-agent-isolation.md) — one simulator, port, and human-readable token per agent
- [test-entry-points.md](test-entry-points.md) — `runHeist` / `runHeistSync` / `joinHeist` / `withJoinedHeistSession` and the run loop

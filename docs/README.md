# Documentation

Technical documentation for The Button Heist's public contracts, runtime architecture, and integration surfaces.

## Contents

| Document | Description |
|----------|-------------|
| [Accessibility Contract](ACCESSIBILITY-CONTRACT.md) | Canonical product contract, boundary map, pipeline, and conformance cases |
| [Architecture](ARCHITECTURE.md) | Load-bearing product contracts and the compact component map |
| [API](API.md) | Product API invariants, public surface matrix, and integration contracts; generated references own commands and parameters |
| [Heist Doctor](HEIST-DOCTOR.md) | Public experimental SwiftPM-only repair-suggestion experiment for raw heist execution receipts |
| [Swift Heist Authoring](SWIFT-HEIST-AUTHORING.md) | Source boundary between Swift DSL, HeistPlan JSON IR, and `.heist` artifacts |
| [Element Inflation](ELEMENT-INFLATION.md) | Runtime boundary from semantic targets to inflated live targets |
| [Command Reference](reference/commands.md) | Generated command names, CLI exposure, heist execution eligibility, and parameters |
| [MCP Tool Reference](reference/mcp-tools.md) | Generated MCP tool surface projected from TheFence |
| [Wire Protocol](WIRE-PROTOCOL.md) | Raw TheScore transport: envelopes, handshake, authentication, TLS transport, and wire-only examples |
| [Authentication](AUTH.md) | Token-derived TLS PSK, token auth, and session locking |
| [USB Connectivity](USB_DEVICE_CONNECTIVITY.md) | Connecting to physical devices over CoreDevice IPv6 tunnels without enabling LAN scope |
| [Bonjour Troubleshooting](BONJOUR_TROUBLESHOOTING.md) | MDM stealth mode workarounds |
| [Reviewer's Guide](REVIEWERS-GUIDE.md) | Quick orientation for new reviewers |

## See Also

- [Project Overview](../README.md) — Quick start and architecture
- [Examples](../examples/README.md) — Canonical semantic command and heist examples

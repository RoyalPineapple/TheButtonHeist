# Documentation

Technical documentation for The Button Heist's public contracts, runtime architecture, integration surfaces, and evidence trails.

Start with the contract. Then choose the path that matches the job in front of you.

## Start here

| Document | Use it for |
|----------|------------|
| [Project overview](../README.md) | Public story, quick start, and first map of the system |
| [Accessibility contract](ACCESSIBILITY-CONTRACT.md) | The core runtime idea: semantic intent in, settled evidence out |
| [Architecture](ARCHITECTURE.md) | Load-bearing runtime contracts, component map, and core flows |

## Agents and tools

| Document | Use it for |
|----------|------------|
| [MCP agent guide](MCP-AGENT-GUIDE.md) | How agents should observe, act, wait, and compose heists |
| [MCP server README](../ButtonHeistMCP/) | Adapter behavior, runtime behavior, and environment variables |
| [CLI README](../ButtonHeistCLI/) | Terminal workflows, device targeting, output, and JSON-lines mode |
| [Command reference](reference/commands.md) | Generated Fence command names, CLI exposure, and parameters |
| [MCP tool reference](reference/mcp-tools.md) | Generated MCP tool surface projected from TheFence |

## Authoring and artifacts

| Document | Use it for |
|----------|------------|
| [Swift heist authoring](SWIFT-HEIST-AUTHORING.md) | Boundaries between Swift authoring, canonical heist source, and runtime execution |
| [Heist format](HEIST-FORMAT.md) | `.heist` package shape, generated JSON IR, and artifact rules |
| [API](API.md) | Public API invariants, surface matrix, and integration contracts |
| [Examples](../examples/README.md) | Canonical semantic commands and heist examples |

## Runtime internals

| Document | Use it for |
|----------|------------|
| [Wire protocol](WIRE-PROTOCOL.md) | Raw transport, envelopes, handshake, authentication, and wire examples |

## Security and connectivity

| Document | Use it for |
|----------|------------|
| [Authentication](AUTH.md) | Token-derived TLS PSK, token auth, session locking, and threat model |
| [USB connectivity](USB_DEVICE_CONNECTIVITY.md) | Physical-device connections over CoreDevice IPv6 tunnels without LAN scope |
| [Bonjour troubleshooting](BONJOUR_TROUBLESHOOTING.md) | mDNS, stealth mode, fixed-port workarounds, and LAN discovery issues |

## Evidence and repair

| Document | Use it for |
|----------|------------|
| [Benchmarks](BENCHMARKS.md) | Comparative traces and workflow evidence |
| [Heist Doctor](HEIST-DOCTOR.md) | Experimental repair-suggestion work over heist execution receipts |

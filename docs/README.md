# Documentation

The Button Heist docs start with the executable accessibility contract, then branch by job. Pick the path closest to what you are trying to do.

## Understand the idea

| Document | Use it for |
|----------|------------|
| [Project overview](../README.md) | Public story, setup, first heist, and receipts |
| [Accessibility contract](ACCESSIBILITY-CONTRACT.md) | The runtime loop: product semantics in, settled evidence out |
| [Architecture](ARCHITECTURE.md) | Component boundaries, execution flow, trace semantics, and failure paths |

## Connect an agent

| Document | Use it for |
|----------|------------|
| [MCP agent guide](MCP-AGENT-GUIDE.md) | How agents should observe, act, wait, and compose heists |
| [MCP server README](../ButtonHeistMCP/) | Adapter behavior, runtime behavior, and environment variables |
| [MCP tool reference](reference/mcp-tools.md) | Generated MCP tool surface projected from TheFence |

## Use the terminal

| Document | Use it for |
|----------|------------|
| [CLI README](../ButtonHeistCLI/) | Terminal workflows, device targeting, output, and JSON-lines mode |
| [Command reference](reference/commands.md) | Generated Fence command names, CLI exposure, and parameters |

## Author heists

| Document | Use it for |
|----------|------------|
| [Swift heist authoring](SWIFT-HEIST-AUTHORING.md) | Boundaries between Swift authoring, canonical source, and runtime execution |
| [Heist format](HEIST-FORMAT.md) | `.heist` package shape, generated JSON IR, and artifact rules |
| [Examples](../examples/README.md) | Copyable semantic command and heist examples |

## Embed and operate

| Document | Use it for |
|----------|------------|
| [API](API.md) | Public API invariants, surface matrix, and integration contracts |
| [Authentication](AUTH.md) | Token-derived TLS PSK, token auth, session locking, and threat model |
| [USB connectivity](USB_DEVICE_CONNECTIVITY.md) | Physical-device connections over CoreDevice IPv6 tunnels without LAN scope |
| [Bonjour troubleshooting](BONJOUR_TROUBLESHOOTING.md) | mDNS, stealth mode, fixed-port workarounds, and LAN discovery issues |
| [Wire protocol](WIRE-PROTOCOL.md) | Raw transport, envelopes, handshake, authentication, and wire examples |

## Evidence and repair

| Document | Use it for |
|----------|------------|
| [Benchmarks](BENCHMARKS.md) | Comparative traces and workflow evidence |
| [Heist Doctor](HEIST-DOCTOR.md) | Experimental repair suggestions over heist execution receipts |

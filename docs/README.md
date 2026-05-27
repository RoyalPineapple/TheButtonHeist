# Documentation

Technical documentation for Button Heist internals. The blueprints, not the sales pitch.

## Contents

| Document | Description |
|----------|-------------|
| [Architecture](ARCHITECTURE.md) | Load-bearing product contracts and the compact component map |
| [API](API.md) | Product API invariants and integration contracts; generated references own commands and parameters |
| [Command Reference](reference/commands.md) | Generated command names, CLI exposure, batch/playback eligibility, and parameters |
| [MCP Tool Reference](reference/mcp-tools.md) | Generated MCP tool surface projected from TheFence |
| [Wire Protocol](WIRE-PROTOCOL.md) | Raw TheScore transport: envelopes, handshake, authentication, TLS transport, and wire-only examples |
| [Authentication](AUTH.md) | Token auth, session locking, UI approval pending/denial/timeout states |
| [USB Connectivity](USB_DEVICE_CONNECTIVITY.md) | Connecting to physical devices over CoreDevice IPv6 tunnels without enabling LAN scope |
| [Bonjour Troubleshooting](BONJOUR_TROUBLESHOOTING.md) | MDM stealth mode workarounds |
| [Reviewer's Guide](REVIEWERS-GUIDE.md) | Quick orientation for new reviewers |

## See Also

- [Project Overview](../README.md) — Quick start and architecture

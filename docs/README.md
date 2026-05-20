# Documentation

Technical documentation for Button Heist internals. The blueprints, not the sales pitch.

## Contents

| Document | Description |
|----------|-------------|
| [Architecture](ARCHITECTURE.md) | Load-bearing product contracts and the compact component map |
| [API Reference](API.md) | Complete API for the MCP server, TheInsideJob, TheFence, TheHandoff, and CLI |
| [Wire Protocol](WIRE-PROTOCOL.md) | Protocol specification — explicit envelopes, canonical interface tree, authentication, TLS transport, and artifact-first media behavior. Versioned via product `buttonHeistVersion` (SemVer); no separate wire-protocol version. |
| [Authentication](AUTH.md) | Token auth, session locking, UI approval pending/denial/timeout states |
| [USB Connectivity](USB_DEVICE_CONNECTIVITY.md) | Connecting to physical devices over CoreDevice IPv6 tunnels without enabling LAN scope |
| [Bonjour Troubleshooting](BONJOUR_TROUBLESHOOTING.md) | MDM stealth mode workarounds |
| [Reviewer's Guide](REVIEWERS-GUIDE.md) | Quick orientation for new reviewers |
| [Crew Dossiers](dossiers/) | Per-crew-member technical deep dives |

## See Also

- [Project Overview](../README.md) — Quick start and architecture

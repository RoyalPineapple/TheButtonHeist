# Documentation

Technical documentation for Button Heist internals. The blueprints, not the sales pitch.

## Contents

| Document | Description |
|----------|-------------|
| [Architecture](ARCHITECTURE.md) | System design, component interaction, and data flow diagrams |
| [API Reference](API.md) | Complete API for the MCP server, TheInsideJob, TheFence, TheHandoff, and CLI |
| [Wire Protocol](WIRE-PROTOCOL.md) | Protocol v6.1 specification — explicit envelopes, authentication, TLS transport |
| [Authentication](AUTH.md) | Token auth, session locking, UI approval |
| [USB Connectivity](USB_DEVICE_CONNECTIVITY.md) | Connecting to physical devices over USB via CoreDevice IPv6 tunnels |
| [Versioning](VERSIONING.md) | SemVer strategy and release workflow |
| [Bonjour Troubleshooting](BONJOUR_TROUBLESHOOTING.md) | MDM stealth mode workarounds |
| [Reviewer's Guide](REVIEWERS-GUIDE.md) | Quick orientation for new reviewers |
| [Competitive Landscape](competitive-landscape.md) | How Button Heist compares to alternatives |
| [The Argument](the-argument.md) | Why this approach, why now |
| Benchmark Data | Raw results in `.context/bh-infra/results/` |
| [Crew Dossiers](dossiers/) | Per-crew-member technical deep dives |

## See Also

- [Project Overview](../README.md) — Quick start and architecture

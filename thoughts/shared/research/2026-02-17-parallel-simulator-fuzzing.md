---
date: 2026-02-17T16:30:00Z
researcher: aodawa
git_commit: cbcafba22644a09386d629287f64891c504428cd
branch: RoyalPineapple/ai-fuzz-framework
repository: minnetonka
topic: "Parallel Simulator Management for Multi-Agent Fuzzing"
tags: [research, ios-simulator, xcrun-simctl, parallel-testing, fuzzing, mcp, buttonheist]
status: complete
last_updated: 2026-02-17
last_updated_by: aodawa
---

# Research: Parallel Simulator Management for Multi-Agent Fuzzing

**Date**: 2026-02-17T16:30:00Z
**Researcher**: aodawa
**Git Commit**: cbcafba
**Branch**: RoyalPineapple/ai-fuzz-framework
**Repository**: minnetonka

## Research Question

How can sub-agents spin up new iOS simulators to run parallel fuzzers? What skills are needed for simulator lifecycle management?

## Summary

The architecture already supports parallel fuzzing. The ButtonHeist MCP server uses a **process-per-device model** — each MCP server instance connects to one simulator via Bonjour discovery, filtering by simulator UDID or short ID. The multi-simulator discovery infrastructure (unique per-launch session IDs, `list_devices` tool, `--device` / `BUTTONHEIST_DEVICE` filtering) is fully implemented. What's missing is the **simulator lifecycle layer** — the skills that create, boot, deploy, and clean up simulators so fuzzer agents can spin up their own test environments.

`xcrun simctl` provides all the building blocks: `create` or `clone` to make new simulators, `boot` to start them, `install`/`launch` to deploy the app, and `shutdown`/`delete` to clean up. Practical limits are 5-10 simulators on most Macs (up to 14 with system tuning), each consuming ~1.3GB RAM and ~150 processes.

## Detailed Findings

### 1. Current Multi-Simulator Architecture

The ButtonHeist system already supports multiple simultaneous simulators:

**InsideMan (iOS framework)** advertises via Bonjour as `_buttonheist._tcp` with service name format `AppName-DeviceName#shortId`. Each instance gets a unique 8-char session ID. TXT records include `simudid` (the `SIMULATOR_UDID` environment variable) and `vendorid`.
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:160-189` — service advertisement
- `ButtonHeist/Sources/Wheelman/DeviceDiscovery.swift:55-95` — Bonjour discovery

**MCP server** connects to one device, selected at startup via `--device` CLI flag or `BUTTONHEIST_DEVICE` environment variable. The filter matches against service name, app name, device name, short ID prefix, simulator UDID prefix, or vendor ID prefix (all case-insensitive).
- `ButtonHeistMCP/Sources/main.swift:705-716` — device matching
- `ButtonHeistMCP/Sources/main.swift:724-731` — filter parsing

**Process-per-device model** is the explicit design choice:
- `thoughts/shared/plans/2026-02-13-multi-sim-discovery.md:44-46` — "Not adding support for one client connected to many devices simultaneously. Separate processes per simulator is the model."

**`list_devices` tool** returns all discovered devices (not just the connected one), including `simulatorUDID` and `shortId`.
- `ButtonHeistMCP/Sources/main.swift:348-367` — tool handler

### 2. Parallel Fuzzing Architecture (How It Would Work)

```
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│  Fuzzer A    │   │  Fuzzer B    │   │  Fuzzer C    │
│  (agent)     │   │  (agent)     │   │  (agent)     │
└──────┬───────┘   └──────┬───────┘   └──────┬───────┘
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ MCP Server A │  │ MCP Server B │  │ MCP Server C │
│ --device     │  │ --device     │  │ --device     │
│   <UDID-A>   │  │   <UDID-B>   │  │   <UDID-C>   │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Simulator A  │  │ Simulator B  │  │ Simulator C  │
│ (iPhone 16)  │  │ (iPhone 16)  │  │ (iPhone 16)  │
│ InsideMan    │  │ InsideMan    │  │ InsideMan    │
└──────────────┘  └──────────────┘  └──────────────┘
```

Each layer is independent:
- Each simulator runs in its own process (managed by CoreSimulator)
- Each app instance has its own InsideMan server on an auto-assigned port
- Each MCP server is a separate process targeting its specific simulator
- Each fuzzer agent talks to its own MCP server

### 3. xcrun simctl Capabilities

#### Creating Simulators

```bash
# List available device types and runtimes
xcrun simctl list devicetypes --json
xcrun simctl list runtimes --json

# Create a new simulator
xcrun simctl create "Fuzzer-1" com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro com.apple.CoreSimulator.SimRuntime.iOS-18-0
# Returns: new UDID

# Clone an existing simulator (copies all apps and state)
xcrun simctl clone <source-UDID> "Fuzzer-2"
# Returns: new UDID
```

#### Booting and Deploying

```bash
# Boot (can boot multiple simultaneously)
xcrun simctl boot <UDID>

# Wait for boot to complete
xcrun simctl bootstatus <UDID>

# Install and launch app
xcrun simctl install <UDID> /path/to/App.app
xcrun simctl launch <UDID> com.bundle.identifier
```

#### Cleanup

```bash
# Terminate app
xcrun simctl terminate <UDID> com.bundle.identifier

# Shutdown simulator
xcrun simctl shutdown <UDID>

# Delete simulator
xcrun simctl delete <UDID>

# Erase all content (keep simulator)
xcrun simctl erase <UDID>
```

#### Resource Limits

| Hardware | Comfortable Limit | Max with Tuning |
|----------|------------------|-----------------|
| M1 MacBook Pro (16GB) | 5 simulators | 8-10 |
| M1 Mac Mini (16GB) | 10 simulators | 14 |
| M-series (32GB+) | 10-12 simulators | 14+ |

Per simulator: ~1.3GB RAM, ~150 processes, ~3,000 file descriptors.

Default macOS limits: 2,666 max processes per user, 49,152 file descriptors. For 10+ simulators, system limits need to be raised via LaunchDaemons.

#### Headless Mode

Simulators can run without Simulator.app window — just don't `open -a Simulator`. The `xcrun simctl boot` command boots the simulator service without requiring a GUI. All capabilities (app launch, screenshots, etc.) work headless.

### 4. Existing Simulator References in Codebase

- `CLAUDE.md` — Simulator Quick Start section with full build/deploy workflow
- `ai-fuzzer/references/simulator-snapshots.md` — Snapshot save/restore for state management
- `ai-fuzzer/.mcp.json` — MCP server config with `BUTTONHEIST_DEVICE` env var
- `thoughts/shared/plans/2026-02-13-multi-sim-discovery.md` — Multi-sim discovery implementation plan (completed)
- `AccessibilitySnapshot/Scripts/github/prepare-simulators.sh` — CI simulator runtime setup

### 5. What Skills Are Needed

The fuzzer framework needs skills that handle the full simulator lifecycle so sub-agents can self-provision. Based on the research, these are the needed capabilities:

**Skill 1: Provision a simulator** — Create (or clone) a simulator, boot it, build the app, install it, launch it, verify the Bonjour service is advertising. Return the UDID.

**Skill 2: Start an MCP server for a specific simulator** — Launch a `buttonheist-mcp` process with `--device <UDID>`, verify it connects. Return the connection info.

**Skill 3: Tear down a simulator** — Terminate the app, shutdown the simulator, optionally delete it. Clean up any MCP server processes.

**Skill 4: Orchestrate parallel fuzzers** — Spin up N simulators, start N MCP servers, launch N fuzzer agents (each with a different strategy or swarm config), collect results.

### 6. Key Design Decisions for Parallel Fuzzing

**App build**: Only needs to happen once. The `.app` bundle can be installed on multiple simulators.

**Simulator identity**: Each simulator has a unique UDID. The MCP server can target by UDID prefix. InsideMan automatically picks up the `SIMULATOR_UDID` env var and includes it in Bonjour TXT records.

**MCP server lifecycle**: Each server is a separate process. Can be launched with `BUTTONHEIST_DEVICE=<UDID> ../ButtonHeistMCP/.build/release/buttonheist-mcp`. Each would need to be a background process.

**Session notes isolation**: Each fuzzer agent writes to its own session notes file (already unique by timestamp in `session/fuzzsession-*.md`). No conflict.

**Strategy diversity**: Different fuzzers can use different strategies. With swarm testing, each session randomly restricts its action palette, maximizing combined coverage.

**Result aggregation**: After all fuzzers complete, a report aggregator reads all session notes files and produces a combined report.

## Code References

- `ButtonHeistMCP/Sources/main.swift:705-716` — Device matching logic
- `ButtonHeistMCP/Sources/main.swift:724-731` — Device filter parsing from CLI/env
- `ButtonHeistMCP/Sources/main.swift:348-367` — `list_devices` tool handler
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:160-189` — Bonjour service advertisement with UDID
- `ButtonHeist/Sources/Wheelman/DeviceDiscovery.swift:55-95` — Device discovery
- `ButtonHeist/Sources/Wheelman/DiscoveredDevice.swift:5-67` — Device data structure
- `ButtonHeist/Sources/ButtonHeist/HeistClient.swift:85-132` — Single-connection model
- `CLAUDE.md:1-65` — Simulator Quick Start
- `ai-fuzzer/.mcp.json` — MCP server configuration

## Architecture Documentation

### Connection Flow for Parallel Setup

1. Build app once: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp ...`
2. For each fuzzer instance:
   a. `xcrun simctl create "Fuzzer-N" <device-type> <runtime>` → get UDID
   b. `xcrun simctl boot <UDID>`
   c. `xcrun simctl install <UDID> /path/to/app.app`
   d. `xcrun simctl launch <UDID> com.buttonheist.testapp`
   e. Wait for Bonjour advertisement (dns-sd or MCP discovery)
   f. Launch MCP server: `BUTTONHEIST_DEVICE=<UDID> buttonheist-mcp &`
   g. Launch fuzzer agent with its own strategy and session notes

### MCP Server Multi-Instance Configuration

Each MCP server can be configured in `.mcp.json` or launched with env vars:

```json
{
  "mcpServers": {
    "buttonheist-1": {
      "command": "../ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "UDID-1"],
      "env": {}
    },
    "buttonheist-2": {
      "command": "../ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "UDID-2"],
      "env": {}
    }
  }
}
```

Or dynamically via environment:
```bash
BUTTONHEIST_DEVICE=<UDID-1> buttonheist-mcp &
BUTTONHEIST_DEVICE=<UDID-2> buttonheist-mcp &
```

## Related Research

- `thoughts/shared/research/2026-02-17-fuzzing-beyond-randomness.md` — Fuzzing techniques research (swarm testing for parallel diversity)
- `thoughts/shared/plans/2026-02-13-multi-sim-discovery.md` — Multi-simulator discovery implementation plan (completed)

## Open Questions

1. **MCP server as sub-agent tool**: How do sub-agents get their own MCP server? The current `.mcp.json` is static. Would need dynamic MCP server spawning or pre-configured multi-server configs.
2. **Agent orchestration**: How does a parent agent spawn child fuzzer agents, each with their own MCP connection? This may require Claude Code's task/subagent architecture.
3. **Build caching**: Does `xcodebuild` cache well enough that the second build is fast? Or should we build once and share the `.app` bundle?
4. **Resource monitoring**: How do we detect when the machine is overloaded (too many simulators)? Should the orchestrator check available RAM before spawning more?
5. **Result merging**: How do we combine findings from multiple parallel fuzzer sessions into a single report? Session notes are per-agent, but we want a unified view.
6. **Simulator reuse**: Should we create fresh simulators each time, or maintain a pool of pre-created simulators to avoid creation overhead?

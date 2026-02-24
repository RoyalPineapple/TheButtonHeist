# Direct Connect: --host/--port Flags + Env Vars

## Overview

Add `--host` and `--port` flags (plus `BUTTONHEIST_HOST`/`BUTTONHEIST_PORT`/`BUTTONHEIST_DEVICE` env vars) to skip Bonjour discovery when the address is already known. Each CLI command still opens a fresh TCP connection, but eliminates the 1-2 second discovery overhead.

## Current State Analysis

Every device-connecting CLI command goes through Bonjour discovery:
1. Start NWBrowser → poll every 100ms → wait for matching device (1-2s)
2. Resolve Bonjour service endpoint → TCP connect
3. Auth handshake → execute command → disconnect

Three separate connection paths exist:
- **`DeviceConnector`** (`DeviceConnector.swift`) — used by 10+ commands (action, touch, type, screenshot, copy, paste, cut, select, select-all, dismiss-keyboard)
- **`CLIRunner`** (`CLIRunner.swift:68-102`) — watch command, event-driven via `onDeviceDiscovered` callback
- **`SessionRunner`** (`SessionCommand.swift:104-139`) — session command, polling-based discovery

All three ultimately call `client.connect(to: DiscoveredDevice)`, which creates `NWConnection(to: device.endpoint, using: .tcp)`. Network.framework accepts both `.service` (Bonjour) and `.hostPort` (direct) endpoints — no changes needed at the framework level.

### Key Discoveries:
- `NWEndpoint.hostPort(host:port:)` works as a drop-in replacement for Bonjour-resolved endpoints — same `NWConnection` API
- `BUTTONHEIST_TOKEN` env var already exists in `DeviceConnector.swift:18` — follow the same pattern
- `BUTTONHEIST_DEVICE` env var is documented in README but doesn't exist in code
- For simulators, the address is always `127.0.0.1:1455` (loopback binding + fixed port from Info.plist)
- For USB devices, the IPv6 address is discoverable via `lsof` (e.g., `fd9a:6190:eed7::1:1455`)

## Desired End State

```bash
# Direct connection — no discovery, ~50ms instead of ~2s
buttonheist --host 127.0.0.1 --port 1455 watch --once --format json

# Env vars — set once, all subsequent commands skip discovery
export BUTTONHEIST_HOST=127.0.0.1
export BUTTONHEIST_PORT=1455
buttonheist watch --once --format json
buttonheist touch tap --identifier loginButton --format json

# Device filter via env var (still uses discovery, but no --device flag needed)
export BUTTONHEIST_DEVICE=DEADBEEF-1234
buttonheist watch --once

# Flags override env vars
export BUTTONHEIST_HOST=127.0.0.1
buttonheist --host 192.168.1.50 --port 1455 watch --once  # uses 192.168.1.50
```

### Verification:
- `buttonheist --host 127.0.0.1 --port 1455 watch --once` returns hierarchy without Bonjour
- `BUTTONHEIST_HOST=127.0.0.1 BUTTONHEIST_PORT=1455 buttonheist watch --once` works
- `BUTTONHEIST_DEVICE=<udid> buttonheist watch --once` filters by device
- All existing `--device` usage still works (backwards compatible)
- `buttonheist list` does NOT accept `--host`/`--port` (discovery-only command)

## What We're NOT Doing

- Not adding persistent session/connection pooling (each command still opens/closes a TCP connection)
- Not adding mDNS-level caching or resolution shortcuts
- Not changing `HeistClient`, `DeviceConnection`, or any Wheelman framework code
- Not changing the `list` command (it's inherently a discovery operation)

## Implementation Approach

The change is concentrated in the CLI layer only. We synthesize a `DiscoveredDevice` with a `.hostPort` endpoint when host+port are known, then feed it into the existing connection pipeline. No framework changes needed.

Priority order for host/port resolution:
1. `--host`/`--port` flags (highest)
2. `BUTTONHEIST_HOST`/`BUTTONHEIST_PORT` env vars
3. Bonjour discovery with `--device` or `BUTTONHEIST_DEVICE` filter (default)

## Phase 1: DeviceConnector + Env Var Support

### Overview
Update `DeviceConnector` to accept host/port params and skip discovery when provided. Add `BUTTONHEIST_DEVICE` env var support. This covers 10+ commands in one change.

### Changes Required:

#### 1. DeviceConnector — add direct connection path
**File**: `ButtonHeistCLI/Sources/DeviceConnector.swift`

Add `host` and `port` params. When both are provided, create a synthetic `DiscoveredDevice` and skip Bonjour. Also add `BUTTONHEIST_DEVICE` env var fallback for the device filter.

```swift
import Network  // needed for NWEndpoint

@MainActor
final class DeviceConnector {
    let client = HeistClient()
    private let deviceFilter: String?
    private let quiet: Bool
    private let discoveryTimeout: UInt64
    private let connectionTimeout: UInt64
    private let directHost: String?
    private let directPort: UInt16?

    init(deviceFilter: String?, host: String? = nil, port: UInt16? = nil,
         token: String? = nil, quiet: Bool = false,
         discoveryTimeout: TimeInterval = 5, connectionTimeout: TimeInterval = 5) {
        // Flags override env vars
        self.directHost = host
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_HOST"]
        self.directPort = port
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_PORT"].flatMap { UInt16($0) }
        self.deviceFilter = deviceFilter
            ?? ProcessInfo.processInfo.environment["BUTTONHEIST_DEVICE"]
        self.quiet = quiet
        self.discoveryTimeout = UInt64(discoveryTimeout * 1_000_000_000)
        self.connectionTimeout = UInt64(connectionTimeout * 1_000_000_000)
        self.client.token = token ?? ProcessInfo.processInfo.environment["BUTTONHEIST_TOKEN"]
    }

    func connect() async throws {
        // Direct connection — skip Bonjour entirely
        if let host = directHost, let port = directPort {
            if !quiet { logStatus("Connecting to \(host):\(port)...") }
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: port)
            )
            let device = DiscoveredDevice(
                id: "\(host):\(port)",
                name: "\(host):\(port)",
                endpoint: endpoint
            )
            try await connectToDevice(device)
            return
        }

        // Bonjour discovery path (existing logic)
        if !quiet { logStatus("Searching for iOS devices...") }
        client.startDiscovery()
        // ... existing discovery + filter logic unchanged ...
    }
    // ...
}
```

Extract the "connect to a known device and wait" logic into a shared `connectToDevice(_:)` method to avoid duplication between the direct and discovery paths.

#### 2. All DeviceConnector-using commands — add --host and --port flags
**Files**: `ActionCommand.swift`, `TouchCommand.swift`, `TypeCommand.swift`, `ScreenshotCommand.swift`, `TextEditCommands.swift`, `DismissKeyboardCommand.swift`

Add two options to each command (next to the existing `--device` option):

```swift
@Option(name: .long, help: "Direct host address (skip Bonjour discovery)")
var host: String?

@Option(name: .long, help: "Direct port number (skip Bonjour discovery)")
var port: UInt16?
```

Update each `DeviceConnector(...)` call to pass `host: host, port: port`.

**TouchCommand note**: The `sendTouchGesture` helper already takes a `device: String?` param. Add `host: String?` and `port: UInt16?` params and thread them through. Each of the 9 touch subcommands gets the two new options.

### Success Criteria:

#### Automated Verification:
- [ ] `cd ButtonHeistCLI && swift build -c release` succeeds
- [ ] `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build` succeeds

---

## Phase 2: CLIRunner (watch command) + SessionRunner (session command)

### Overview
Update the two remaining connection paths so `--host`/`--port` work with `watch` and `session` commands.

### Changes Required:

#### 1. CLIOptions — add host/port fields
**File**: `ButtonHeistCLI/Sources/main.swift`

```swift
struct CLIOptions {
    let format: OutputFormat
    let once: Bool
    let quiet: Bool
    let timeout: Int
    let verbose: Bool
    let device: String?
    let host: String?
    let port: UInt16?
}
```

Add `--host` and `--port` options to `WatchCommand`, thread them into `CLIOptions`.

#### 2. CLIRunner — direct connect path
**File**: `ButtonHeistCLI/Sources/CLIRunner.swift`

In `run()`, when `host` + `port` are set (from options or env vars), skip `startDiscovery()`. Instead, create a synthetic `DiscoveredDevice` and call `client.connect(to:)` directly.

```swift
func run() async throws {
    setupSignalHandlers()
    setupClientCallbacks()

    let effectiveHost = options.host ?? ProcessInfo.processInfo.environment["BUTTONHEIST_HOST"]
    let effectivePort = options.port ?? ProcessInfo.processInfo.environment["BUTTONHEIST_PORT"].flatMap { UInt16($0) }

    if let host = effectiveHost, let port = effectivePort {
        // Direct connection — skip discovery
        if !options.quiet { logStatus("Connecting to \(host):\(port)...") }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let device = DiscoveredDevice(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
        client.connect(to: device)
    } else {
        // Bonjour discovery (existing path)
        if !options.quiet { logStatus("Searching for iOS devices...") }
        client.startDiscovery()
    }
    // ... rest unchanged ...
}
```

Also apply `BUTTONHEIST_DEVICE` env var fallback in the `onDeviceDiscovered` callback's filter check.

#### 3. SessionRunner — direct connect path
**File**: `ButtonHeistCLI/Sources/SessionCommand.swift`

Add `host: String?` and `port: UInt16?` params to `SessionRunner.init()`. Add `--host`/`--port` options to `SessionCommand`. In `SessionRunner.connect()`, check for direct host/port before starting Bonjour:

```swift
private func connect() async throws {
    let effectiveHost = directHost ?? ProcessInfo.processInfo.environment["BUTTONHEIST_HOST"]
    let effectivePort = directPort ?? ProcessInfo.processInfo.environment["BUTTONHEIST_PORT"].flatMap { UInt16($0) }

    if let host = effectiveHost, let port = effectivePort {
        logStatus("Connecting to \(host):\(port)...")
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let device = DiscoveredDevice(id: "\(host):\(port)", name: "\(host):\(port)", endpoint: endpoint)
        // ... connect to device, wait for connected state ...
        return
    }

    // Existing Bonjour discovery path unchanged
    logStatus("Searching for iOS devices...")
    client.startDiscovery()
    // ...
}
```

Also apply `BUTTONHEIST_DEVICE` env var fallback for `deviceFilter`.

### Success Criteria:

#### Automated Verification:
- [ ] `cd ButtonHeistCLI && swift build -c release` succeeds
- [ ] `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build` succeeds

---

## Phase 3: Documentation

### Overview
Update docs to cover the new flags and env vars.

### Changes Required:

#### 1. README.md
- Add `--host`/`--port` to CLI Usage section
- Add env vars table (`BUTTONHEIST_HOST`, `BUTTONHEIST_PORT`, `BUTTONHEIST_DEVICE`, `BUTTONHEIST_TOKEN`)
- Update "Connect with the CLI" section with direct-connect example

#### 2. CLAUDE.md
- Update "Verify" section to mention `--host`/`--port` as optimization
- Add env var tip for repeated CLI use during development

#### 3. docs/API.md
- Add `--host`/`--port` to each command's OPTIONS section
- Add "Environment Variables" section to CLI Reference
- Update CLI overview paragraph

#### 4. docs/ARCHITECTURE.md
- Update "CLI Agent Flow" to show direct-connect path as the fast path

#### 5. ai-fuzzer/SKILL.md + command files
- Update CLI Quick Reference to mention `--host`/`--port` for faster connections
- Note env var setup in fuzzer initialization steps

### Success Criteria:

#### Automated Verification:
- [ ] `grep -l "BUTTONHEIST_HOST" README.md docs/API.md` returns both files
- [ ] `grep -l "\-\-host" docs/API.md` returns the file
- [ ] No broken markdown formatting (visual review)

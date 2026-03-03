# TheMastermind - The Outside Coordinator

> **File:** `ButtonHeist/Sources/TheButtonHeist/TheMastermind.swift`
> **Platform:** macOS 14.0+
> **Role:** Observable macOS client API wrapping TheWheelman for SwiftUI and callback consumers

## Responsibilities

TheMastermind is the macOS-side counterpart to TheInsideJob:

1. **Observable state** for SwiftUI integration (`@Observable`) - mirrors TheWheelman's state
2. **Callback API** for non-SwiftUI consumers (CLI, MCP) via typed closures
3. **Configuration forwarding** - proxies `token`, `forceSession`, `driverId`, `autoSubscribe` to TheWheelman
4. **Async wait methods** for action results, screenshots, interface, recordings
5. **Display name disambiguation** when multiple devices share names (delegated to TheWheelman)
6. **Discovery and connection** delegation to TheWheelman

> **Note:** TheMastermind replaced the former `TheClient` class. It is a thin `@Observable` wrapper
> that delegates all discovery, connection, keepalive, and reconnect logic to `TheWheelman`.

## Architecture Diagram

```mermaid
graph TD
    subgraph TheMastermind["TheMastermind (@Observable, @MainActor)"]
        Wheelman["TheWheelman - discovery, connection, keepalive"]

        subgraph ObservableState["Observable State"]
            Devices["discoveredDevices: [DiscoveredDevice]"]
            Connected["connectedDevice: DiscoveredDevice?"]
            ConnState["connectionState: ConnectionState"]
            CurrentIF["currentInterface: Interface?"]
            CurrentScreen["currentScreen: ScreenPayload?"]
            ServerInfo["serverInfo: ServerInfo?"]
            IsRecording["isRecording: Bool"]
        end

        subgraph Callbacks["Callbacks"]
            OnDevice["onDeviceDiscovered / onDeviceLost"]
            OnConn["onConnected / onDisconnected"]
            OnIF["onInterfaceUpdate"]
            OnAction["onActionResult"]
            OnScreen["onScreen"]
            OnRec["onRecordingStarted / onRecording / onRecordingError"]
            OnToken["onTokenReceived"]
            OnAuth["onAuthFailed / onSessionLocked"]
        end
    end

    Wheelman --> ObservableState
    Wheelman --> Callbacks
```

## Connection Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Disconnected

    Disconnected --> Discovering: startDiscovery()
    Discovering --> Disconnected: stopDiscovery()

    Disconnected --> Connecting: connect(to: device)
    Connecting --> Connected: auth handshake complete
    Connecting --> Failed: auth failed / timeout

    Connected --> Disconnected: disconnect()
    Connected --> Disconnected: connection lost

    Failed --> Connecting: retry
    Failed --> Disconnected: give up

    state Connected {
        [*] --> Subscribed: auto-subscribe
        Subscribed --> Keepalive: ping every 3s
    }
```

## Wait Method Pattern

```mermaid
flowchart TD
    Call["waitForActionResult(timeout: 15)"]
    Call --> Setup["withCheckedThrowingContinuation"]
    Setup --> Hook["Set onActionResult callback"]
    Setup --> Timer["Start timeout Task (@MainActor)"]

    Hook --> Result{"Result received?"}
    Result -->|yes| Check{"didResume?"}
    Check -->|no| Resume1["resume(returning: result) - didResume = true"]
    Check -->|yes| Skip1["Skip (already resumed)"]

    Timer --> Timeout{"Timeout elapsed?"}
    Timeout -->|yes| Check2{"didResume?"}
    Check2 -->|no| Resume2["resume(throwing: timeout) - didResume = true"]
    Check2 -->|yes| Skip2["Skip (already resumed)"]
```

## Delegation Pattern

TheMastermind delegates all core operations to TheWheelman:

| TheMastermind method | Delegates to |
|---------------------|-------------|
| `startDiscovery()` | `wheelman.startDiscovery()` |
| `stopDiscovery()` | `wheelman.stopDiscovery()` |
| `connect(to:)` | `wheelman.connect(to:)` |
| `disconnect()` | `wheelman.disconnect()` |
| `send(_:)` | `wheelman.send(_:)` |
| `requestInterface()` | `wheelman.send(.requestInterface)` |
| `displayName(for:)` | `wheelman.displayName(for:)` |
| `token` / `forceSession` / `driverId` / `autoSubscribe` | `wheelman.token` / etc. |

The `wireUpWheelman()` method (called from `init`) connects all of TheWheelman's callbacks
to update TheMastermind's observable state and forward to TheMastermind's own callbacks.

# Button Heist API Reference

Complete API documentation for TheInsideJob (iOS), TheFence (command dispatch), TheHandoff (connection lifecycle), and the CLI.

## TheInsideJob

**Import**: `import TheInsideJob`
**Platform**: iOS 17.0+
**Location**: `ButtonHeist/Sources/TheInsideJob/TheInsideJob.swift`

### Overview

TheInsideJob automatically starts when your app loads via ObjC `+load`. No manual initialization is required - just link the framework and configure your Info.plist.

### Auto-Start Behavior

When the TheInsideJob framework loads:
1. Reads configuration from environment variables or Info.plist
2. Creates a TLS TCP server on an OS-assigned port
3. Publishes Bonjour as `_buttonheist._tcp` only when network scope is enabled
4. Starts settle-driven UI change detection

### Configuration

**Environment variables (highest priority):**
```bash
INSIDEJOB_POLLING_INTERVAL=2.0       # Settle-driven polling timeout in seconds (min: 0.5)
INSIDEJOB_DISABLE=true               # Disable auto-start
INSIDEJOB_DISABLE_FINGERPRINTS=true  # Suppress visual tap/gesture indicators
INSIDEJOB_TOKEN=my-secret-token      # Auth token (fresh UUID auto-generated each launch if not set)
INSIDEJOB_ID=my-instance             # Human-readable instance identifier
INSIDEJOB_SESSION_TIMEOUT=30         # Session release timeout in seconds (default: 30, min: 1)
INSIDEJOB_SCOPE=simulator,usb        # Allowed scopes (default: simulator,usb; add network to publish Bonjour)
```

**Info.plist (fallback):**
```xml
<key>InsideJobPollingInterval</key>
<real>1.0</real>
<key>InsideJobDisableAutoStart</key>
<false/>
<key>InsideJobDisableFingerprints</key>
<false/>
<key>InsideJobToken</key>
<string>my-secret-token</string>
<key>InsideJobInstanceId</key>
<string>my-instance</string>
<key>InsideJobScope</key>
<array>
    <string>simulator</string>
    <string>usb</string>
</array>
```

**Client-side:** Set `BUTTONHEIST_TOKEN` environment variable to authenticate with the server.

### TheInsideJob Class

Main server class. Use the shared singleton instance.

```swift
@MainActor
public final class TheInsideJob
```

#### Properties

##### shared

```swift
public static var shared: TheInsideJob
```

Singleton instance. Automatically initialized on framework load.

##### isRunning

```swift
private var isRunning: Bool
```

Whether the server is currently running. This property is private; external code should not need to check server state directly.

#### Methods

##### configure(token:instanceId:allowedScopes:port:)

```swift
public static func configure(token: String? = nil, instanceId: String? = nil, allowedScopes: Set<ConnectionScope>? = nil, port: UInt16 = 0)
```

Configure the shared instance with an auth token, instance identifier, allowed scopes, and preferred port. Must be called before `start()` if not using Info.plist/environment variables.

**Parameters**:
- `token`: Auth token for client authentication. If nil, auto-generated at startup.
- `instanceId`: Human-readable instance identifier. If nil, falls back to a short UUID prefix.
- `allowedScopes`: Set of connection scopes the server will accept. If nil, startup/default scopes are used (`simulator,usb` unless overridden by `INSIDEJOB_SCOPE` or `InsideJobScope`).
- `port`: Preferred TCP port for the server. Pass 0 (the default) for an OS-assigned ephemeral port. The Info.plist (`InsideJobPort`) and environment variable (`INSIDEJOB_PORT`) fallback is handled by the auto-start mechanism in `AutoStart.swift`, not by `configure()` itself.

**Note**: Normally not needed - use Info.plist or environment variable configuration instead.

##### start()

```swift
public func start() async throws
```

Start the TLS TCP server. Listener setup fails closed if the TLS identity or TLS transport parameters cannot be created. Bonjour advertisement begins only when the configured scopes include `.network`.

**Note**: Called automatically on framework load. Manual calls are rarely needed.

**Throws**: TLS setup or network errors if the listener fails to start.

##### stop()

```swift
public func stop() async
```

Stop the server, disconnect all clients, and stop Bonjour advertisement if it was active.

##### startPolling(interval:)

```swift
public func startPolling(interval: TimeInterval = 1.0)
```

Enable automatic polling for UI changes.

**Note**: Called automatically on framework load with 2.0 second settle timeout. Polling is settle-driven — wakes on TheTripwire settle events rather than a fixed timer.

**Parameters**:
- `interval`: Maximum seconds between settle checks (default 2.0, min 0.5). The polling loop awaits `tripwire.waitForAllClear(timeout:)` rather than sleeping for a fixed interval.

##### stopPolling()

```swift
public func stopPolling()
```

Stop automatic polling.

##### notifyChange()

```swift
public func notifyChange()
```

Mark the hierarchy as changed so the next settled Tripwire pulse refreshes Button Heist's accessibility capture.

### Interaction Philosophy: Activation-First

TheInsideJob follows an **activation-first** strategy for all element interactions:

1. **Try `accessibilityActivate()` first** -- TheBrains refreshes live target state, resolves the element to a live object and geometry snapshot, then calls the element's native accessibility activation method. This is the most reliable path because it mirrors how VoiceOver activates controls and respects custom activation behavior.

2. **Fall back to synthetic tap** -- If activation returns `false` or the element does not support it, TheSafecracker injects a synthetic tap at the fresh live activation point. If live geometry cannot be acquired, the command fails with structured diagnostics instead of tapping a cached coordinate.

The same pattern applies to `increment`/`decrement` (native accessibility API first). The `one_finger_tap` command is a pure synthetic tap with no activation-first logic — it is a low-level escape hatch for when coordinate-precise touch injection is needed.

**Why activation-first matters:**
- Native activation respects custom `accessibilityActivate()` overrides
- It works correctly with complex controls (e.g., custom toggle implementations)
- Synthetic taps can miss if the coordinate is occluded by an overlay or the view hierarchy has changed

When a synthetic tap fallback occurs, a debug log is emitted so the behavior is observable.

### Touch Gesture & Text Input System (TheSafecracker)

TheInsideJob uses `TheSafecracker` internally for handling all touch gesture and text input commands. TheSafecracker is an **internal** type -- only TheInsideJob creates and holds the instance. It supports single-finger gestures, multi-touch gestures via synthetic UITouch/IOHIDEvent injection, and text entry via UIKeyboardImpl. TheSafecracker never holds live UIView pointers; it receives only screen coordinates and action outcomes from TheBrains after targets are resolved from current element state.

**Supported gestures:**
- `one_finger_tap` - Single tap at a point (low-level escape hatch; prefer `activate` for element interactions)
- `long_press` - Long press with configurable duration
- `swipe` - Quick swipe between two points
- `drag` - Slow drag between two points (for sliders, reordering)
- `pinch` - Two-finger pinch/zoom
- `rotate` - Two-finger rotation
- `twoFingerTap` - Simultaneous two-finger tap
- `draw_path` - Trace through a sequence of waypoints (polyline)
- `draw_bezier` - Trace through cubic bezier segments sampled server-side

**Text input (via UIKeyboardImpl):**
- `typeText` - Inject text character-by-character via `addInputString:`
- `isKeyboardVisible` - Check if the software keyboard is showing

Text input uses the same private API approach as KIF (Keep It Functional). The iOS keyboard is rendered by a remote process, so individual key views aren't accessible from within the app. UIKeyboardImpl's `addInputString:` bypasses the visual keyboard entirely, injecting text directly into the input system. This handles all characters (uppercase, symbols, `@`, `.`, etc.) without needing keyboard mode switching.

**Injection stack:**
1. `SyntheticTouchFactory` - Creates UITouch instances via private API IMP invocation
2. `IOHIDEventBuilder` - Creates IOHIDEvent hand events with per-finger child events
3. `SyntheticEventFactory` - Creates fresh UIEvent per touch phase (iOS 26 compatible)
4. `UIApplication.sendEvent()` - Dispatches the synthetic events

**Key implementation notes:**
- All private API calls use direct IMP invocation (`method(for:)` + `@convention(c)`) to avoid `perform(_:with:)` boxing non-object types
- IOKit function pointers loaded via `dlsym` use `@convention(c)` types for correct 8-byte pointer size
- Multi-touch events use unique finger identity/index per finger for proper tracking
- `windowForPoint()` filters out `FingerprintWindow` instances by type check

### Fingerprint Tracking

Visual interaction feedback for taps and continuous gestures. All overlays are displayed via a passthrough `FingerprintWindow` (does not intercept touches). Recordings include the overlay because `captureScreenForRecording()` draws all windows, including `FingerprintWindow`.

**Instant fingerprints** (`showFingerprint(at:)`):
- On successful tap/activate, a 40pt white circle appears at the interaction point
- Scales up to 1.5x and fades out over 0.8 seconds

**Continuous gesture tracking** (`beginTrackingFingerprints` / `updateTrackingFingerprints` / `endTrackingFingerprints`):
- Active during swipe, drag, long press, pinch, rotate, and draw path gestures
- Shows one circle per finger (e.g., 2 circles for pinch/rotate)
- Fast animate in: 0.12 seconds (scale from 0.1x to 1.0x)
- Circles follow touch positions in real-time via `TheSafecracker.onGestureMove` callback
- Slow animate out: 0.6 seconds (scale to 1.5x + fade)

**Recording integration**:
- `FingerprintWindow`: Live UIView-based overlay for on-device display (window level `statusBar + 100`)
- Recordings include fingerprints because `captureScreenForRecording()` draws all windows (including `FingerprintWindow`) via `drawHierarchy`

### Platform Support

- **iPhone**: All screen sizes supported
- **iPad**: Single-app mode supported. Multi-window (Split View, Slide Over, Stage Manager) is not supported — the framework assumes single-window coordinate space
- **Accessibility settings**: The framework reads the iOS accessibility tree but does not adapt to system accessibility preference changes (Dynamic Type, Reduce Motion, etc.)

---

## TheHandoff (macOS Connection Lifecycle)

**Import**: `import ButtonHeist`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/TheButtonHeist/TheHandoff/TheHandoff.swift`

### TheHandoff

Client-side session manager that owns the full device lifecycle: discovery, connection, keepalive, auto-reconnect, and session state tracking. TheFence owns a TheHandoff instance and talks to it directly.

```swift
@ButtonHeistActor
public final class TheHandoff
```

#### State Properties

| Property | Type | Description |
|----------|------|-------------|
| `discoveredDevices` | `[DiscoveredDevice]` | Devices found via Bonjour discovery |
| `connectedDevice` | `DiscoveredDevice?` | Currently connected device |
| `connectionPhase` | `ConnectionPhase` | Connection lifecycle state machine (disconnected/connecting/connected/failed) |
| `reconnectPolicy` | `ReconnectPolicy` | Whether auto-reconnect fires on disconnect (disabled/enabled) |
| `recordingPhase` | `RecordingPhase` | Recording lifecycle state machine (idle/recording) |
| `serverInfo` | `ServerInfo?` | Server info received after connecting |
| `isConnected` | `Bool` | Whether transport is connected |
| `isDiscovering` | `Bool` | Whether Bonjour discovery is active |
| `isRecording` | `Bool` | Whether screen recording is in progress |

#### Callback Properties

| Callback | Type | Description |
|----------|------|-------------|
| `onDeviceFound` | `((DiscoveredDevice) -> Void)?` | New device discovered |
| `onDeviceLost` | `((DiscoveredDevice) -> Void)?` | Device no longer available |
| `onConnectionStateChanged` | `((ConnectionPhase) -> Void)?` | Connection lifecycle state changed |
| `onInterface` | `((Interface, String?) -> Void)?` | Hierarchy received (with optional requestId) |
| `onActionResult` | `((ActionResult, String?) -> Void)?` | Action result received (with optional requestId) |
| `onScreen` | `((ScreenPayload, String?) -> Void)?` | Screenshot received (with optional requestId) |
| `onRecordingStarted` | `(() -> Void)?` | Recording has begun |
| `onRecording` | `((RecordingPayload) -> Void)?` | Completed recording received |
| `onRecordingError` | `((String) -> Void)?` | Recording failed |
| `onAuthApproved` | `((String?) -> Void)?` | Auth approved (token provided) |
| `onSessionLocked` | `((SessionLockedPayload) -> Void)?` | Session locked by another driver |
| `onAuthFailed` | `((String) -> Void)?` | Auth rejected |
| `onStatus` | `((String) -> Void)?` | Progress messages for session management |

> **Note:** At the network layer, `DeviceConnection` and `DeviceDiscovery` use a single `onEvent` callback with typed enums (`ConnectionEvent`, `DiscoveryEvent`). TheHandoff translates connection lifecycle into `connectionPhase` plus `onConnectionStateChanged`; request/response payloads still use typed callbacks.

#### Configuration

| Property | Type | Description |
|----------|------|-------------|
| `token` | `String?` | Auth token for connections |
| `driverId` | `String?` | Driver identity for session locking |

#### Injectable Closures (Test Boundary)

```swift
var makeDiscovery: () -> any DeviceDiscovering
var makeConnection: (DiscoveredDevice, String?, String) -> any DeviceConnecting
```

Tests replace these with mock implementations to avoid real Bonjour and NWConnection.

#### Methods

| Method | Description |
|--------|-------------|
| `startDiscovery()` | Begin Bonjour discovery |
| `stopDiscovery()` | Stop discovery |
| `connect(to:)` | Connect to a device (sets connectionPhase to .connecting) |
| `disconnect()` | Disconnect and clear all state |
| `forceDisconnect()` | Force-close a stale connection |
| `send(_:requestId:)` | Send a ClientMessage with optional requestId |
| `connectWithDiscovery(filter:timeout:)` | Discover + resolve + connect in one async call |
| `setupAutoReconnect(filter:)` | Install auto-reconnect on disconnect (60 attempts at 1s) |
| `discoverReachableDevices(timeout:probeTimeout:retryInterval:)` | Discover and probe-validate devices |
| `displayName(for:)` | Disambiguated display name for a device |

#### Connection Phases and Failures

TheHandoff exposes a connection phase for disconnected, connecting, connected,
and failed states. Failure diagnostics are derived from typed disconnect reasons
instead of a hand-maintained public enum list. Current failure families include
transport failure, session lock, auth failure, auth approval pending/timeout,
protocol version mismatch, missing TLS fingerprint for a non-loopback endpoint,
backlog overflow, no discovered device, and no matching target.

Auto-reconnect preserves one concrete target identity and reports a terminal
diagnostic after bounded retries. Direct endpoint sessions (`host:port`) reuse
that endpoint without requiring Bonjour discovery.

#### RecordingPhase

```swift
public enum RecordingPhase: Equatable {
    case idle
    case recording
}
```

### Device Protocols

| Type | Description |
|------|-------------|
| `DeviceConnecting` | Protocol for device connection implementations. Defines `connect()`, `disconnect()`, `send(_:)`, and connection state callbacks. |
| `DeviceDiscovering` | Protocol for device discovery implementations. Defines `start()`, `stop()`, and discovery event callbacks. |
| `ConnectionEvent` | Events emitted by `DeviceConnecting`: `.connected`, `.disconnected(Error?)`, `.data(Data)` |
| `DiscoveryEvent` | Events emitted by `DeviceDiscovering`: `.found(DiscoveredDevice)`, `.lost(DiscoveredDevice)`, `.stateChanged(isReady:)` |

---

## TheFence (Orchestration Layer)

**Import**: `import ButtonHeist`
**Platform**: macOS 14.0+
**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence.swift`

### Overview

TheFence is the shared orchestration layer for all command dispatch. Both the CLI (`buttonheist session`) and the MCP server (`buttonheist-mcp`) are thin wrappers over it.

### TheFence Class

```swift
@ButtonHeistActor
public final class TheFence
```

#### Configuration

```swift
public struct Configuration {
    public var deviceFilter: String?        // Target device by name/ID/UDID
    public var connectionTimeout: TimeInterval // Default: 30
    public var token: String?               // Auth token (falls back to BUTTONHEIST_TOKEN env)
    public var autoReconnect: Bool          // Auto-reconnect on disconnect (default: true)
    public var fileConfig: ButtonHeistFileConfig? // Named targets from config file
}
```

#### Properties

##### supportedCommands
```swift
public static let supportedCommands: [String]  // From Command.allCases
```

##### onStatus
```swift
public var onStatus: (@ButtonHeistActor (String) -> Void)?
```
Called with status messages during connection lifecycle (searching, connecting, reconnecting).

##### onAuthApproved
```swift
public var onAuthApproved: (@ButtonHeistActor (String?) -> Void)?
```
Called when the connection is approved. UI approval returns the token that the client can reuse.

#### Methods

##### start()
```swift
public func start() async throws
```
Discover a device, connect, and set up auto-reconnect. Idempotent if already connected.

##### stop()
```swift
public func stop()
```
Disconnect and stop discovery.

##### execute(request:)
```swift
public func execute(request: [String: Any]) async throws -> FenceResponse
```
Execute a command. The `request` dictionary must contain a `command` key. Auto-connects if not already connected. Returns a typed `FenceResponse`.

### Command

```swift
public enum Command: String, CaseIterable, Sendable {
    case help, status, quit, exit
    case listDevices = "list_devices"
    case getInterface = "get_interface"
    case runBatch = "run_batch"
    case getSessionState = "get_session_state"
    case connect
    case listTargets = "list_targets"
    case getSessionLog = "get_session_log"
    case archiveSession = "archive_session"
    // Full catalog lives in TheFence+CommandCatalog.swift.
}
```

Single source of truth for supported commands in the product command layer. Each case has a `rawValue` matching the command request string accepted by TheFence (e.g., `.oneFingerTap` -> `"one_finger_tap"`). These command names are the CLI/session/batch contract; wire message discriminators are a lower transport layer and may use different names such as `typeText`. `Command.allCases` replaces the former hand-maintained string array.

`connect` establishes the session and returns session state; observation starts with `get_interface`. It verifies transport, handshake/auth, and session ownership, but it does not request, parse, or explore the UI hierarchy.

**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift`

### FenceResponse

```swift
public enum FenceResponse
```

Typed response enum with `humanFormatted() -> String`, `jsonData() -> Data`, and `compactFormatted() -> String` (token-efficient compact text format used by MCP and JSON output modes) serialization. JSON output is encoded from typed public response models.

#### Cases

| Case | Description |
|------|-------------|
| `ok(message:)` | Generic success with message |
| `error(_:)` | Error with message |
| `help(commands:)` | List of supported commands |
| `status(connected:deviceName:)` | Connection status |
| `devices(_:)` | List of discovered devices |
| `interface(_:)` | UI element state |
| `action(result:expectation:)` | Action outcome with delta and optional expectation validation result |
| `screenshot(path:payload:)` | Screenshot saved to path plus screen payload metadata |
| `screenshotData(payload:)` | Opt-in inline screenshot as base64 PNG plus metadata; visible interface data is included only when requested |
| `recording(path:payload:)` | Recording saved to path with metadata summary |
| `recordingExpanded(path:payload:options:)` | Recording saved to path with explicitly requested bounded inline video and/or interaction log |
| `recordingData(payload:)` | In-memory recording payload for callers that explicitly request base64 video |
| `batch(results:completedSteps:failedIndex:totalTimingMs:expectationsChecked:expectationsMet:)` | Batched command results with aggregate timing, optional failure index, and expectation stats |
| `sessionState(payload:)` | Read-only client-side session summary for `get_session_state` |
| `targets(_:defaultTarget:)` | Named targets from config file with optional default |
| `sessionLog(snapshot:)` | Current session log snapshot for `get_session_log` |
| `archiveResult(path:snapshot:)` | Archive path and final session log snapshot for `archive_session` |
| `heistStarted(message:)` | Heist recording started confirmation |
| `heistStopped(path:stepCount:)` | Heist recording stopped with file path and step count |
| `heistPlayback(completedSteps:failedIndex:totalTimingMs:failure:report:)` | Heist playback result with pass/fail, timing, and per-step report |

### FenceError

```swift
public enum FenceError: Error, LocalizedError
```

#### Cases

| Case | Description |
|------|-------------|
| `invalidRequest(_:)` | Invalid JSON or missing command |
| `noDeviceFound` | No devices found within timeout |
| `noMatchingDevice(filter:available:)` | No device matching the filter |
| `connectionTimeout` | Connection timed out |
| `connectionFailed(_:)` | Connection failed |
| `sessionLocked(_:)` | Session held by another driver |
| `authFailed(_:)` | Authentication failed |
| `notConnected` | Not connected to device |
| `actionTimeout` | Action timed out — connection is preserved |
| `actionFailed(_:)` | Action failed with server error message |

### TargetConfig

```swift
public struct TargetConfig: Codable, Sendable, Equatable {
    public let device: String            // host:port string
    public let token: String?            // Optional auth token
    public let certFingerprint: String?  // Optional TLS fingerprint pin
}
```

A named connection target with a device address, optional auth token, and optional TLS certificate fingerprint. Defined in config files (`.buttonheist.json` or `~/.config/buttonheist/config.json`). Non-loopback direct targets must have configured or persisted trust, usually a `certFingerprint` such as `sha256:<hex>`.

### ButtonHeistFileConfig

```swift
public struct ButtonHeistFileConfig: Codable, Sendable, Equatable {
    public let targets: [String: TargetConfig]
    public let defaultTarget: String?  // JSON key: "default"
}
```

Schema for the ButtonHeist config file. Contains named targets and an optional default.

### TargetConfigResolver

```swift
public enum TargetConfigResolver
```

Stateless resolver for connection targets with environment variable override precedence.

#### Methods

| Method | Description |
|--------|-------------|
| `loadConfig(from:)` | Load config from explicit path, or search `.buttonheist.json` then `~/.config/buttonheist/config.json` |
| `resolve(targetName:config:)` | Look up a named target in config |
| `resolveEffective(targetName:config:env:)` | Full precedence resolution: env vars > named target > default target |

### DisconnectReason

```swift
public enum DisconnectReason: Error, LocalizedError
```

Structured reason for why a connection was closed. Passed via `ConnectionEvent.disconnected` on `DeviceConnection`; TheHandoff folds it into connection phase and diagnostic state for session-state consumers.

Public diagnostics are grouped into high-level categories rather than exposed as a stable enum inventory:

| Category | Examples |
|----------|----------|
| Transport | Network errors, buffer overflow, server close, event backlog overflow |
| TLS trust | Certificate fingerprint mismatch or missing TLS fingerprint for a non-loopback target |
| Authentication | Auth failure or on-device approval pending |
| Protocol | Exact `buttonHeistVersion` mismatch during hello negotiation |
| Session | Session locked by another driver |
| Client | Local disconnect |

---

## ButtonHeistMCP (MCP Server)

**Location**: `ButtonHeistMCP/`
**Binary**: `buttonheist-mcp`
**Platform**: macOS 14.0+

### Overview

MCP server projecting its tool schemas from TheFence. `activate` is the primary interaction tool — it uses the activation-first pattern (accessibility activation, then synthetic tap fallback). Pass `action` to `activate` to perform named actions (increment, decrement, or custom actions). Low-level touch gestures are grouped under `gesture` as escape hatches. Build with:

```bash
cd ButtonHeistMCP && swift build -c release
```

### Tool Surface

ButtonHeistMCP projects its tool surface from `TheFence.Command.parameters`
through `ToolDefinitions.swift`; this section documents the contract rather
than duplicating every parameter. The checked-in generated tool reference lives
at [MCP Tool Reference](reference/mcp-tools.md).

The command reference at [Command Reference](reference/commands.md) is the
source for canonical command names, CLI exposure, MCP grouping, batch
eligibility, playback eligibility, and parameter shape. Hand-written docs stay
at the workflow and invariant layer.

`get_session_state` reports the current connection phase and the last known failure/disconnect reason without doing observation work. It does not send `requestInterface` or `explore`.

Additive payload fields:

| Field | Type | Description |
|-------|------|-------------|
| `phase` | `String` | Current handoff phase: `disconnected`, `connecting`, `connected`, or `failed` |
| `lastFailure` | `Object?` | Present when a typed failed/disconnected reason is known. Contains `errorCode`, failure `phase`, `retryable`, and optional `message`/`hint` |

All tools use strict schemas (`additionalProperties: false`) for the call shape — only documented parameters are accepted. Semantic validation happens in TheFence handlers, which report malformed fields as `schema validation failed for <field>: observed <type/value>; expected <type/range/enum>`.

`wait_for_change` is server-owned: with an expectation, TheInsideJob checks the current settled state first, then holds the request open until a later settled scan satisfies the same predicate or the timeout clears it.

For `wait_for_change`, `element_disappeared` is satisfied by current absence. It does not require proving a prior arrival and removal event.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | MCP client idle timeout in seconds (default: 60). Disconnects from device after MCP inactivity; next tool call auto-reconnects. Server-side session release is controlled by `INSIDEJOB_SESSION_TIMEOUT` |

### Response Handling

- Screenshots return metadata plus an artifact path by default. `get_screen` with `inlineData=true` opts into capped MCP image content; `run_batch` rejects inline screenshots so batch responses stay bounded.
- Recording video data is replaced with a size summary to keep responses readable.
- Error responses set `isError: true` on the MCP result.

---

## TheScore Types

**Import**: `import TheScore`
**Platform**: iOS 17.0+ / macOS 14.0+
**Location**: `ButtonHeist/Sources/TheScore/Messages.swift`

### Constants

```swift
public let buttonHeistServiceType = "_buttonheist._tcp"
public let buttonHeistVersion = "<semver>"  // Single product version; bumped only by scripts/release.sh
```

### Connection Lifecycle Types

Connection lifecycle state lives in TheHandoff. Public responses expose
structured diagnostics rather than requiring callers to switch on internal enum
cases. Diagnostics distinguish transport failure, auth failure, auth approval
pending/timeout, session lock, protocol mismatch, missing TLS fingerprint,
backlog overflow, no device, and no matching target.

### RecordingPhase

```swift
public enum RecordingPhase: Equatable
```

#### Cases

- `idle` - No recording in progress
- `recording` - Screen recording is active

### DiscoveredDevice

```swift
public struct DiscoveredDevice: Identifiable, Hashable, Sendable
```

Represents a discovered TheInsideJob device.

#### Properties

- `id: String` - Unique identifier
- `name: String` - Service name (v3 format: "AppName#instanceId")
- `endpoint: NWEndpoint` - Network endpoint for connection
- `simulatorUDID: String?` - Simulator UDID from Bonjour TXT record (nil on physical devices)
- `installationId: String?` - Stable installation identifier from Bonjour TXT record
- `displayDeviceName: String?` - Human-readable device name from Bonjour TXT record
- `instanceId: String?` - Instance identifier from Bonjour TXT record
- `sessionActive: Bool?` - Whether the device currently has an active session
- `certFingerprint: String?` - Advertised TLS certificate SHA-256 fingerprint (format: `sha256:<hex>`). Discovery metadata is not trust by itself; non-loopback trust must be configured, persisted, or approved.

#### Computed Properties

- `shortId: String?` - Short instance ID parsed from service name suffix (after `#`)
- `appName: String` - App name extracted from service name (before `#`)
- `deviceName: String` - Device name extracted from service name (empty for v3 format)

### ClientMessage

```swift
public enum ClientMessage: Codable
```

Messages sent from client to server.

#### Cases

- `clientHello` - Version-negotiation hello sent immediately after `serverHello`
- `authenticate(AuthenticatePayload)` - Authenticate with a token (sent after `clientHello` / `authRequired`)
- `requestInterface` - Request the current on-screen interface
- `ping` - Keepalive
- `activate(ElementTarget)` - Activate element (VoiceOver double-tap)
- `increment(ElementTarget)` - Increment adjustable element
- `decrement(ElementTarget)` - Decrement adjustable element
- `performCustomAction(CustomActionTarget)` - Invoke named custom action
- `touchTap(TouchTapTarget)` - Tap at coordinates or element
- `touchLongPress(LongPressTarget)` - Long press at coordinates or element
- `touchSwipe(SwipeTarget)` - Swipe between two points or in a direction
- `touchDrag(DragTarget)` - Drag from one point to another
- `touchPinch(PinchTarget)` - Pinch/zoom gesture
- `touchRotate(RotateTarget)` - Rotation gesture
- `touchTwoFingerTap(TwoFingerTapTarget)` - Two-finger tap
- `touchDrawPath(DrawPathTarget)` - Draw along a path of waypoints
- `touchDrawBezier(DrawBezierTarget)` - Draw along bezier curves (sampled server-side)
- `typeText(TypeTextTarget)` - Type non-empty text via UIKeyboardImpl.sharedInstance injection
- `editAction(EditActionTarget)` - Perform edit action (copy, paste, cut, select, selectAll, delete)
- `setPasteboard(SetPasteboardTarget)` - Write text to general pasteboard
- `getPasteboard` - Read text from general pasteboard
- `scroll(ScrollTarget)` - Axis-aware page scroll (finds scroll view matching direction's axis)
- `scrollToVisible(ScrollToVisibleTarget)` - One-shot scroll to a known element
- `elementSearch(ElementSearchTarget)` - Iterative scroll search for an unseen element
- `scrollToEdge(ScrollToEdgeTarget)` - Axis-aware edge jump with lazy container iteration
- `resignFirstResponder` - Dismiss keyboard
- `waitForIdle(WaitForIdleTarget)` - Wait for animations to settle (internal)
- `waitForChange(WaitForChangeTarget)` - Wait for UI to change, optionally matching an expectation
- `waitFor(WaitForTarget)` - Wait for an element matching a predicate to appear or disappear
- `requestScreen` - Request PNG screenshot plus visible accessibility data at the wire layer; public responses expose the interface only when explicitly requested
- `startRecording(RecordingConfig)` - Start screen recording (H.264/MP4)
- `stopRecording` - Stop active screen recording
- `status` - Lightweight status probe allowed after the hello handshake and before auth (identity + availability, no session claim)

### ServerMessage

```swift
public enum ServerMessage: Codable
```

Messages sent from server to client.

#### Cases

- `serverHello` - Server hello sent immediately on connection; client must answer with `clientHello`
- `protocolMismatch(ProtocolMismatchPayload)` - Exact protocol version mismatch; server disconnects after sending this
- `authRequired` - Server requires authentication (sent after a successful hello/version handshake)
- `authFailed(String)` - Authentication failed (sent before disconnect)
- `authApproved(AuthApprovedPayload)` - Connection approved via on-device UI (contains token for future use). See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#ui-approval-flow) for details.
- `info(ServerInfo)` - Device/app metadata (sent after successful auth)
- `interface(Interface)` - UI element state
- `pong` - Ping response
- `error(String)` - Error description
- `actionResult(ActionResult)` - Action outcome
- `screen(ScreenPayload)` - Raw wire screenshot payload. Public CLI/MCP formatting returns metadata and artifact paths by default; inline PNG data is explicit and size-bounded.
- `sessionLocked(SessionLockedPayload)` - Session locked by another driver (sent before disconnect). See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#session-locking).
- `recordingStarted` - Recording has begun
- `recordingStopped` - Recording stop acknowledged
- `recording(RecordingPayload)` - Raw wire recording payload. Public CLI/MCP formatting returns metadata and artifact paths by default; inline video/log data is explicit and size-bounded.
- `recordingError(String)` - Recording failed
- `status(StatusPayload)` - Lightweight server identity and session availability snapshot

### StatusPayload

```swift
public struct StatusPayload: Codable, Sendable
```

#### Properties

- `identity: StatusIdentity` - App/device identity for the reachable Inside Job instance
- `session: StatusSession` - Current session availability and connection counts

### StatusIdentity

```swift
public struct StatusIdentity: Codable, Sendable
```

#### Properties

- `appName: String` - App name from the target bundle
- `bundleIdentifier: String` - Target app bundle identifier
- `appBuild: String` - Target app build number
- `deviceName: String` - Device name reported by UIKit
- `systemVersion: String` - iOS version string
- `buttonHeistVersion: String` - Protocol version exposed by Inside Job

### StatusSession

```swift
public struct StatusSession: Codable, Sendable
```

#### Properties

- `active: Bool` - Whether a driver session is active
- `watchersAllowed: Bool` - Always `false`; a session has one active driver connection
- `activeConnections: Int` - Number of connections in the current session

### AuthenticatePayload

```swift
public struct AuthenticatePayload: Codable, Sendable
```

#### Properties

- `token: String` - Auth token for authentication
- `driverId: String?` - Driver identity for session locking. When set, used instead of token for session identity.

### SessionLockedPayload

```swift
public struct SessionLockedPayload: Codable, Sendable
```

#### Properties

- `message: String` - Human-readable description of why the session is locked
- `activeConnections: Int` - Number of active connections in the current session

### ElementTarget

```swift
public enum ElementTarget: Codable, Sendable
```

Two resolution strategies: `heistId` (a handle from the current hierarchy) or flat matcher fields (describe the element by accessibility properties). `heistId` takes priority when both are present. A `heistId` is not a durable identity and is not geometry authority; action execution resolves fresh live geometry immediately before touching.

#### Properties

- `heistId: String?` - Current-hierarchy semantic handle assigned by `get_interface`
- `label` / `identifier` / `value` / `traits` / `excludeTraits` - Predicate matcher fields for accessibility-based resolution
- `ordinal: Int?` - 0-based index to select among multiple matcher results. Without ordinal, multiple matches return an ambiguity error with a hint showing valid ordinal range.

### TouchTapTarget

```swift
public struct TouchTapTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ElementTarget?` - Target element (taps at a freshly resolved live activation point)
- `pointX: Double?` - Explicit X coordinate
- `pointY: Double?` - Explicit Y coordinate
- `point: CGPoint?` - Computed CGPoint from pointX/pointY

### TypeTextTarget

```swift
public struct TypeTextTarget: Codable, Sendable
```

#### Properties

- `text: String` - Non-empty text to type character-by-character
- `elementTarget: ElementTarget?` - Element to tap for focus and value readback

### CustomActionTarget

```swift
public struct CustomActionTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ElementTarget` - Target element
- `actionName: String` - Name of the custom action

### ScrollDirection

```swift
public enum ScrollDirection: String, Codable, Sendable
```

#### Cases

- `up` - Scroll up (reveal content above)
- `down` - Scroll down (reveal content below)
- `left` - Scroll left (reveal content to the left)
- `right` - Scroll right (reveal content to the right)
- `next` - Scroll to next page (vertical)
- `previous` - Scroll to previous page (vertical)

### ScrollTarget

```swift
public struct ScrollTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ElementTarget?` - Element to scroll from (axis-aware: finds scroll view matching direction's axis)
- `direction: ScrollDirection` - Scroll direction

### ScrollEdge

```swift
public enum ScrollEdge: String, Codable, Sendable
```

#### Cases

- `top` - Scroll to top edge
- `bottom` - Scroll to bottom edge
- `left` - Scroll to left edge
- `right` - Scroll to right edge

### ScrollToEdgeTarget

```swift
public struct ScrollToEdgeTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ElementTarget?` - Element whose nearest scroll view ancestor to scroll (axis-aware)
- `edge: ScrollEdge` - Which edge to scroll to

### ElementMatcher

```swift
public struct ElementMatcher: Codable, Sendable, Equatable
```

Composable predicate for matching elements in the accessibility tree. All specified fields use AND semantics. Used by `element_search`, `wait_for`, `get_interface` filtering, and action commands through flat `ElementTarget` matcher fields.

Matching is **exact or miss**: string fields are compared case-insensitively after typography folding (smart quotes/dashes/ellipsis fold to ASCII; emoji, accents, and CJK pass through). Traits compare as exact bitmasks. There is no substring fallback. On a miss the resolver returns `.notFound` with a structured near-miss diagnostic that lists up to three substring suggestions (e.g. "did you mean 'Save Draft', 'Save All', 'Save As'?"). The same semantics are evaluated by `HeistElement.matches` on the client and `AccessibilityElement.matches` on the server so the same matcher input produces the same outcome on both sides.

#### Properties

- `label: String?` - Case-insensitive equality match on accessibility label (typography-folded)
- `identifier: String?` - Case-insensitive equality match on accessibility identifier (typography-folded)
- `value: String?` - Case-insensitive equality match on accessibility value (typography-folded)
- `traits: [String]?` - All listed traits must be present (exact bitmask)
- `excludeTraits: [String]?` - None of the listed traits may be present (exact bitmask)

### ScrollToVisibleTarget

```swift
public struct ScrollToVisibleTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ElementTarget?` - Known element to scroll into view. Use `heistId` for current-hierarchy handles; matcher fields resolve elements already present in the current accessibility state. Use `ElementSearchTarget` for iterative discovery.

### ScrollSearchDirection

```swift
public enum ScrollSearchDirection: String, Codable, Sendable, CaseIterable
```

#### Cases

- `down` - Scroll down (default)
- `up` - Scroll up
- `left` - Scroll left
- `right` - Scroll right

### ScrollSearchResult

```swift
public struct ScrollSearchResult: Codable, Sendable
```

Diagnostic output from `elementSearch`.

#### Properties

- `scrollCount: Int` - Number of scroll steps performed
- `uniqueElementsSeen: Int` - Distinct elements seen across all scroll positions
- `totalItems: Int?` - Total item count from UITableView/UICollectionView data source (nil if not a collection)
- `exhaustive: Bool` - `true` if all items in the collection were visited
- `foundElement: HeistElement?` - The matched element (nil on failure)

### WaitForTarget

```swift
public struct WaitForTarget: Codable, Sendable
```

Target for `wait_for` command — waits for an element matching a heistId or predicate to appear or disappear.

Presence waits use the same target resolution contract as actions: one exact match succeeds, an explicit `ordinal` selects that match, zero matches keep waiting until timeout, and ambiguous matcher results fail with candidate diagnostics. Absence waits succeed on current absence; ambiguous matcher results also fail immediately with candidate diagnostics instead of satisfying absence.

#### Properties

- `elementTarget: ElementTarget` - Element to wait for, encoded as flat `heistId` or matcher fields
- `heistId: String?` - Assigned element id from the current screen
- `label` / `identifier` / `value` / `traits` / `excludeTraits` - Predicate fields for accessibility-based resolution
- `ordinal: Int?` - 0-based index to select among multiple matcher results
- `absent: Bool?` - When `true`, wait for element to NOT exist (default: `false`)
- `timeout: Double?` - Maximum wait time in seconds (default: 10, max: 30)
- `resolvedAbsent: Bool` - Computed: `absent ?? false`
- `resolvedTimeout: Double` - Computed: `min(timeout ?? 10, 30)`

### UnitPoint

```swift
public struct UnitPoint: Codable, Sendable, Equatable
```

A point in unit coordinates (0–1) relative to an element's accessibility frame. `(0, 0)` is top-left, `(1, 1)` is bottom-right, `(0.5, 0.5)` is center. Used by `SwipeTarget` for element-relative, device-independent swiping.

#### Properties

- `x: Double` - Horizontal position (0 = left edge, 1 = right edge)
- `y: Double` - Vertical position (0 = top edge, 1 = bottom edge)

### ServerInfo

```swift
public struct ServerInfo: Codable, Sendable
```

Device and app metadata received after connecting. The product version
is carried by `ResponseEnvelope.buttonHeistVersion` and is not duplicated
here.

#### Properties

- `appName: String` - App display name
- `bundleIdentifier: String` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points
- `instanceId: String?` - Per-launch session UUID
- `instanceIdentifier: String?` - Human-readable instance identifier (from `INSIDEJOB_ID` env var, or shortId fallback)
- `listeningPort: UInt16?` - Port the server is listening on
- `simulatorUDID: String?` - Simulator UDID when running on iOS Simulator (nil on physical devices)
- `vendorIdentifier: String?` - `UIDevice.identifierForVendor` UUID string (stable per app install per device)

### Interface

```swift
public struct Interface: Codable, Sendable
```

Container for UI element interface data.

#### Properties

- `timestamp: Date` — When the hierarchy was captured
- `tree: [AccessibilityHierarchy]` — Canonical full-fidelity parser hierarchy. Button Heist metadata is attached through `annotations`.
- `annotations: InterfaceAnnotations` — Element and container metadata keyed by parser traversal index and tree path.
- `elements: [HeistElement]` — Computed projection of `tree + annotations`. Provided for callers that want a flat list.
- `screenDescription: String` — Deterministic one-line screen summary (e.g. `"Sign In — 1 text field, 1 password field, 3 buttons"`)
- `screenId: String?` — Slugified screen name for machine use (e.g. `"controls_demo"`), derived from the first header element's label

### AccessibilityHierarchy

```swift
public enum AccessibilityHierarchy: Codable, Equatable, Sendable
```

Recursive node in the canonical interface tree, supplied by `AccessibilitySnapshotModel`. It carries parser `AccessibilityElement` / `AccessibilityContainer` values directly; Button Heist handles and stable container IDs live in `InterfaceAnnotations`.

#### Cases

- `element(AccessibilityElement, traversalIndex: Int)` — Leaf parser element
- `container(AccessibilityContainer, children: [AccessibilityHierarchy])` — Container grouping nested nodes

### InterfaceAnnotations

```swift
public struct InterfaceAnnotations: Codable, Equatable, Hashable, Sendable
```

Button Heist metadata for a parser hierarchy capture.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `elements` | `[InterfaceElementAnnotation]` | Element heistId/action metadata keyed by traversal index |
| `containers` | `[InterfaceContainerAnnotation]` | Container stable IDs keyed by tree path |

### HeistElement

```swift
public struct HeistElement: Codable, Equatable, Hashable, Sendable
```

Represents a single UI element captured from the accessibility hierarchy.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `heistId` | `String` | Current-hierarchy handle for immediate targeting. Use minimum matcher fields for durable replay; action geometry is refreshed live before dispatch. |
| `label` | `String?` | Label |
| `value` | `String?` | Current value |
| `identifier` | `String?` | Identifier |
| `hint` | `String?` | Accessibility hint |
| `traits` | `[HeistTrait]` | Trait names (e.g., `"button"`, `"adjustable"`, `"staticText"`) — see [Trait Reference](#trait-reference) |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |
| `activationPointX` | `Double` | Activation point X (where VoiceOver would tap) |
| `activationPointY` | `Double` | Activation point Y |
| `customContent` | `[HeistCustomContent]?` | Custom accessibility content |
| `actions` | `[ElementAction]?` | Non-obvious actions only. Omitted when all actions are implied by traits (`activate` for buttons, `increment`/`decrement` for adjustable). Custom actions always included. |

### Trait Reference

`HeistTrait` is a `String`-backed enum aligned 1:1 with the AccessibilitySnapshot parser's `knownTraits`. Trait names are used in `traits` and `excludeTraits` fields throughout the API.

#### Standard Traits (Public UIAccessibilityTraits)

| Trait Name | UIKit Constant | Description |
|------------|---------------|-------------|
| `button` | `.button` | Interactive button |
| `link` | `.link` | Hyperlink |
| `image` | `.image` | Image content |
| `staticText` | `.staticText` | Non-interactive text |
| `header` | `.header` | Section header |
| `adjustable` | `.adjustable` | Slider / stepper (increment/decrement) |
| `searchField` | `.searchField` | Search input field |
| `selected` | `.selected` | Currently selected |
| `notEnabled` | `.notEnabled` | Disabled / non-interactive |
| `keyboardKey` | `.keyboardKey` | Keyboard key |
| `summaryElement` | `.summaryElement` | Summary of the app state |
| `updatesFrequently` | `.updatesFrequently` | Value changes frequently |
| `playsSound` | `.playsSound` | Plays audio on activation |
| `startsMediaSession` | `.startsMediaSession` | Starts media playback |
| `allowsDirectInteraction` | `.allowsDirectInteraction` | VoiceOver passes touches through |
| `causesPageTurn` | `.causesPageTurn` | Triggers page turn |
| `tabBar` | `.tabBar` | Tab bar container |

#### Private Traits — Core (Used for Element Classification)

These come from AXRuntime private SPI, surfaced by the AccessibilitySnapshot parser. They are the canonical names used throughout Button Heist.

| Trait Name | Bit | Notes |
|------------|-----|-------|
| `textEntry` | 47 | Text input field (UITextField, UITextView) |
| `isEditing` | 50 | Field is currently being edited |
| `backButton` | 48 | Navigation back button |
| `tabBarItem` | 49 | Individual tab bar item |
| `textArea` | — | Multi-line text area |
| `switchButton` | 53 | Toggle switch (UISwitch). iOS 17 added the public `UIAccessibilityTraitToggleButton` mapping to the same bit — Button Heist uses `switchButton` as the canonical name. |

#### Private Traits — Extended (AXRuntime Diagnostics)

These are from the full AXRuntime trait space. They are retained as canonical trait names for diagnostics and advanced filtering.

| Trait Name | Trait Name | Trait Name |
|------------|------------|------------|
| `webContent` | `pickerElement` | `radioButton` |
| `launchIcon` | `statusBarElement` | `secureTextField` |
| `inactive` | `footer` | `autoCorrectCandidate` |
| `deleteKey` | `selectionDismissesItem` | `visited` |
| `spacer` | `tableIndex` | `map` |
| `textOperationsAvailable` | `draggable` | `popupButton` |
| `menuItem` | `alert` | |

### ActionResult

```swift
public struct ActionResult: Codable, Sendable
```

#### Properties

- `success: Bool` - Whether action succeeded
- `method: ActionMethod` - How action was performed
- `message: String?` - Additional context or error description. Action capability failures use a
  boundary/observation/recovery shape, e.g. `custom action failed: observed ...; try ...`.
- `value: String?` - Current text field value (populated by `typeText`)
- `accessibilityDelta: AccessibilityTrace.Delta?` - Compact delta describing what changed after the action
- `animating: Bool?` - `true` if UI was still animating when result was produced; `nil` means idle
- `screenName: String?` - Label of the first header element in the post-action snapshot
- `screenId: String?` - Slugified screen name for machine use (e.g. `"controls_demo"`)
- `scrollSearchResult: ScrollSearchResult?` - Diagnostics from `elementSearch` (scroll count, unique elements seen, total items, exhaustive flag, matched element)
- `exploreResult: ExploreResult?` - Diagnostics from `explore` (elements discovered, scroll count, containers explored)

### ActionMethod

```swift
public enum ActionMethod: String, Codable, Sendable
```

#### Cases

- `activate` - Used activation
- `increment` - Used increment action
- `decrement` - Used decrement action
- `syntheticTap` - Tap via TheSafecracker
- `syntheticLongPress` - Long press via TheSafecracker
- `syntheticSwipe` - Swipe via TheSafecracker
- `syntheticDrag` - Drag via TheSafecracker
- `syntheticPinch` - Pinch via TheSafecracker
- `syntheticRotate` - Rotation via TheSafecracker
- `syntheticTwoFingerTap` - Two-finger tap via TheSafecracker
- `syntheticDrawPath` - Path drawing via TheSafecracker
- `typeText` - Text injected via UIKeyboardImpl
- `customAction` - Used custom action
- `editAction` - Edit action via responder chain
- `setPasteboard` - Text written to general pasteboard
- `getPasteboard` - Text read from general pasteboard
- `resignFirstResponder` - Keyboard dismissed
- `waitForIdle` - Wait-for-idle completed (internal)
- `waitForChange` - Wait-for-change completed
- `waitFor` - Wait-for element completed
- `scroll` - Scroll view scrolled by one page
- `scrollToVisible` - Known element was scrolled into view
- `elementSearch` - Iterative scroll search found (or failed to find) element matching predicate
- `scrollToEdge` - Scroll view scrolled to an edge
- `explore` - Accessibility-state discovery completed
- `elementNotFound` - Element could not be found
- `elementDeallocated` - Element's view was deallocated

### ActionExpectation

```swift
public enum ActionExpectation: Codable, Sendable, Equatable
```

Outcome signal classifiers for actions. Attached to a request (not to a target type) so any action can opt in. Every action implicitly checks delivery (`success == true`); these tiers classify what kind of change the caller expected. Results report what actually happened — the caller decides what to do with it. In batches, a mismet expectation halts execution at the action that broke rather than letting later steps fail in a confusing state.

Expectations follow a **"say what you know"** design: agents express what they care about and omit what they don't. Optional fields act as filters — provide more to tighten the check, fewer to loosen it. The framework scans the result for any match. This minimizes cognitive load on the caller.

#### Cases

- `screenChanged` - Expected the result's `accessibilityDelta` to be a `.screenChanged` case (view controller identity changed).
- `elementsChanged` - Expected the result's `accessibilityDelta` to be `.elementsChanged` (also met by `.screenChanged` under the superset rule).
- `elementUpdated(heistId: String?, property: ElementProperty?, oldValue: String?, newValue: String?)` - Expected a property change on an element. All fields optional — provide what you know, omit what you don't. Met when any entry in the delta's `updated` list matches all provided fields.
- `elementAppeared(ElementMatcher)` - Expected an element matching this predicate to appear in the delta's `added` list.
- `elementDisappeared(ElementMatcher)` - Expected an element matching this predicate to disappear from the delta's `removed` list. Validation requires a pre-action element cache to resolve removed heistIds to matchers.
- `compound([ActionExpectation])` - All sub-expectations must be met.

#### Static Methods

- `validateDelivery(_: ActionResult) -> ExpectationResult` - Baseline delivery check (always run implicitly). Returns result with `expectation: nil`.

#### Methods

- `validate(against: ActionResult) -> ExpectationResult` - Check this expectation against an action result.

### ExpectationResult

```swift
public struct ExpectationResult: Codable, Sendable, Equatable
```

The outcome of checking an `ActionExpectation` against an `ActionResult`.

#### Properties

- `met: Bool` - Whether the expected outcome was observed
- `expectation: ActionExpectation?` - The expectation that was checked. `nil` for implicit delivery check.
- `actual: String?` - What was actually observed (for diagnostics when `met` is false)

### ScreenPayload

```swift
public struct ScreenPayload: Codable, Sendable
```

Raw wire screen capture payload. Public CLI/MCP responses write the image as an artifact and return metadata by default; inline PNG data and visible-interface expansion are explicit opt-ins and size-bounded.

#### Properties

- `pngData: String` - Base64-encoded PNG data at the wire boundary
- `width: Double` - Screen width in points
- `height: Double` - Screen height in points
- `timestamp: Date` - When screenshot was captured
- `interface: Interface` - Fresh visible accessibility capture at the wire layer. Public outputs include it only when `includeInterface=true`.

### RecordingConfig

```swift
public struct RecordingConfig: Codable, Sendable
```

Recording configuration sent with `startRecording`.

#### Properties

- `fps: Int?` - Frames per second (default: 8, range: 1-15)
- `scale: Double?` - Resolution scale factor (default: 1.0, range: 0.25-1.0)
- `maxDuration: Double?` - Maximum recording duration in seconds (default: 60.0)
- `inactivityTimeout: Double?` - Optional early-stop seconds of inactivity; omitted disables inactivity auto-stop

### RecordingPayload

```swift
public struct RecordingPayload: Codable, Sendable
```

Raw wire completed recording payload. Public CLI/MCP responses write the video as an artifact and return metadata by default; inline video data and full interaction logs are opt-in and size-bounded.

#### Properties

- `videoData: String` - Base64-encoded H.264/MP4 video data at the wire boundary
- `width: Int` - Video width in pixels
- `height: Int` - Video height in pixels
- `duration: Double` - Recording duration in seconds
- `frameCount: Int` - Total frames captured
- `fps: Int` - Frames per second used during recording
- `startTime: Date` - When recording started
- `endTime: Date` - When recording ended
- `stopReason: StopReason` - Why recording stopped (`.manual`, `.inactivity`, `.maxDuration`, `.fileSizeLimit`)
- `interactionLog: [InteractionEvent]?` - Ordered log of interactions recorded during the session (nil if no interactions occurred)

### InteractionEvent

```swift
public struct InteractionEvent: Codable, Sendable
```

A single recorded interaction event captured during a Stakeout recording.

#### Properties

- `timestamp: Double` - Time offset from recording start in seconds
- `command: ClientMessage` - The command that triggered this interaction
- `result: ActionResult` - The result returned to the client
- `accessibilityDelta: AccessibilityTrace.Delta?` - Compact delta describing what changed in the hierarchy (from result.accessibilityDelta)

### Playback Types

| Type | Description |
|------|-------------|
| `HeistPlayback` | Recorded heist script for deterministic replay |
| `HeistEvidence` | Single step of evidence from a heist execution |
| `HeistValue` | Dynamically-typed JSON value (bool, int, double, string, array, object) |
| `RecordedMetadata` | Metadata from the original recording session |
| `RecordedFrame` | Single recorded command with its expected outcome |

---

## CLI Reference

**Location**: `ButtonHeistCLI/`

Top-level CLI command identity, grouped exposure, defaults, and parameter
shape are projected from `TheFence.Command.descriptors`. The generated
command reference is checked against that executable contract:

- [Command Reference](reference/commands.md)
- [MCP Tool Reference](reference/mcp-tools.md)

All direct commands that connect to a device accept `--device <filter>`. The
filter matches discovered metadata such as service name, app name, device name,
short ID prefix, installation ID prefix, instance ID prefix, simulator UDID
prefix, or vendor ID. Run `buttonheist --help` and
`buttonheist <command> --help` for adapter-rendered usage text.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter (overridden by `--device`) |
| `BUTTONHEIST_TOKEN` | Auth token for TheInsideJob |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking (distinguishes drivers sharing the same token) |
| `BUTTONHEIST_SESSION_TIMEOUT` | Default idle timeout in seconds for `buttonheist session` (overridden by `--session-timeout`) |

Flags always take precedence over environment variables.

## Usage Examples

### Minimal iOS Integration

Just import the framework - it auto-starts:

```swift
import SwiftUI
import TheInsideJob

@main
struct MyApp: App {
    // TheInsideJob auto-starts via ObjC +load

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Info.plist for Bonjour/LAN discovery:**
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>element inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

These keys are only needed when you include `network` in `INSIDEJOB_SCOPE` /
`InsideJobScope`. The default `simulator,usb` scope does not publish Bonjour.

### Callback-Based Usage

```swift
import ButtonHeist
import TheScore

@ButtonHeistActor
class Inspector {
    let handoff = TheHandoff()

    init() {
        handoff.onDeviceFound = { [weak self] device in
            print("Found: \(device.name)")
            self?.handoff.connect(to: device)
        }

        handoff.onInterface = { iface, _ in
            print("Received \(iface.elements.count) elements")
            for element in iface.elements {
                print("  \(element.heistId): \(element.description)")
            }
        }

        handoff.onActionResult = { result, _ in
            print("Action: \(result.success ? "success" : "failed") via \(result.method)")
        }

        handoff.onScreen = { screenshot, _ in
            print("Screenshot: \(screenshot.width)x\(screenshot.height)")
        }

        handoff.onConnectionStateChanged = { [weak self] state in
            if case .disconnected = state,
               let failure = self?.handoff.connectionDiagnosticFailure {
                print("Disconnected: \(failure.localizedDescription)")
            }
        }
    }

    func start() {
        handoff.startDiscovery()
    }
}
```

### Async/Await Action with Result

```swift
// Activate an element and wait for the result
let target = ElementTarget.matcher(ElementMatcher(identifier: "loginButton"))
client.send(.activate(target))

do {
    let result = try await client.waitForActionResult(timeout: 10)
    print("Result: \(result.success), method: \(result.method)")
} catch {
    print("Timeout waiting for action result")
}
```

### CLI Scripting

```bash
# List all discovered devices
buttonheist list_devices
buttonheist list_devices --format json

# Target a specific device (by short ID, UDID, or name)
buttonheist --device a1b2 activate --identifier myButton
buttonheist --device DEADBEEF-1234 get_screen --output screen.png

# Get hierarchy as JSON via session
echo '{"command":"get_interface"}' | buttonheist session --format json

# Activate a button (primary interaction command)
buttonheist activate --identifier loginButton
buttonheist activate -l "Submit" --traits button

# Named actions (increment, decrement, custom)
buttonheist activate --identifier volumeSlider --action increment
buttonheist activate --identifier volumeSlider --action decrement
buttonheist activate --identifier myCell --action "Delete"

# Edit actions
buttonheist edit_action copy
buttonheist edit_action paste
buttonheist edit_action delete
buttonheist dismiss_keyboard

# Capture screenshot
buttonheist get_screen --output screen.png

# Touch gestures (low-level escape hatches)
buttonheist one_finger_tap --x 100 --y 200
buttonheist one_finger_tap --identifier loginButton
buttonheist long_press --identifier myButton --duration 1.0
buttonheist swipe --identifier list --direction up
buttonheist drag --from-x 100 --from-y 200 --to-x 300 --to-y 200
buttonheist pinch --identifier mapView --scale 2.0
buttonheist rotate --center-x 200 --center-y 300 --angle 1.57
buttonheist two_finger_tap --identifier zoomControl

# Text entry
buttonheist type_text "Hello World" --identifier nameField
buttonheist activate --identifier nameField
buttonheist edit_action selectAll
buttonheist edit_action delete
buttonheist type_text "World!" --identifier nameField

# Scroll commands
buttonheist scroll --identifier "buttonheist.longList.item-5" --direction up
buttonheist scroll -l "Messages" --ordinal 1 --direction down
buttonheist element_search --label "Color Picker"
buttonheist element_search --label "Settings" --traits header
buttonheist scroll_to_visible "buttonheist.longList.last"
buttonheist scroll_to_edge --identifier "buttonheist.longList.item-0" --edge bottom
```

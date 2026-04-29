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
2. Creates a TCP server on an OS-assigned port
3. Begins Bonjour advertisement as `_buttonheist._tcp`
4. Starts polling for UI element snapshot changes

### Configuration

**Environment variables (highest priority):**
```bash
INSIDEJOB_POLLING_INTERVAL=2.0       # Settle-driven polling timeout in seconds (min: 0.5)
INSIDEJOB_DISABLE=true               # Disable auto-start
INSIDEJOB_DISABLE_FINGERPRINTS=true  # Suppress visual tap/gesture indicators
INSIDEJOB_TOKEN=my-secret-token      # Auth token (fresh UUID auto-generated each launch if not set)
INSIDEJOB_ID=my-instance             # Human-readable instance identifier
INSIDEJOB_SESSION_TIMEOUT=30         # Session release timeout in seconds (default: 30, min: 1)
INSIDEJOB_RESTRICT_WATCHERS=0        # Allow unauthenticated watch (observer) connections (default: restricted, watchers require token)
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
- `allowedScopes`: Set of connection scopes the server will accept. If nil, all scopes are allowed.
- `port`: Preferred TCP port for the server. Pass 0 (the default) for an OS-assigned ephemeral port. The Info.plist (`InsideJobPort`) and environment variable (`INSIDEJOB_PORT`) fallback is handled by the auto-start mechanism in `AutoStart.swift`, not by `configure()` itself.

**Note**: Normally not needed - use Info.plist or environment variable configuration instead.

##### start()

```swift
public func start() throws
```

Start the TCP server and begin Bonjour advertisement.

**Note**: Called automatically on framework load. Manual calls are rarely needed.

**Throws**: Network errors if the listener fails to start.

##### stop()

```swift
public func stop()
```

Stop the server, disconnect all clients, and stop Bonjour advertisement.

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

Manually trigger a debounced hierarchy broadcast to connected clients. Uses a 300ms debounce to prevent update spam.

### Interaction Philosophy: Activation-First

TheInsideJob follows an **activation-first** strategy for all element interactions:

1. **Try `accessibilityActivate()` first** -- TheBrains calls the element's native accessibility activation method via the live object reference held by TheStash's registry. This is the most reliable path because it mirrors how VoiceOver activates controls and respects custom activation behavior.

2. **Fall back to synthetic tap** -- If activation returns `false` or the element does not support it, TheSafecracker injects a synthetic tap at the element's activation point. This is a low-level escape hatch that cannot confirm the gesture was actually handled by the target view.

The same pattern applies to `increment`/`decrement` (native accessibility API first). The `one_finger_tap` command is a pure synthetic tap with no activation-first logic — it is a low-level escape hatch for when coordinate-precise touch injection is needed.

**Why activation-first matters:**
- Native activation respects custom `accessibilityActivate()` overrides
- It works correctly with complex controls (e.g., custom toggle implementations)
- Synthetic taps can miss if the coordinate is occluded by an overlay or the view hierarchy has changed

When a synthetic tap fallback occurs, a debug log is emitted so the behavior is observable.

### Touch Gesture & Text Input System (TheSafecracker)

TheInsideJob uses `TheSafecracker` internally for handling all touch gesture and text input commands. TheSafecracker is an **internal** type -- only TheInsideJob creates and holds the instance. It supports single-finger gestures, multi-touch gestures via synthetic UITouch/IOHIDEvent injection, and text entry via UIKeyboardImpl. TheSafecracker never holds live UIView pointers; it receives only screen coordinates and action outcomes from TheBrains (which resolves targets via TheStash's registry).

**Supported gestures:**
- `one_finger_tap` - Single tap at a point (low-level escape hatch; prefer `activate` for element interactions)
- `longPress` - Long press with configurable duration
- `swipe` - Quick swipe between two points
- `drag` - Slow drag between two points (for sliders, reordering)
- `pinch` - Two-finger pinch/zoom
- `rotate` - Two-finger rotation
- `twoFingerTap` - Simultaneous two-finger tap
- `drawPath` - Trace through a sequence of waypoints (polyline)

**Text input (via UIKeyboardImpl):**
- `typeText` - Inject text character-by-character via `addInputString:`
- `deleteText` - Delete characters via `deleteFromInput`
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
| `currentInterface` | `Interface?` | Most recent UI hierarchy from push broadcasts |
| `currentScreen` | `ScreenPayload?` | Most recent unsolicited screenshot payload, retained for protocol compatibility. Normal screenshots are explicit `requestScreen` responses. |
| `isConnected` | `Bool` | Whether transport is connected |
| `isDiscovering` | `Bool` | Whether Bonjour discovery is active |
| `isRecording` | `Bool` | Whether screen recording is in progress |

#### Callback Properties

| Callback | Type | Description |
|----------|------|-------------|
| `onDeviceFound` | `((DiscoveredDevice) -> Void)?` | New device discovered |
| `onDeviceLost` | `((DiscoveredDevice) -> Void)?` | Device no longer available |
| `onConnected` | `((ServerInfo) -> Void)?` | Connection established |
| `onDisconnected` | `((DisconnectReason) -> Void)?` | Connection closed |
| `onInterface` | `((Interface, String?) -> Void)?` | Hierarchy received (with optional requestId) |
| `onActionResult` | `((ActionResult, String?) -> Void)?` | Action result received (with optional requestId) |
| `onScreen` | `((ScreenPayload, String?) -> Void)?` | Screenshot received (with optional requestId) |
| `onRecordingStarted` | `(() -> Void)?` | Recording has begun |
| `onRecording` | `((RecordingPayload) -> Void)?` | Completed recording received |
| `onRecordingError` | `((String) -> Void)?` | Recording failed |
| `onError` | `((String) -> Void)?` | General error |
| `onAuthApproved` | `((String?) -> Void)?` | Auth approved (token provided) |
| `onSessionLocked` | `((SessionLockedPayload) -> Void)?` | Session locked by another driver |
| `onAuthFailed` | `((String) -> Void)?` | Auth rejected |
| `onInteraction` | `((InteractionEvent) -> Void)?` | Interaction broadcast from observer mode |
| `onStatus` | `((String) -> Void)?` | Progress messages for session management |

> **Note:** At the network layer, `DeviceConnection` and `DeviceDiscovery` use a single `onEvent` callback with typed enums (`ConnectionEvent`, `DiscoveryEvent`). TheHandoff translates these into the named callbacks above.

#### Configuration

| Property | Type | Description |
|----------|------|-------------|
| `token` | `String?` | Auth token for connections |
| `driverId` | `String?` | Driver identity for session locking |
| `autoSubscribe` | `Bool` | Auto-send subscribe/requestInterface on connect (default: true) |
| `observeMode` | `Bool` | Send `watch` instead of `authenticate` (default: false) |

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

#### ConnectionPhase

```swift
public enum ConnectionPhase: Equatable {
    case disconnected
    case connecting(device: DiscoveredDevice)
    case connected(device: DiscoveredDevice)
    case failed(ConnectionFailure)
}
```

#### ConnectionFailure

```swift
public enum ConnectionFailure: Equatable {
    case error(String)
    case authFailed(String)
    case sessionLocked(String)
}
```

#### ReconnectPolicy

```swift
public enum ReconnectPolicy: Equatable {
    case disabled
    case enabled(filter: String?)
}
```

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
public var onStatus: ((String) -> Void)?
```
Called with status messages during connection lifecycle (searching, connecting, reconnecting).

##### onAuthApproved
```swift
public var onAuthApproved: ((String?) -> Void)?
```
Called when the connection is approved. Token is `nil` for observer connections.

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
    // ... 38 total cases
}
```

Single source of truth for the 38 supported commands. Each case has a `rawValue` matching the wire-format string (e.g., `.oneFingerTap` → `"one_finger_tap"`). `Command.allCases` replaces the former hand-maintained string array.

**Location**: `ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift`

### FenceResponse

```swift
public enum FenceResponse
```

Typed response enum with `humanFormatted() -> String`, `jsonDict() -> [String: Any]?`, and `compactFormatted() -> String` (token-efficient compact text format used by MCP and JSON output modes) serialization.

#### Cases

| Case | Description |
|------|-------------|
| `ok(message:)` | Generic success with message |
| `error(_:)` | Error with message |
| `help(commands:)` | List of supported commands |
| `status(connected:deviceName:)` | Connection status |
| `devices(_:)` | List of discovered devices |
| `interface(_:)` | UI element snapshot |
| `action(result:expectation:)` | Action outcome with delta and optional expectation validation result |
| `screenshot(path:width:height:)` | Screenshot saved to path |
| `screenshotData(pngData:width:height:)` | Screenshot as base64 PNG |
| `recording(path:payload:)` | Recording saved to path |
| `recordingData(payload:)` | Recording as base64 video |
| `batch(results:completedSteps:failedIndex:totalTimingMs:expectationsChecked:expectationsMet:)` | Batched command results with aggregate timing, optional failure index, and expectation stats |
| `sessionState(payload:)` | Read-only client-side session summary for `get_session_state` |
| `targets(_:defaultTarget:)` | Named targets from config file with optional default |
| `sessionLog(manifest:)` | Current session manifest for `get_session_log` |
| `archiveResult(path:manifest:)` | Archive path and final manifest for `archive_session` |
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
| `actionTimeout` | Action timed out, connection lost |
| `actionFailed(_:)` | Action failed with server error message |

### TargetConfig

```swift
public struct TargetConfig: Codable, Sendable, Equatable {
    public let device: String   // host:port string
    public let token: String?   // Optional auth token
}
```

A named connection target with a device address and optional auth token. Defined in config files (`.buttonheist.json` or `~/.config/buttonheist/config.json`).

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

Structured reason for why a connection was closed. Passed via `ConnectionEvent.disconnected` on `DeviceConnection` and to `onDisconnected` callbacks on `TheHandoff`.

#### Cases

| Case | Description |
|------|-------------|
| `networkError(_:)` | Underlying network error (wraps the original `Error`) |
| `bufferOverflow` | Server exceeded max buffer size |
| `serverClosed` | Connection closed by server |
| `authFailed(_:)` | Authentication failed with reason |
| `sessionLocked(_:)` | Session locked by another driver |
| `localDisconnect` | Disconnected by client |
| `certificateMismatch` | TLS certificate fingerprint did not match expected value from Bonjour TXT |

---

## ButtonHeistMCP (MCP Server)

**Location**: `ButtonHeistMCP/`
**Binary**: `buttonheist-mcp`
**Platform**: macOS 14.0+

### Overview

MCP server exposing 23 purpose-built tools backed by TheFence. `activate` is the primary interaction tool — it uses the activation-first pattern (accessibility activation, then synthetic tap fallback). Pass `action` to `activate` to perform named actions (increment, decrement, or custom actions). Low-level touch gestures are grouped under `gesture` as escape hatches. Build with:

```bash
cd ButtonHeistMCP && swift build -c release
```

### Tools

| Tool | Description | Key Parameters |
|------|-------------|----------------|
| `get_interface` | Get UI element hierarchy. Pass `full: true` to include off-screen elements in scroll views. | `full`, `label`, `identifier`, `value`, `traits`, `excludeTraits` (optional filtering) |
| `activate` | **Primary interaction tool.** Activate a UI element (activation-first pattern). Pass `action` for named actions (increment, decrement, custom) | `heistId`, `label`, `identifier`, `value`, `traits`, `excludeTraits`, `action`, `expect` |
| `type_text` | Type text / delete characters | `text`, `deleteCount`, `clearFirst`, `heistId`, `label`, `identifier`, `value`, `traits`, `excludeTraits`, `expect` |
| `get_screen` | Capture PNG screenshot | `output` (file path, optional) |
| `wait_for_change` | Wait for UI to change, optionally matching an expectation | `expect`, `timeout` |
| `wait_for` | Wait for element to appear/disappear | `label`, `identifier`, `value`, `traits`, `excludeTraits`, `absent`, `timeout` |
| `start_recording` | Start H.264/MP4 screen recording | `fps`, `scale`, `maxDuration`, `inactivityTimeout` |
| `stop_recording` | Stop recording (returns metadata) | `output` (file path, optional) |
| `list_devices` | List discovered iOS devices | — |
| `gesture` | Touch gestures (prefer `activate`). Includes swipe. | `type` (required): `swipe`, `one_finger_tap`, `drag`, `long_press`, `pinch`, `rotate`, `two_finger_tap`, `draw_path`, `draw_bezier`; `expect` |
| `edit_action` | Perform edit or keyboard actions on first responder | `action` (required): `copy`, `paste`, `cut`, `select`, `selectAll`, `dismiss`; `expect` |
| `scroll` | Scroll within scroll views. Mode selects behavior. | `mode`: `page` (default), `to_visible`, `search`, `to_edge`; `direction`, `edge`, element target, `expect` |
| `set_pasteboard` | Write text to the general pasteboard | `text` (required), `expect` |
| `get_pasteboard` | Read text from the general pasteboard | `expect` |
| `run_batch` | Execute an ordered batch of Fence requests in one MCP call | `steps` (required), `policy` |
| `get_session_state` | Read-only summary of the current macOS-side session state | — |

All tools use strict schemas (`additionalProperties: false`) — only documented parameters are accepted.

#### activate

The primary way to interact with buttons, links, and controls. Uses the activation-first pattern: tries `accessibilityActivate()` (like VoiceOver double-tap) first, falls back to synthetic tap at the element's activation point. Provide `identifier` or `order` from `get_interface`.

Pass `action` to perform a named action instead of default activation:
- `"increment"` / `"decrement"` — For sliders, steppers
- Any custom action name from the element's `actions` array
- Prefix with `"action:"` to force custom action dispatch (e.g., `"action:increment"` dispatches as a custom action named "increment")

#### gesture

Touch gesture tool. For element interactions, prefer `activate` instead. The `type` field selects the gesture:

- `swipe` — Swipe on element or between coordinates. `direction` for cardinal swipes, or `start`/`end` unit points (0-1 relative to element frame) for precise control. Also accepts `startX`/`startY`/`endX`/`endY` for absolute screen coordinates. Optional `duration`.
- `one_finger_tap` — Synthetic tap at x/y coordinates
- `drag` — Requires `endX`, `endY`
- `long_press` — Optional `duration` (seconds, default 1.0)
- `pinch` — Requires `scale` (>1 zoom in, <1 zoom out)
- `rotate` — Requires `angle` (radians)
- `two_finger_tap` — Two-finger tap
- `draw_path` — Requires `points` array of `{x, y}` objects
- `draw_bezier` — Requires `curves` array of bezier curve objects

#### edit_action

Perform an edit or keyboard action on the current first responder. Requires `action`: `copy`, `paste`, `cut`, `select`, `selectAll`, or `dismiss` (dismisses the software keyboard by resigning first responder).

#### run_batch

Execute an ordered sequence of commands in a single call. Each step is a full command request (same schema as a standalone tool call). Steps run sequentially — the response from one step is not piped into the next.

**Parameters:**

- `steps` (required) — Array of command request objects (e.g., `[{"command": "activate", "identifier": "loginButton", "expect": "screen_changed"}, ...]`)
- `policy` — `"stop_on_error"` (default) or `"continue_on_error"`

With the default `stop_on_error` policy, the batch halts at the first mismet expectation or delivery failure. `failedIndex` points at the step that broke — not a downstream step that failed because the expected state change never happened.

**Response fields:**

- `results` — Array of per-step responses (only includes steps that ran)
- `completedSteps` — Number of steps executed
- `failedIndex` — Index of the first failed step (`null` if all passed)
- `totalTimingMs` — Wall-clock duration of the entire batch
- `expectations.checked` — Count of steps with explicit `expect` fields
- `expectations.met` — Count of those that were satisfied
- `expectations.allMet` — Boolean summary

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter |
| `BUTTONHEIST_TOKEN` | Auth token |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking |
| `BUTTONHEIST_SESSION_TIMEOUT` | Idle timeout in seconds (default: 60). Disconnects from device after inactivity; next tool call auto-reconnects |

### Response Handling

- Screenshots are returned as inline MCP image content items alongside the JSON payload.
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
public let protocolVersion = "6.8"  // Protocol v6.8: current wire protocol version
```

### ConnectionPhase

```swift
public enum ConnectionPhase: Equatable
```

#### Cases

- `disconnected` - No active connection
- `connecting(device: DiscoveredDevice)` - Connection in progress to device
- `connected(device: DiscoveredDevice)` - Connected to a device
- `failed(ConnectionFailure)` - Connection failed with typed failure

### ConnectionFailure

```swift
public enum ConnectionFailure: Equatable
```

#### Cases

- `error(String)` - General connection error
- `authFailed(String)` - Authentication rejected
- `sessionLocked(String)` - Session locked by another driver

### ReconnectPolicy

```swift
public enum ReconnectPolicy: Equatable
```

#### Cases

- `disabled` - Auto-reconnect will not fire
- `enabled(filter: String?)` - Auto-reconnect fires on disconnect with optional device filter

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
- `certFingerprint: String?` - TLS certificate SHA-256 fingerprint from Bonjour TXT record (format: `sha256:<hex>`)

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
- `requestInterface` - Request current hierarchy
- `subscribe` - Subscribe to automatic updates
- `unsubscribe` - Unsubscribe from updates
- `ping` - Keepalive
- `activate(ActionTarget)` - Activate element (VoiceOver double-tap)
- `increment(ActionTarget)` - Increment adjustable element
- `decrement(ActionTarget)` - Decrement adjustable element
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
- `typeText(TypeTextTarget)` - Type text via UIKeyboardImpl.sharedInstance injection
- `editAction(EditActionTarget)` - Perform edit action (copy, paste, cut, select, selectAll)
- `setPasteboard(SetPasteboardTarget)` - Write text to general pasteboard
- `getPasteboard` - Read text from general pasteboard
- `scroll(ScrollTarget)` - Axis-aware page scroll (finds scroll view matching direction's axis)
- `scrollToVisible(ScrollToVisibleTarget)` - Hierarchy-driven scroll search with swipe fallback for nested layouts
- `scrollToEdge(ScrollToEdgeTarget)` - Axis-aware edge jump with lazy container iteration
- `resignFirstResponder` - Dismiss keyboard
- `waitForIdle(WaitForIdleTarget)` - Wait for animations to settle (internal)
- `waitForChange(WaitForChangeTarget)` - Wait for UI to change, optionally matching an expectation
- `waitFor(WaitForTarget)` - Wait for an element matching a predicate to appear or disappear
- `requestScreen` - Request PNG screenshot
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
- `interface(Interface)` - UI element snapshot
- `pong` - Ping response
- `error(String)` - Error description
- `actionResult(ActionResult)` - Action outcome
- `screen(ScreenPayload)` - Base64-encoded PNG
- `sessionLocked(SessionLockedPayload)` - Session locked by another driver (sent before disconnect). See [WIRE-PROTOCOL.md](WIRE-PROTOCOL.md#session-locking).
- `recordingStarted` - Recording has begun
- `recordingStopped` - Recording stop acknowledged
- `recording(RecordingPayload)` - Completed recording (H.264/MP4 as base64)
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
- `watchersAllowed: Bool` - Whether observer connections are allowed for the active session
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

### ActionTarget

```swift
public struct ActionTarget: Codable, Sendable
```

Two resolution strategies: `heistId` (assigned token from `get_interface`) or `match` (describe the element by accessibility properties). `heistId` takes priority when both are present.

#### Properties

- `heistId: String?` - Stable element identifier assigned by `get_interface`
- `match: ElementMatcher?` - Predicate matcher for accessibility-based resolution
- `ordinal: Int?` - 0-based index to select among multiple matches. Requires `match`. Without ordinal, multiple matches return an ambiguity error with a hint showing valid ordinal range.

### TouchTapTarget

```swift
public struct TouchTapTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget?` - Target element (taps at activation point)
- `pointX: Double?` - Explicit X coordinate
- `pointY: Double?` - Explicit Y coordinate
- `point: CGPoint?` - Computed CGPoint from pointX/pointY

### TypeTextTarget

```swift
public struct TypeTextTarget: Codable, Sendable
```

#### Properties

- `text: String?` - Text to type character-by-character (nil if only deleting)
- `deleteCount: Int?` - Number of delete key taps before typing
- `elementTarget: ActionTarget?` - Element to tap for focus and value readback

### CustomActionTarget

```swift
public struct CustomActionTarget: Codable, Sendable
```

#### Properties

- `elementTarget: ActionTarget` - Target element
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

- `elementTarget: ActionTarget?` - Element to scroll from (axis-aware: finds scroll view matching direction's axis)
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

- `elementTarget: ActionTarget?` - Element whose nearest scroll view ancestor to scroll (axis-aware)
- `edge: ScrollEdge` - Which edge to scroll to

### ElementMatcher

```swift
public struct ElementMatcher: Codable, Sendable, Equatable
```

Composable predicate for matching elements in the accessibility tree. All specified fields use AND semantics. Used by `scrollToVisible`, `wait_for`, `get_interface` filtering, and all action commands via `ActionTarget.match`.

#### Properties

- `label: String?` - Exact match on accessibility label
- `identifier: String?` - Exact match on accessibility identifier
- `value: String?` - Exact match on accessibility value
- `traits: [String]?` - All listed traits must be present
- `excludeTraits: [String]?` - None of the listed traits may be present
- `absent: Bool?` - When `true`, inverts the match — succeeds when no element matches

### ScrollToVisibleTarget

```swift
public struct ScrollToVisibleTarget: Codable, Sendable
```

#### Properties

- `heistId: String?` - Stable heistId to search for while scrolling
- `match: ElementMatcher?` - Predicate for the element to find
- `direction: ScrollSearchDirection?` - Starting scroll direction (default: `.down`), adapted to each container's natural axis

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

Diagnostic output from `scrollToVisible`.

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

Target for `wait_for` command — waits for an element matching a predicate to appear or disappear.

#### Properties

- `match: ElementMatcher` - Predicate describing the element to wait for
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

Device and app metadata received after connecting.

#### Properties

- `protocolVersion: String` - Protocol version (e.g., "6.4")
- `appName: String` - App display name
- `bundleIdentifier: String` - App bundle identifier
- `deviceName: String` - Device name
- `systemVersion: String` - iOS version
- `screenWidth: Double` - Screen width in points
- `screenHeight: Double` - Screen height in points
- `screenSize: CGSize` - Computed from width/height
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

- `timestamp: Date` - When the hierarchy was captured
- `elements: [HeistElement]` - Flat list of UI elements
- `tree: [ElementNode]?` - Optional tree structure with containers
- `screenDescription: String` - Deterministic one-line screen summary (e.g. `"Sign In — 1 text field, 1 password field, 3 buttons"`)
- `screenId: String?` - Slugified screen name for machine use (e.g. `"controls_demo"`), derived from the first header element's label

### ElementNode

```swift
public indirect enum ElementNode: Codable, Equatable, Sendable
```

Recursive tree structure for UI element snapshot.

#### Cases

- `element(order: Int)` - Leaf node referencing element by index
- `container(Group, children: [ElementNode])` - Container with children

### Group

```swift
public struct Group: Codable, Equatable, Hashable, Sendable
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `type` | `String` | "semanticGroup", "list", "landmark", or "dataTable" |
| `label` | `String?` | Container's label |
| `value` | `String?` | Container's value |
| `identifier` | `String?` | Container's identifier |
| `frameX` | `Double` | Frame X origin |
| `frameY` | `Double` | Frame Y origin |
| `frameWidth` | `Double` | Frame width |
| `frameHeight` | `Double` | Frame height |

### HeistElement

```swift
public struct HeistElement: Codable, Equatable, Hashable, Sendable
```

Represents a single UI element captured from the accessibility hierarchy.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `heistId` | `String` | Stable identifier for targeting (developer identifier or synthesized from traits + label) |
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

#### Computed Properties

```swift
public var frame: CGRect            // Frame as CGRect
public var activationPoint: CGPoint // Activation point as CGPoint
```

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

These are from the full AXRuntime trait space. Marked `isExtendedPrivate = true` on `HeistTrait`. Useful for diagnostics and advanced filtering.

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
- `message: String?` - Additional context or error description
- `value: String?` - Current text field value (populated by `typeText`)
- `interfaceDelta: InterfaceDelta?` - Compact delta describing what changed after the action
- `animating: Bool?` - `true` if UI was still animating when result was produced; `nil` means idle
- `screenName: String?` - Label of the first header element in the post-action snapshot
- `screenId: String?` - Slugified screen name for machine use (e.g. `"controls_demo"`)
- `scrollSearchResult: ScrollSearchResult?` - Diagnostics from `scrollToVisible` (scroll count, unique elements seen, total items, exhaustive flag, matched element)
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
- `scrollToVisible` - Bidirectional scroll search found (or failed to find) element matching predicate
- `scrollToEdge` - Scroll view scrolled to an edge
- `explore` - Full element census completed (dispatched internally by `get_interface` with `full: true`)
- `elementNotFound` - Element could not be found
- `elementDeallocated` - Element's view was deallocated

### ActionExpectation

```swift
public enum ActionExpectation: Codable, Sendable, Equatable
```

Outcome signal classifiers for actions. Attached to a request (not to a target type) so any action can opt in. Every action implicitly checks delivery (`success == true`); these tiers classify what kind of change the caller expected. Results report what actually happened — the caller decides what to do with it. In batches, a mismet expectation halts execution at the action that broke rather than letting later steps fail in a confusing state.

Expectations follow a **"say what you know"** design: agents express what they care about and omit what they don't. Optional fields act as filters — provide more to tighten the check, fewer to loosen it. The framework scans the result for any match. This minimizes cognitive load on the caller.

#### Cases

- `screenChanged` - Expected `interfaceDelta.kind == .screenChanged`
- `layoutChanged` - Expected `interfaceDelta.kind == .elementsChanged` (also met by `.screenChanged`)
- `valueChanged(heistId: String?, oldValue: String?, newValue: String?)` - Expected a value change in `interfaceDelta.valueChanges`. All fields optional — provide what you know, omit what you don't. Met when any entry matches all provided fields.

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

Screen capture payload.

#### Properties

- `pngData: String` - Base64-encoded PNG data
- `width: Double` - Screen width in points
- `height: Double` - Screen height in points
- `timestamp: Date` - When screenshot was captured

### RecordingConfig

```swift
public struct RecordingConfig: Codable, Sendable
```

Recording configuration sent with `startRecording`.

#### Properties

- `fps: Int?` - Frames per second (default: 8, range: 1-15)
- `scale: Double?` - Resolution scale factor (default: 1.0, range: 0.25-1.0)
- `inactivityTimeout: Double?` - Seconds of inactivity before auto-stop (default: 5.0)
- `maxDuration: Double?` - Maximum recording duration in seconds (default: 60.0)

### RecordingPayload

```swift
public struct RecordingPayload: Codable, Sendable
```

Completed recording payload.

#### Properties

- `videoData: String` - Base64-encoded H.264/MP4 video data
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
- `interfaceDelta: InterfaceDelta?` - Compact delta describing what changed in the hierarchy (from result.interfaceDelta)

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
**Version**: 0.2.15

All subcommands that connect to a device accept these connection options:

| Option | Description |
|--------|-------------|
| `--device <filter>` | Target a specific device by name, ID prefix, simulator UDID, or vendor ID |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUTTONHEIST_DEVICE` | Default device filter (overridden by `--device`) |
| `BUTTONHEIST_TOKEN` | Auth token for TheInsideJob |
| `BUTTONHEIST_DRIVER_ID` | Driver identity for session locking (distinguishes drivers sharing the same token) |
| `BUTTONHEIST_SESSION_TIMEOUT` | Default idle timeout in seconds for `buttonheist session` (overridden by `--session-timeout`) |

Flags always take precedence over environment variables.

### buttonheist list_devices

List discovered devices that answer a lightweight `status` probe.

```
USAGE: buttonheist list_devices [OPTIONS]

OPTIONS:
  -t, --timeout <seconds> Discovery timeout in seconds (default: 3)
  -f, --format <format>   Output format: human, json (default: human)
```

Human output shows device index, short ID, app name, device name, and any device identifiers (simulator UDID or vendor identifier). Before printing, the CLI verifies each discovered endpoint with an unauthenticated `status` RPC so stale Bonjour entries are filtered out. JSON output includes all fields.

### buttonheist activate

Activate a UI element — the primary interaction command. Uses the activation-first pattern: tries `accessibilityActivate()` (like VoiceOver double-tap) first, then falls back to synthetic tap at the element's activation point. This is the most reliable way to interact with buttons, links, and controls.

```
USAGE: buttonheist activate [OPTIONS]

OPTIONS:
  --identifier <id>       Element accessibility identifier
  --index <n>             Element traversal order index
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

Examples:
```bash
buttonheist activate --identifier loginButton
buttonheist activate --index 3
```

### buttonheist edit_action

Perform an edit menu action on the current first responder.

```
USAGE: buttonheist edit_action <action>

ARGUMENTS:
  <action>                Edit action: copy, paste, cut, select, selectAll

OPTIONS:
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

Examples:
```bash
buttonheist edit_action copy
buttonheist edit_action paste
buttonheist edit_action selectAll
```

### buttonheist dismiss_keyboard

Dismiss the software keyboard by resigning first responder.

```
USAGE: buttonheist dismiss_keyboard [OPTIONS]

OPTIONS:
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### Gesture Commands

Low-level touch gestures registered as top-level commands. For tapping buttons and controls, prefer `buttonheist activate`.

| Command | Description |
|---------|-------------|
| `buttonheist one_finger_tap` | Raw synthetic tap at coordinates or element center |
| `buttonheist long_press` | Long press at a point or element |
| `buttonheist swipe` | Swipe between two points or in a direction |
| `buttonheist drag` | Drag from one point to another |
| `buttonheist pinch` | Pinch/zoom at a point or element |
| `buttonheist rotate` | Rotate at a point or element |
| `buttonheist two_finger_tap` | Tap with two fingers at a point or element |

All gesture commands accept `--identifier <id>` or `--index <n>` to target an element, or coordinate options (`--x`, `--y`, `--from-x`, `--from-y`, `--to-x`, `--to-y`) for explicit positioning, and `--device` to target a specific device.

### buttonheist type_text

Type text into a field by tapping keyboard keys.

```
USAGE: buttonheist type_text [OPTIONS]

OPTIONS:
  --text <text>           Text to type
  --delete <n>            Number of characters to delete before typing
  --identifier <id>       Element identifier (focuses field, reads value back)
  --index <n>             Element index (focuses field, reads value back)
  -t, --timeout <seconds> Timeout in seconds (default: 30)
  -q, --quiet             Suppress status messages
```

Outputs the current text field value to stdout after the operation. If no element target is provided, outputs "success".

Examples:
```bash
# Type text and get the resulting value
buttonheist type_text --text "Hello" --identifier "nameField"
# Output: Hello

# Delete 3 characters
buttonheist type_text --delete 3 --identifier "nameField"
# Output: He

# Delete and retype (correction)
buttonheist type_text --delete 2 --text "llo World" --identifier "nameField"
# Output: Hello World
```

### buttonheist scroll

Scroll the nearest scroll view ancestor by one page.

```
USAGE: buttonheist scroll [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier (scroll bubbles up to nearest scroll view)
  --index <n>             Element index
  --direction <dir>       Scroll direction: up, down, left, right, next, previous
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist scroll_to_visible

Search for an element by scrolling through the nearest scroll view. Matches elements
by any combination of label, identifier, heistId, value, and traits (AND semantics).
For UITableView/UICollectionView, provides exhaustive search with item count tracking.

```
USAGE: buttonheist scroll_to_visible [OPTIONS]

OPTIONS:
  --label <text>          Match element by accessibility label (exact)
  --identifier <id>       Match element by accessibility identifier (exact)
  --heist-id <id>         Match element by heistId (exact)
  --value <text>          Match element by accessibility value (exact)
  --traits <trait>        Required traits (all must be present, repeatable)
  --exclude-traits <trait> Excluded traits (none may be present, repeatable)
  --scope <scope>         Match scope: elements (default), containers, both
  --max-scrolls <n>       Maximum scroll attempts (default: 20, minimum: 1)
  --direction <dir>       Starting scroll direction: down, up, left, right (default: down)
  -t, --timeout <seconds> Timeout in seconds (default: 30)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist scroll_to_edge

Scroll the nearest scroll view ancestor to an edge.

```
USAGE: buttonheist scroll_to_edge [OPTIONS]

OPTIONS:
  --identifier <id>       Element identifier
  --index <n>             Element index
  --edge <edge>           Target edge: top, bottom, left, right
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -f, --format <format>   Output format: human, json (default: human when interactive, json when piped)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist session

Start a persistent interactive session that accepts commands on stdin and writes responses to stdout. Interactive mode accepts plain-text commands (e.g. `tap myButton`). JSON input is always accepted (e.g. `{"command":"one_finger_tap"}`). Output is human-readable by default, compact JSON when piped.

```
USAGE: buttonheist session [OPTIONS]

OPTIONS:
  -f, --format <format>           Output format: human, json (default: human)
  -t, --timeout <seconds>         Timeout waiting for device (default: 0 = no timeout)
  --session-timeout <seconds>     Idle timeout — exit if no command received (0 = disabled)
  --token <token>                 Auth token from a previous connection
  --device <filter>               Target a specific device
```

The `--session-timeout` flag exits the session if no commands are received within the specified period. This prevents abandoned agent processes from holding sessions indefinitely. Also configurable via the `BUTTONHEIST_SESSION_TIMEOUT` environment variable.

**Human-friendly input:** In interactive mode, commands can be typed as plain text with positional arguments. Command aliases provide shortcuts for common operations. Use `help` to see all available commands.

| Shorthand | Resolves to |
|-----------|------------|
| `tap <id>` | `one_finger_tap` |
| `ui` | `get_interface` |
| `screen` | `get_screen` |
| `type "text"` | `type_text` |
| `press <id>` | `long_press` |
| `devices` | `list_devices` |
| `idle` | `wait_for_change` |
| `change` | `wait_for_change` |
| `wait` | `wait_for` |
| `record` | `start_recording` |

Elements can be targeted by accessibility identifier (`tap myButton`), by order number (`tap #3`), or by coordinates (`tap 100 200`). Key=value pairs work for any parameter (`press identifier=btn duration=2`).

**JSON input:** Each line of stdin can also be a JSON object with a `command` field. Each command produces exactly one response. Use `--format json` to force JSON output.

```bash
# Start an interactive session
buttonheist session

# Plain-text commands
echo 'tap myButton' | buttonheist session --format json

# JSON commands still work
echo '{"command":"get_interface"}' | buttonheist session --format json

# Read the current client-side session state without reconnect side effects
echo '{"command":"get_session_state"}' | buttonheist session --format json

# Execute multiple commands in one request
echo '{"command":"run_batch","steps":[{"command":"get_interface"},{"command":"wait_for_change","timeout":2}]}' | buttonheist session --format json

# Start a session with a 5-minute idle timeout (for agent use)
buttonheist session --format json --session-timeout 300
```

This command is useful for persistent connections where multiple commands need to share a single TCP session.

### buttonheist get_screen

Capture a screenshot from the connected device.

```
USAGE: buttonheist get_screen [OPTIONS]

OPTIONS:
  -o, --output <path>     Output file path (default: stdout as raw PNG)
  -t, --timeout <seconds> Timeout in seconds (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist start_recording

Record the screen as H.264/MP4 video. Recording auto-stops on inactivity.

```
USAGE: buttonheist start_recording [OPTIONS]

OPTIONS:
  -o, --output <path>         Output file path (default: recording.mp4)
  --fps <n>                   Frames per second (default: 8, range: 1-15)
  --scale <factor>            Resolution scale (default: 1.0, range: 0.25-1.0)
  --max-duration <seconds>    Maximum recording duration (default: 60)
  --inactivity-timeout <secs> Auto-stop after N seconds of inactivity (default: 5)
  -t, --timeout <seconds>     Timeout waiting for recording to complete (default: 120)
  -q, --quiet                 Suppress status messages
  --device <filter>           Target a specific device
```

### buttonheist stop_recording

Explicitly stop an in-progress recording. The recording payload is broadcast to all connected clients, so the original `record` process (running in background) receives it and writes the file.

```
USAGE: buttonheist stop_recording [OPTIONS]

OPTIONS:
  --timeout <seconds>     Connection timeout (default: 10)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

### buttonheist wait_for

Wait for an element matching a predicate to appear or disappear. Uses settle-event polling, not busy-waiting. Timeout is capped at 30 seconds.

```
USAGE: buttonheist wait_for [OPTIONS]

OPTIONS:
  --heist-id <id>         Element heistId (from get_interface)
  --identifier <id>       Accessibility identifier
  --label <text>          Accessibility label
  -t, --timeout <seconds> Maximum wait time (default: 10, max: 30)
  --absent                Wait for element to disappear instead
  -f, --format <format>   Output format: human, json (default: auto)
  -q, --quiet             Suppress status messages
  --device <filter>       Target a specific device
```

**Examples:**
```bash
# Wait for a loading spinner to disappear
buttonheist wait_for --label "Loading" --absent --timeout 5

# Wait for a welcome message to appear
buttonheist wait_for --label "Welcome" --timeout 10

# Wait for an element by heistId
buttonheist wait_for --heist-id button_login
```

### buttonheist watch

Watch a live session as a read-only observer. Streams JSON events to stdout until killed with Ctrl+C. Does not require a token by default and does not claim a session lock — multiple observers can observe simultaneously alongside an active driver.

```
USAGE: buttonheist watch [OPTIONS]

OPTIONS:
  --device <filter>       Target a specific device by name, ID prefix, or index
  -t, --timeout <seconds> Connection timeout (default: 30)
  --token <token>         Auth token (only needed if server requires INSIDEJOB_RESTRICT_WATCHERS)
```

**Output**: Newline-delimited JSON objects, each with a `type` field:

| Type | Description |
|------|-------------|
| `"info"` | Connection established, contains `ServerInfo` |
| `"interface"` | UI hierarchy update |
| `"interaction"` | Driver performed an action (contains command, result, delta) |

**Examples:**
```bash
# Watch the first available device
buttonheist watch

# Watch a specific device
buttonheist watch --device my-simulator

# Pipe to jq for formatted output
buttonheist watch | jq .

# Watch with auth (when server requires it)
buttonheist watch --token my-secret-token
```

---

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

**Info.plist:**
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>element inspector connection.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

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

        handoff.onConnected = { info in
            print("Connected to \(info.appName) on \(info.deviceName)")
        }

        handoff.onInterface = { iface, _ in
            print("Received \(iface.elements.count) elements")
            for element in iface.elements {
                print("  \(element.order): \(element.description)")
            }
        }

        handoff.onActionResult = { result, _ in
            print("Action: \(result.success ? "success" : "failed") via \(result.method)")
        }

        handoff.onScreen = { screenshot, _ in
            print("Screenshot: \(screenshot.width)x\(screenshot.height)")
        }

        handoff.onDisconnected = { reason in
            print("Disconnected: \(reason)")
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
let target = ActionTarget(identifier: "loginButton", order: nil)
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
buttonheist activate --index 3

# Named actions (increment, decrement, custom)
buttonheist activate --identifier volumeSlider --action increment
buttonheist activate --identifier volumeSlider --action decrement
buttonheist activate --identifier myCell --action "Delete"

# Edit actions
buttonheist edit_action copy
buttonheist edit_action paste
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
buttonheist rotate --x 200 --y 300 --angle 1.57
buttonheist two_finger_tap --identifier zoomControl

# Text entry
buttonheist type_text --text "Hello World" --identifier nameField
buttonheist type_text --delete 5 --text "World!" --identifier nameField

# Scroll commands
buttonheist scroll --identifier "buttonheist.longList.item-5" --direction up
buttonheist scroll --index 3 --direction down
buttonheist scroll_to_visible --label "Color Picker"
buttonheist scroll_to_visible --label "Settings" --traits header
buttonheist scroll_to_visible --identifier "buttonheist.longList.last" --direction up
buttonheist scroll_to_edge --identifier "buttonheist.longList.item-0" --edge bottom
```

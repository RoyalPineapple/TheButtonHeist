---
date: 2026-02-01T02:20:56+01:00
researcher: aodawa
git_commit: 65db7b97269498363f3c9704010a5254bd67d92a
branch: RoyalPineapple/accra
repository: switftui-accessibility-discovery
topic: "Comprehensive Codebase Documentation for Accra Accessibility Toolkit"
tags: [research, codebase, accessibility, ios, macos, swiftui, uikit, documentation]
status: complete
last_updated: 2026-02-01
last_updated_by: aodawa
---

# Research: Comprehensive Codebase Documentation for Accra Accessibility Toolkit

**Date**: 2026-02-01T02:20:56+01:00
**Researcher**: aodawa
**Git Commit**: 65db7b97269498363f3c9704010a5254bd67d92a
**Branch**: RoyalPineapple/accra
**Repository**: switftui-accessibility-discovery

## Research Question

Document the Accra codebase comprehensively to support creating README and documentation for the project.

## Summary

Accra is an accessibility inspection toolkit for iOS applications that enables real-time inspection of accessibility hierarchies from macOS. The project consists of five main modules:

1. **AccraCore** - Cross-platform shared types and wire protocol (iOS + macOS)
2. **AccraHost** - iOS server framework embedded in apps being inspected
3. **AccraClient** - macOS client library for discovery and connection
4. **AccraInspector** - macOS GUI application for visual inspection
5. **AccraCLI** - Command-line tool for scripting and CI integration

The system uses Bonjour for automatic device discovery and WebSocket over TCP for real-time communication of accessibility hierarchy data.

---

## Detailed Findings

### 1. AccraCore Module

**Location**: `AccraCore/Sources/AccraCore/`

AccraCore is the foundational cross-platform framework containing shared types, message protocols, and constants used by both iOS (AccraHost) and macOS (AccraClient) components.

#### Key Files

| File | Purpose |
|------|---------|
| `Messages.swift` | All shared types, protocols, and constants |

#### Service Discovery Constants

```swift
public let accraServiceType = "_a11ybridge._tcp"  // Bonjour service type
public let protocolVersion = "1.0"                 // Protocol version
```

#### Data Types

**AccessibilityElementData** - Represents a single accessibility element:
- `traversalIndex: Int` - VoiceOver reading order
- `description: String` - What VoiceOver reads aloud
- `label: String?` - Accessibility label
- `value: String?` - Current value (for controls)
- `traits: [String]` - Human-readable trait names ("button", "header", etc.)
- `identifier: String?` - Accessibility identifier
- `hint: String?` - Accessibility hint
- `frameX/Y/Width/Height: Double` - Screen coordinates
- `activationPointX/Y: Double` - Touch target center
- `customActions: [String]` - Custom action names

**HierarchyPayload** - Container for hierarchy snapshot:
- `timestamp: Date` - When captured
- `elements: [AccessibilityElementData]` - All elements

**ServerInfo** - Device/app metadata:
- `protocolVersion`, `appName`, `bundleIdentifier`
- `deviceName`, `systemVersion`
- `screenWidth`, `screenHeight`

#### Wire Protocol Messages

**Client → Server (ClientMessage)**:
- `.requestHierarchy` - Request current snapshot
- `.subscribe` - Enable automatic updates
- `.unsubscribe` - Disable updates
- `.ping` - Keepalive

**Server → Client (ServerMessage)**:
- `.info(ServerInfo)` - Connection metadata
- `.hierarchy(HierarchyPayload)` - Accessibility data
- `.pong` - Keepalive response
- `.error(String)` - Error message

---

### 2. AccraHost Module

**Location**: `AccraCore/Sources/AccraHost/`

AccraHost is an iOS-only WebSocket server that exposes the accessibility hierarchy of SwiftUI or UIKit applications to remote clients.

#### Key Files

| File | Purpose |
|------|---------|
| `AccraHost.swift` | Main server implementation (singleton) |

#### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    AccraHost                         │
├─────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  NetService │  │ NWListener  │  │   Parser    │ │
│  │  (Bonjour)  │  │ (WebSocket) │  │ (A11y Tree) │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────┘
```

#### Key Features

1. **Singleton Access**: `AccraHost.shared`
2. **WebSocket Server**: Uses Network framework with TCP + WebSocket protocol stack
3. **Bonjour Advertisement**: Advertises as `_a11ybridge._tcp` on local network
4. **Accessibility Parsing**: Uses AccessibilitySnapshotParser to traverse UIKit hierarchy
5. **Polling Support**: Configurable interval for automatic updates (default 1.0s)
6. **Change Detection**: Hash-based comparison to only broadcast when hierarchy changes

#### Public API

```swift
// Start the server
try AccraHost.shared.start()

// Enable automatic polling (interval in seconds)
AccraHost.shared.startPolling(interval: 1.0)

// Manual change notification
AccraHost.shared.notifyChange()

// Stop everything
AccraHost.shared.stop()
```

#### Integration Points

**SwiftUI Apps** (`@main` App struct):
```swift
init() {
    try? AccraHost.shared.start()
    AccraHost.shared.startPolling(interval: 1.0)
}
```

**UIKit Apps** (AppDelegate):
```swift
func application(_:didFinishLaunchingWithOptions:) -> Bool {
    try? AccraHost.shared.start()
    AccraHost.shared.startPolling(interval: 1.0)
    return true
}
```

#### Required Info.plist Entries

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Accessibility inspection over local network</string>
<key>NSBonjourServices</key>
<array>
    <string>_a11ybridge._tcp</string>
</array>
```

---

### 3. AccraClient Module

**Location**: `AccraCore/Sources/AccraClient/`

AccraClient is the macOS client library for discovering and connecting to iOS devices running AccraHost.

#### Key Files

| File | Purpose |
|------|---------|
| `AccraClient.swift` | Main public API, ObservableObject |
| `DeviceDiscovery.swift` | Bonjour/mDNS service discovery |
| `DeviceConnection.swift` | WebSocket client implementation |

#### Architecture

```
┌─────────────────────────────────────────────────────┐
│                   AccraClient                        │
├─────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐        │
│  │ DeviceDiscovery │    │ DeviceConnection │        │
│  │   (NWBrowser)   │    │  (NWConnection)  │        │
│  └─────────────────┘    └─────────────────┘        │
└─────────────────────────────────────────────────────┘
```

#### Dual API Design

**SwiftUI Integration** (ObservableObject):
```swift
@StateObject private var client = AccraClient()

// Published properties auto-update views
client.discoveredDevices    // [DiscoveredDevice]
client.connectionState      // .disconnected/.connecting/.connected/.failed
client.currentHierarchy     // HierarchyPayload?
client.serverInfo           // ServerInfo?
```

**Callback-based API** (non-SwiftUI):
```swift
let client = AccraClient()

client.onDeviceDiscovered = { device in ... }
client.onConnected = { serverInfo in ... }
client.onHierarchyUpdate = { payload in ... }
client.onDisconnected = { error in ... }
```

#### Connection States

| State | Description |
|-------|-------------|
| `.disconnected` | No active connection |
| `.connecting` | Connection in progress |
| `.connected` | Active WebSocket connection |
| `.failed(String)` | Connection failed with error |

#### Public Methods

```swift
client.startDiscovery()      // Begin Bonjour discovery
client.stopDiscovery()       // Stop discovery
client.connect(to: device)   // Connect to specific device
client.disconnect()          // Close connection
client.requestHierarchy()    // Manual refresh
```

---

### 4. AccraInspector Module

**Location**: `AccraInspector/Sources/`

AccraInspector is a macOS SwiftUI application providing a graphical interface for accessibility inspection.

#### Key Files

| File | Purpose |
|------|---------|
| `AccraInspectorApp.swift` | App entry point |
| `Views/ContentView.swift` | Main navigation and device list |
| `Views/HierarchyListView.swift` | Accessibility tree display |
| `Design/Colors.swift` | Semantic color definitions |
| `Design/Spacing.swift` | Layout constants |
| `Design/Typography.swift` | Font definitions |

#### UI Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  NavigationSplitView                     │
├─────────────────┬───────────────────────────────────────┤
│    Sidebar      │              Detail                    │
│  ┌───────────┐  │  ┌─────────────────────────────────┐  │
│  │  Devices  │  │  │        HierarchyListView        │  │
│  │   List    │  │  │  ┌─────────┬───────────────┐   │  │
│  │           │  │  │  │ Element │    Detail     │   │  │
│  │  • Dev 1  │  │  │  │  List   │    Panel      │   │  │
│  │  • Dev 2  │  │  │  │         │               │   │  │
│  └───────────┘  │  │  └─────────┴───────────────┘   │  │
└─────────────────┴───────────────────────────────────────┘
```

#### Features

- **Device Discovery**: Automatic Bonjour discovery with manual refresh
- **Real-time Updates**: Live hierarchy updates via subscription
- **Search/Filter**: Filter elements by label, description, or traits
- **Detail View**: Full element properties with text selection
- **Connection States**: Visual feedback for all connection states

#### Design System

**Colors** (`Color.Tree` namespace):
- `textPrimary`, `textSecondary`, `textTertiary`
- `background`, `rowHover`, `rowSelected`

**Typography** (`Font.Tree` namespace):
- `elementLabel` - 13pt regular
- `elementTrait` - 11pt monospaced
- `searchInput` - 14pt regular
- `detailSectionTitle` - Caption

**Spacing** (`TreeSpacing` enum):
- `rowHeight` - 28pt
- `searchHeight` - 32pt
- `unit` - 8pt base

---

### 5. AccraCLI Module

**Location**: `AccraCLI/`

AccraCLI is a Unix-standard command-line tool for scripting and CI integration.

#### Key Files

| File | Purpose |
|------|---------|
| `Sources/main.swift` | ArgumentParser command definition |
| `Sources/CLIRunner.swift` | Main execution logic |
| `Package.swift` | SPM package configuration |

#### Command-Line Interface

```
USAGE: accra [--format <format>] [--once] [--quiet] [--timeout <timeout>] [--verbose]

OPTIONS:
  -f, --format <format>   Output format: human, json (default: human)
  -o, --once              Single snapshot then exit (default: watch mode)
  -q, --quiet             Suppress status messages (only output data)
  -t, --timeout <timeout> Timeout in seconds waiting for device (default: 0)
  -v, --verbose           Show verbose output
  -h, --help              Show help information.
```

#### Output Formats

**Human-readable** (default):
```
Accessibility Hierarchy - 10:30:45 AM
=====================================
00  (staticText)  "Welcome"
01  (button)      "Sign In"
    Value: disabled
    Hint: Double tap to sign in
02  (textField)   "Email"
    Identifier: emailField
-------------------------------------
Total: 3 elements
```

**JSON** (`--format json`):
```json
{
  "timestamp": "2026-02-01T10:30:45Z",
  "elements": [
    {
      "traversalIndex": 0,
      "description": "Welcome",
      "traits": ["staticText"],
      ...
    }
  ]
}
```

#### Modes

| Mode | Flag | Behavior |
|------|------|----------|
| Watch | (default) | Continuous updates, keyboard commands |
| Single-shot | `--once` | Exit after first snapshot |

#### Watch Mode Commands

- `r` or `Enter` - Refresh hierarchy
- `q` - Quit

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Connection failed |
| 2 | No device found |
| 3 | Timeout |

---

### 6. TestApp Sample Applications

**Location**: `TestApp/`

Two sample iOS applications demonstrating AccraHost integration.

#### SwiftUI Test App

**Sources**: `TestApp/Sources/`

```swift
// AccessibilityTestApp.swift - Entry point
@main
struct AccessibilityTestApp: App {
    init() {
        try? AccraHost.shared.start()
        AccraHost.shared.startPolling(interval: 1.0)
    }
}
```

**UI Elements**:
- Form with text fields (name, email)
- Toggle for newsletter subscription
- Picker for notification frequency
- Submit/Cancel buttons
- Info label and external link

All elements have explicit accessibility identifiers.

#### UIKit Test App

**Sources**: `TestApp/UIKitSources/`

Three-tab application demonstrating different UIKit patterns:

1. **Form Tab** (`FormViewController`)
   - Text fields, switches, segmented controls, buttons
   - Grouped sections with labels

2. **Table View Tab** (`DemoTableViewController`)
   - 3 sections with multiple rows
   - Dynamic cell identifiers (`tableCell_{section}_{row}`)

3. **Collection View Tab** (`DemoCollectionViewController`)
   - 12-item grid with custom cells
   - Compositional layout (3 columns)
   - Custom `AccessibilityCell` with explicit accessibility configuration

---

### 7. Project Configuration

#### Tuist Setup

**Root Files**:
- `Project.swift` - Main project configuration
- `Workspace.swift` - Workspace definition
- `Tuist.swift` - Tuist configuration

#### Module Dependencies

```
                    ┌─────────────┐
                    │  AccraCore  │
                    └──────┬──────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │  AccraHost  │ │ AccraClient │ │   TestApp   │
    │   (iOS)     │ │   (macOS)   │ │   (iOS)     │
    └─────────────┘ └──────┬──────┘ └─────────────┘
                           │
           ┌───────────────┼───────────────┐
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐
    │  Inspector  │ │   AccraCLI  │
    │   (macOS)   │ │   (macOS)   │
    └─────────────┘ └─────────────┘
```

#### Platform Requirements

| Module | Platform | Minimum Version |
|--------|----------|-----------------|
| AccraCore | iOS + macOS | iOS 17.0 / macOS 14.0 |
| AccraHost | iOS | iOS 17.0 |
| AccraClient | macOS | macOS 14.0 |
| AccraInspector | macOS | macOS 14.0 |
| AccraCLI | macOS | macOS 14.0 |
| TestApp | iOS | iOS 17.0 |

#### External Dependencies

- **AccessibilitySnapshot** (Cash App) - Accessibility hierarchy parsing
- **swift-argument-parser** (Apple) - CLI argument parsing

---

## Code References

### Entry Points
- `AccraCore/Sources/AccraCore/Messages.swift` - Shared types
- `AccraCore/Sources/AccraHost/AccraHost.swift:13` - `AccraHost.shared` singleton
- `AccraCore/Sources/AccraClient/AccraClient.swift:28` - `AccraClient` class
- `AccraInspector/Sources/AccraInspectorApp.swift:4` - GUI app entry
- `AccraCLI/Sources/main.swift:5` - CLI entry

### Key Implementation Files
- `AccraCore/Sources/AccraHost/AccraHost.swift:46` - Server start
- `AccraCore/Sources/AccraClient/DeviceDiscovery.swift:19` - Bonjour browsing
- `AccraCore/Sources/AccraClient/DeviceConnection.swift:21` - WebSocket client
- `AccraInspector/Sources/Views/HierarchyListView.swift:4` - Tree display
- `AccraCLI/Sources/CLIRunner.swift:45` - CLI execution

---

## Architecture Documentation

### Communication Flow

```
1. iOS App starts AccraHost
   └── Advertises via Bonjour (_a11ybridge._tcp)

2. macOS client discovers device
   └── NWBrowser finds service

3. Client connects via WebSocket
   └── Server sends .info(ServerInfo)

4. Client subscribes to updates
   └── Sends .subscribe message

5. Server polls accessibility tree
   └── Compares hash, broadcasts if changed

6. Client receives hierarchy
   └── Updates UI or outputs to console
```

### Threading Model

All modules use `@MainActor` annotation for thread safety:
- AccraHost operations run on main thread (UIKit requirement)
- AccraClient publishes to main thread for SwiftUI
- Network callbacks dispatch via `Task { @MainActor in ... }`

---

## Related Research

- `research/swiftui-accessibility-insights.md` - SwiftUI accessibility research
- `research/private-api-findings.md` - iOS private API exploration
- `research/external-accessibility-client.md` - Cross-platform client implementation
- `thoughts/shared/plans/2026-01-31-accessibility-tree-design.md` - UI design plan
- `thoughts/shared/plans/2026-01-31-macos-ios-accessibility-bridge.md` - Bridge architecture
- `thoughts/shared/research/2026-01-31-accessibility-tree-visualization.md` - Visualization patterns

---

## Open Questions

1. **Test Coverage**: No unit or integration tests currently exist
2. **Error Recovery**: Connection recovery after network interruption not implemented
3. **Multiple Device Support**: CLI only connects to first discovered device
4. **Simulator Support**: Behavior on iOS Simulator vs physical device
5. **Performance**: Large hierarchy performance with many elements

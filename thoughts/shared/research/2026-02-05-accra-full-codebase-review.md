---
date: 2026-02-05T15:57:26Z
researcher: aodawa
git_commit: c5d26834af32770895d39cad81699bd3b25fe87f
branch: RoyalPineapple/ios26-interaction-fix
repository: RoyalPineapple/accra
topic: "Full Codebase Review - Accra iOS Accessibility Inspection Toolkit"
tags: [research, codebase, accra, ios, accessibility, macos, swiftui, uikit]
status: complete
last_updated: 2026-02-05
last_updated_by: aodawa
---

# Research: Full Codebase Review - Accra iOS Accessibility Inspection Toolkit

**Date**: 2026-02-05T15:57:26Z
**Researcher**: aodawa
**Git Commit**: c5d26834af32770895d39cad81699bd3b25fe87f
**Branch**: RoyalPineapple/ios26-interaction-fix
**Repository**: RoyalPineapple/accra

## Research Question

Comprehensive review of the entire Accra project: architecture, components, purpose, and how everything fits together.

## Summary

**Accra** is an accessibility inspection and automation toolkit for iOS apps. It enables real-time inspection and interaction with iOS app accessibility hierarchies from a Mac. The system follows a distributed client-server architecture:

- **AccraHost** (iOS): Server framework embedded in iOS apps that exposes the accessibility hierarchy over TCP
- **AccraClient** (macOS): Client library for discovering and connecting to AccraHost instances
- **AccraCore**: Cross-platform shared types and wire protocol definitions
- **AccraInspector**: macOS GUI application for visual inspection
- **AccraCLI**: Command-line tool for scripting and automation

Key capabilities include:
- Real-time accessibility element inspection with live updates
- Remote tap/activate actions on elements
- Screenshot capture with element overlay visualization
- USB and WiFi connectivity options
- Multiple client interfaces (GUI, CLI, Python scripts)

## Detailed Findings

### 1. AccraCore - Shared Protocol Types

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/AccraCore/Sources/AccraCore/Messages.swift`

AccraCore defines the wire protocol through Codable Swift types for JSON serialization:

#### Constants
- `accraServiceType = "_a11ybridge._tcp"` - Bonjour service type for discovery
- `protocolVersion = "2.0"` - Current protocol version

#### Client Messages (`ClientMessage` enum)
- `.requestHierarchy` - Request current accessibility tree
- `.subscribe` / `.unsubscribe` - Enable/disable automatic updates
- `.ping` - Keepalive message
- `.requestScreenshot` - Request PNG screenshot
- `.activate(ActionTarget)` - VoiceOver double-tap equivalent
- `.increment(ActionTarget)` / `.decrement(ActionTarget)` - Adjustable element control
- `.tap(TapTarget)` - Synthetic tap at coordinates or element
- `.performCustomAction(CustomActionTarget)` - Execute named custom action

#### Server Messages (`ServerMessage` enum)
- `.info(ServerInfo)` - Device/app metadata on connection
- `.hierarchy(HierarchyPayload)` - Accessibility tree data
- `.pong` - Ping response
- `.error(String)` - Error description
- `.actionResult(ActionResult)` - Action command outcome
- `.screenshot(ScreenshotPayload)` - Base64-encoded PNG

#### Data Types
- `AccessibilityElementData` - Flat element with frame, traits, activation point, custom actions
- `AccessibilityHierarchyNode` - Recursive tree structure with containers
- `AccessibilityContainerData` - Container metadata (list, landmark, table, semanticGroup)
- `ServerInfo` - Device name, iOS version, screen dimensions, bundle ID
- `ScreenshotPayload` - Base64 PNG data with dimensions and timestamp

---

### 2. AccraHost - iOS Server Framework

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/AccraCore/Sources/AccraHost/`

AccraHost is the iOS server that captures and broadcasts accessibility hierarchy to connected clients.

#### Auto-Start Mechanism
- ObjC `+load` method in `AccraHostLoader/AccraHostAutoStart.m:10-14`
- Calls `AccraHost_autoStartFromLoad()` via `@_cdecl` exported Swift function
- Reads configuration from environment variables or Info.plist:
  - `ACCRA_HOST_PORT` / `AccraHostPort` - Server port (default: 0 = auto)
  - `ACCRA_HOST_POLLING_INTERVAL` / `AccraHostPollingInterval` - Update interval (default: 1.0s)
  - `ACCRA_HOST_DISABLE` / `AccraHostDisableAutoStart` - Disable auto-start

#### Core Components

**AccraHost.swift** (singleton at line 20)
- `@MainActor` for UIKit thread safety
- `SimpleSocketServer` for TCP connections (line 29)
- `NetService` for Bonjour advertisement (line 30)
- `AccessibilityHierarchyParser` from AccessibilitySnapshot library (line 35)
- `TouchInjector` for synthetic touch events (line 36)
- Polling timer for hierarchy change detection with hash comparison

**SimpleSocketServer.swift**
- IPv6 dual-stack BSD socket implementation
- GCD-based async accept and read loops
- Newline-delimited JSON protocol (0x0A separator)
- Multiple concurrent client support
- SIGPIPE handling to prevent crashes

**TouchInjector.swift** - Touch synthesis system with three-level fallback:
1. Low-level synthetic IOHIDEvent injection
2. `accessibilityActivate()` API
3. `UIControl.sendActions(for: .touchUpInside)`

**SyntheticTouchFactory.swift** - Creates UITouch via private APIs
**SyntheticEventFactory.swift** - Creates UIEvent with attached touches
**IOHIDEventBuilder.swift** - Creates IOHIDEvent via dynamically loaded IOKit functions

**TapVisualizerView.swift** - Visual feedback overlay showing tap location with animation

#### Key Data Flow
1. AccraHost loads via ObjC `+load`
2. SimpleSocketServer binds to port, starts accept loop
3. NetService advertises `_a11ybridge._tcp`
4. Client connects, receives `ServerMessage.info`
5. Polling timer triggers hierarchy parsing
6. Changes detected via hash comparison, broadcast to all clients

---

### 3. AccraClient - macOS Client Library

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/AccraCore/Sources/AccraClient/`

AccraClient provides device discovery and connection management for macOS applications.

#### Core Components

**AccraClient.swift** - Main client facade
- `@MainActor` + `ObservableObject` for SwiftUI integration
- `@Published` properties: `discoveredDevices`, `connectedDevice`, `serverInfo`, `currentHierarchy`, `currentScreenshot`, `isDiscovering`, `connectionState`
- Callback closures for non-SwiftUI usage
- Async/await methods: `waitForActionResult(timeout:)`, `waitForScreenshot(timeout:)`

**DeviceDiscovery.swift** - Bonjour browser
- `NWBrowser` with service type `_a11ybridge._tcp` on domain `local.`
- Peer-to-peer discovery enabled
- Callbacks for device found/lost events

**DeviceConnection.swift** - TCP socket handler
- Two-phase connection: NWConnection resolves service to port, then BSD socket connects
- Connects to `127.0.0.1:port` (localhost via USB tunnel or WiFi)
- Background read loop with dispatch to main thread for callbacks
- Newline-delimited JSON message parsing

#### Connection State Machine
```
disconnected → connect() → connecting → success → connected
                              ↓                      ↓
                           failure              disconnect()
                              ↓                      ↓
                           failed ←─────────────────┘
```

---

### 4. AccraCLI - Command-Line Interface

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/AccraCLI/`

Command-line tool for scripting and automation built with Swift Argument Parser.

#### Commands

**watch** (default command)
- `--format <human|json>` - Output format
- `--once` - Single snapshot then exit
- `--quiet` - Suppress status messages
- `--timeout <seconds>` - Wait timeout
- `--verbose` - Show verbose output

**action** - Perform actions on elements
- `--identifier` - Element accessibility identifier
- `--index` - Traversal index
- `--type <activate|increment|decrement|tap|custom>` - Action type
- `--custom-action` - Custom action name
- `--x`, `--y` - Tap coordinates
- `--timeout`, `--quiet` - Standard options

**screenshot** - Capture screenshot
- `--output` - Output file path (default: stdout)
- `--timeout`, `--quiet` - Standard options

#### Implementation
- **CLIRunner.swift** - Main execution loop, client callbacks, output formatting
- Terminal raw mode for keyboard input in watch mode
- Change detection with `*` prefix for new elements
- Exit codes: success=0, connectionFailed=1, noDeviceFound=2, timeout=3

---

### 5. AccraInspector - macOS GUI Application

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/AccraInspector/Sources/`

SwiftUI-based macOS application for visual accessibility inspection.

#### Views

**ContentView.swift** - Root view with NavigationSplitView
- Sidebar: Device list with discovery toggle
- Detail: Three-pane layout when connected
  - Left (280px): Element hierarchy (tree or flat list)
  - Middle: Screenshot with element overlays
  - Right (250px): Element inspector

**HierarchyTreeView.swift** - Tree hierarchy display
- `TreeDisplayNode` struct for display model
- `TreeBuilder` converts AccessibilityHierarchyNode to display nodes
- SwiftUI List with children for hierarchical display

**HierarchyListView.swift** - Flat list with search
- `SearchBar` component with keyboard shortcut hint
- `ElementRowView` with colored circle, icon, and label
- Filters by label, description, or traits

**ScreenshotView.swift** - Screenshot display with overlays
- Base64 PNG decoding to NSImage
- `ElementOverlayView` renders colored rectangles on Canvas
- Tap and double-tap gestures for selection and activation
- Yellow flash animation on activation

**ElementInspectorView.swift** - Element detail view
- Sections: description, label, value, hint, traits, frame, activation point, identifier, custom actions
- Activate button with Return key shortcut

#### Design System
- **Colors.swift** - `Color.Tree` namespace with background, text, divider colors
- **Typography.swift** - `Font.Tree` namespace with element, search, detail fonts
- **Spacing.swift** - `TreeSpacing` enum with row heights, padding, unit values
- **ElementStyling.swift** - Color and icon mapping by trait type

---

### 6. TestApp - iOS Test Applications

**Location**: `/Users/aodawa/conductor/workspaces/accra/memphis/TestApp/`

Two iOS test applications that embed AccraHost for testing.

#### AccessibilityTestApp (SwiftUI)
- Bundle ID: `com.accra.testapp`
- Display name: "A11y SwiftUI"
- Form-based UI with sections:
  - Personal Information (text fields)
  - Preferences (toggle, picker)
  - Action Testing (button, slider, stepper)
  - Submit/Cancel buttons
  - Accessibility Notifications (4 notification types)
- Comprehensive accessibility identifiers: `accra.form.*`, `accra.action.*`, etc.

#### UIKitTestApp
- Bundle ID: `com.accra.uikittestapp`
- Display name: "A11y UIKit"
- Tab bar interface with 3 tabs:
  - Form: UITextField, UISwitch, UISegmentedControl, UIButton
  - Table: UITableView with sections and styled cells
  - Collection: UICollectionView with compositional layout

Both apps auto-start AccraHost via ObjC `+load` and include network permissions in Info.plist.

---

### 7. Build System and Dependencies

#### Tuist Configuration
- **Workspace.swift** - Includes main project and TestApp
- **Project.swift** - Defines 8 targets: AccraCore, AccraHost, AccraClient, AccraInspector, test targets
- **TestApp/Project.swift** - Defines 2 iOS app targets

#### Swift Package Manager
- **AccraCore/Package.swift** - Core package with 4 products
- **AccraCLI/Package.swift** - CLI executable with ArgumentParser dependency

#### External Dependencies
- **AccessibilitySnapshot** - Hierarchy parsing (local path reference)
- **swift-argument-parser** - CLI parsing (GitHub v1.3.0+)
- **swift-snapshot-testing** - Test utilities (transitive)

#### Scripts
- **accra_usb.py** - Python USB connection module (380 lines)
- **usb-connect.sh** - Bash USB connection helper with embedded Python

---

### 8. Test Suites

#### AccraCoreTests (8 test files)
- Message integration tests (full protocol flows)
- AccessibilityElementData tests (equality, hashability, encoding)
- ClientMessage/ServerMessage encoding tests
- HierarchyPayload and ScreenshotPayload tests
- ServerInfo and constants tests

#### AccraClientTests (4 test files)
- AccraClient state management tests
- ConnectionState enum tests
- DiscoveredDevice tests

#### AccraCLITests (5 test files)
- Action command encoding tests
- Exit code validation tests
- Output formatting tests
- Screenshot command tests

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Your Mac                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │  AccraInspector  │  │    accra CLI     │  │  Python/Scripts  │  │
│  │    (GUI app)     │  │                  │  │                  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  │
│           │                     │                     │            │
│           └─────────────────────┼─────────────────────┘            │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │   AccraClient   │  ← Bonjour discovery    │
│                        │   (framework)   │    or direct TCP        │
│                        └────────┬────────┘                         │
└─────────────────────────────────┼───────────────────────────────────┘
                                  │ Local Network / USB (IPv6)
┌─────────────────────────────────┼───────────────────────────────────┐
│                        ┌────────┴────────┐                         │
│                        │   AccraHost     │  ← Auto-starts on load  │
│                        │   (framework)   │    Port 1455            │
│                        └────────┬────────┘                         │
│                                 │                                   │
│                        ┌────────┴────────┐                         │
│                        │  Your iOS App   │                         │
│                        └─────────────────┘                         │
│                           iOS Device                                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Code References

### Key Files
- `AccraCore/Sources/AccraCore/Messages.swift` - Wire protocol types (323 lines)
- `AccraCore/Sources/AccraHost/AccraHost.swift` - iOS server (872 lines)
- `AccraCore/Sources/AccraHost/SimpleSocketServer.swift` - TCP server (227 lines)
- `AccraCore/Sources/AccraHost/TouchInjector.swift` - Touch synthesis (208 lines)
- `AccraCore/Sources/AccraClient/AccraClient.swift` - macOS client (280 lines)
- `AccraCore/Sources/AccraClient/DeviceConnection.swift` - TCP connection (233 lines)
- `AccraCLI/Sources/main.swift` - CLI entry point
- `AccraCLI/Sources/CLIRunner.swift` - CLI implementation (276 lines)
- `AccraInspector/Sources/Views/ContentView.swift` - GUI main view (166 lines)

### Configuration
- **Wire Protocol Port**: 1455 (configurable via Info.plist)
- **Bonjour Service**: `_a11ybridge._tcp`
- **Protocol Version**: 2.0
- **Polling Interval**: 1.0s (minimum 0.5s)
- **Debounce Interval**: 300ms

---

## Related Research

- `thoughts/shared/research/2026-02-01-accra-codebase-documentation.md` - Previous codebase documentation
- `thoughts/shared/research/2026-02-04-ios26-interaction-support.md` - iOS 26 touch injection research

---

## Open Questions

None at this time - comprehensive review complete.

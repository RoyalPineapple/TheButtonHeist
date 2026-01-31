# Round-Trip Accessibility Testing Implementation Plan

## Overview

Enable full round-trip testing where navigating through the iOS app in the Simulator automatically updates the accessibility hierarchy displayed in the CLI tool in real-time.

## Current State Analysis

The accessibility bridge system is functional but has a critical limitation:

**What works:**
- iOS server starts and advertises via Bonjour
- macOS CLI discovers and connects via WebSocket
- Initial hierarchy is received and displayed
- Updates broadcast to subscribed clients

**What doesn't work:**
- Server only observes VoiceOver-specific notifications (`elementFocusedNotification`, `voiceOverStatusDidChangeNotification`)
- General UI interactions (button taps, state changes, navigation) do NOT trigger hierarchy updates
- User cannot see real-time changes when interacting with the app normally

### Key Files:
- Server: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeServer/AccessibilityBridgeServer.swift:246-264`
- CLI: `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift`
- Test app: `test-aoo/test-aoo/ContentView.swift`

## Desired End State

When the user interacts with the iOS app (taps buttons, navigates screens, changes state), the CLI tool should:
1. Automatically receive updated hierarchy data
2. Display the new accessibility tree with changes highlighted
3. Show a timestamp to confirm updates are real-time

### Verification:
1. Run the test app in Simulator
2. Run `a11y-inspect` CLI tool
3. Tap buttons in the app, watch CLI update automatically
4. Changes in `accessibilityInfo` text should appear in CLI within ~500ms

## What We're NOT Doing

- Adding a GUI client (CLI only for now)
- Implementing element interaction (read-only inspection)
- Adding persistence or logging
- Supporting multiple simultaneous apps

## Implementation Approach

Three-pronged approach to detect UI changes:

1. **App-level notification hook** - Apps call `notifyChange()` when state changes (most accurate)
2. **Polling fallback** - Configurable periodic hierarchy scan (catches everything but uses resources)
3. **Manual refresh** - CLI command to request immediate update (user control)

---

## Phase 1: Add Manual Change Notification API

### Overview
Add a public method that iOS apps can call to notify the bridge when their UI changes. This is the most reliable way to detect changes since the app knows when its state updates.

### Changes Required:

#### 1. AccessibilityBridgeServer - Add Public Notification Method
**File**: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeServer/AccessibilityBridgeServer.swift`

Add after line 91 (after `stop()` method):

```swift
/// Notify the bridge that the UI has changed and subscribers should receive an update.
/// Call this from your app whenever state changes that affect the accessibility hierarchy.
public func notifyChange() {
    guard isRunning else { return }
    scheduleHierarchyUpdate()
}
```

#### 2. Test App - Call notifyChange on State Updates
**File**: `test-aoo/test-aoo/ContentView.swift`

Update `accessibilityInfo` to trigger notification:

```swift
@State private var accessibilityInfo: String = "Tap a button to inspect accessibility" {
    didSet {
        // Notify bridge when accessibility info changes
        AccessibilityBridgeServer.shared.notifyChange()
    }
}
```

**Note**: SwiftUI @State doesn't support `didSet`. Instead, use `.onChange`:

```swift
var body: some View {
    VStack(spacing: 16) {
        // ... existing content ...
    }
    .padding()
    .onChange(of: accessibilityInfo) { _, _ in
        AccessibilityBridgeServer.shared.notifyChange()
    }
}
```

#### 3. Add AccessibilityBridgeServer Import
**File**: `test-aoo/test-aoo/ContentView.swift`

Add import at top:
```swift
import AccessibilityBridgeServer
```

### Success Criteria:

#### Automated Verification:
- [ ] Project builds: `xcodebuild -project test-aoo/test-aoo.xcodeproj -scheme test-aoo -destination 'platform=iOS Simulator,name=iPhone 16' build`
- [ ] No compiler warnings related to onChange

#### Manual Verification:
- [ ] Run test app in Simulator
- [ ] Run `a11y-inspect` CLI
- [ ] Tap "Parser" button in app
- [ ] CLI should show updated hierarchy with new `accessibilityInfo` content within 500ms

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation that tapping buttons triggers CLI updates before proceeding to Phase 2.

---

## Phase 2: Add Polling Support for Automatic Updates

### Overview
Add optional polling that periodically rescans the hierarchy. This catches changes from any source without requiring app modification.

### Changes Required:

#### 1. Add Polling Configuration and Timer
**File**: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeServer/AccessibilityBridgeServer.swift`

Add properties after line 28 (`updateDebounceInterval`):

```swift
// Polling for automatic updates (disabled by default)
private var pollingTask: Task<Void, Never>?
private var pollingInterval: UInt64 = 1_000_000_000 // 1 second in nanoseconds
private var isPollingEnabled = false
private var lastHierarchyHash: Int = 0
```

Add methods after `notifyChange()`:

```swift
/// Enable polling for automatic hierarchy updates.
/// - Parameter interval: Polling interval in seconds (default 1.0, minimum 0.5)
public func startPolling(interval: TimeInterval = 1.0) {
    let clampedInterval = max(0.5, interval)
    pollingInterval = UInt64(clampedInterval * 1_000_000_000)
    isPollingEnabled = true
    startPollingLoop()
    print("[AccessibilityBridge] Polling enabled (interval: \(clampedInterval)s)")
}

/// Disable polling for automatic updates
public func stopPolling() {
    isPollingEnabled = false
    pollingTask?.cancel()
    pollingTask = nil
    print("[AccessibilityBridge] Polling disabled")
}

private func startPollingLoop() {
    pollingTask?.cancel()
    pollingTask = Task { @MainActor in
        while isPollingEnabled && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollingInterval)
            if !Task.isCancelled && isPollingEnabled {
                checkForChanges()
            }
        }
    }
}

private func checkForChanges() {
    guard !subscribedConnections.isEmpty else { return }
    guard let rootView = getRootView() else { return }

    let markers = parser.parseAccessibilityElements(in: rootView)
    let elements = markers.enumerated().map { convertMarker($0.element, index: $0.offset) }

    // Compute hash of current hierarchy
    let currentHash = elements.hashValue

    // Only broadcast if hierarchy changed
    if currentHash != lastHierarchyHash {
        lastHierarchyHash = currentHash
        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
        let message = ServerMessage.hierarchy(payload)

        for connection in connections where subscribedConnections.contains(ObjectIdentifier(connection)) {
            send(message, to: connection)
        }
        print("[AccessibilityBridge] Polling detected change, broadcast to \(subscribedConnections.count) client(s)")
    }
}
```

#### 2. Update Test App to Enable Polling
**File**: `test-aoo/test-aoo/test_aooApp.swift`

Update the init to enable polling:

```swift
init() {
    Task { @MainActor in
        do {
            try AccessibilityBridgeServer.shared.start()
            // Enable polling for automatic updates during development
            AccessibilityBridgeServer.shared.startPolling(interval: 0.5)
            print("[test-aoo] AccessibilityBridgeServer started with polling")
        } catch {
            print("[test-aoo] Failed to start AccessibilityBridgeServer: \(error)")
        }
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Project builds successfully
- [ ] No memory leaks in polling loop (Task properly cancelled on stop)

#### Manual Verification:
- [ ] Run test app in Simulator
- [ ] Run `a11y-inspect` CLI
- [ ] Make any UI change (without calling notifyChange)
- [ ] CLI should update within 0.5-1 second automatically
- [ ] Verify console shows "Polling detected change" messages

**Implementation Note**: After completing this phase, verify that polling correctly detects changes and doesn't spam updates when nothing changes.

---

## Phase 3: Add CLI Refresh Command

### Overview
Add keyboard support to the CLI so users can manually trigger a refresh by pressing 'r' or Enter.

### Changes Required:

#### 1. Add Refresh Client Message
**File**: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Messages.swift`

The `requestHierarchy` case already exists, so no protocol change needed.

#### 2. Add Keyboard Input Handling to CLI
**File**: `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift`

Add keyboard monitoring method and update `browseForDevices()`:

```swift
private func startKeyboardMonitoring() {
    Task {
        // Set terminal to raw mode for immediate key reading
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ICANON | ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        let stdin = FileHandle.standardInput

        while isRunning {
            let data = stdin.availableData
            if let char = String(data: data, encoding: .utf8)?.first {
                await MainActor.run {
                    handleKeypress(char)
                }
            }
        }

        // Restore terminal
        tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
    }
}

private func handleKeypress(_ char: Character) {
    switch char.lowercased() {
    case "r", "\n", "\r":
        output("🔄 Refreshing...")
        send(.requestHierarchy)
    case "q":
        output("👋 Exiting...")
        stop()
    default:
        break
    }
}
```

Update the connection ready state to show help:

```swift
private func handleConnectionState(_ state: NWConnection.State) {
    switch state {
    case .ready:
        output("✅ Connected!")
        output("")
        output("Commands: [r]efresh  [q]uit")
        output("")
        receiveMessages()
        startKeyboardMonitoring()
    // ... rest unchanged
    }
}
```

Add import at top of file:
```swift
import Darwin
```

### Success Criteria:

#### Automated Verification:
- [ ] CLI builds successfully
- [ ] Terminal mode properly restored on exit

#### Manual Verification:
- [ ] Run CLI, connect to device
- [ ] Press 'r' - should refresh hierarchy
- [ ] Press 'q' - should exit cleanly
- [ ] Press Enter - should refresh
- [ ] Ctrl+C still works for emergency exit

---

## Phase 4: Enhanced CLI Output with Change Indicators

### Overview
Improve CLI output to show what changed between updates, making it easier to see the effect of interactions.

### Changes Required:

#### 1. Track Previous Hierarchy for Diff
**File**: `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift`

Add property to track previous state:

```swift
private var previousElements: [AccessibilityElementData] = []
```

Update `printHierarchy` to show changes:

```swift
private func printHierarchy(_ payload: HierarchyPayload) {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    output("📋 Accessibility Hierarchy (\(formatter.string(from: payload.timestamp)))")
    output(String(repeating: "─", count: 60))

    if payload.elements.isEmpty {
        output("   (no elements)")
    } else {
        let previousSet = Set(previousElements)
        let currentSet = Set(payload.elements)

        let added = currentSet.subtracting(previousSet)
        let removed = previousSet.subtracting(currentSet)

        for element in payload.elements {
            let indicator: String
            if added.contains(element) {
                indicator = "➕"
            } else if removed.contains(where: { $0.traversalIndex == element.traversalIndex }) {
                indicator = "🔄"
            } else {
                indicator = "  "
            }
            printElement(element, indicator: indicator)
        }

        // Store for next comparison
        previousElements = payload.elements
    }

    output(String(repeating: "─", count: 60))
    output("Total: \(payload.elements.count) elements")

    // Show summary of changes
    if !previousElements.isEmpty {
        let changes = payload.elements.count - previousElements.count
        if changes != 0 {
            output("Changes: \(changes > 0 ? "+" : "")\(changes) elements")
        }
    }

    output("")
    output("💡 Press [r] to refresh, [q] to quit")
    output("")
}

private func printElement(_ element: AccessibilityElementData, indicator: String = "  ") {
    let index = String(format: "[%2d]", element.traversalIndex)
    let traits = element.traits.isEmpty ? "" : " (\(element.traits.joined(separator: ", ")))"

    let label = element.label ?? element.description
    output("\(indicator) \(index) \(label)\(traits)")

    // ... rest of detail printing unchanged
}
```

### Success Criteria:

#### Automated Verification:
- [ ] CLI builds successfully

#### Manual Verification:
- [ ] Run test app and CLI
- [ ] Tap a button that changes accessibilityInfo
- [ ] CLI should show ➕ for new/changed elements
- [ ] Total count updates correctly

---

## Testing Strategy

### End-to-End Test Procedure:

1. **Build and run test app in Simulator:**
   ```bash
   xcodebuild -project test-aoo/test-aoo.xcodeproj -scheme test-aoo \
     -destination 'platform=iOS Simulator,name=iPhone 16' \
     build
   # Then run from Xcode or xcrun simctl
   ```

2. **Build and run CLI:**
   ```bash
   cd AccessibilityInspector
   swift build
   .build/debug/a11y-inspect
   ```

3. **Test interactions:**
   - CLI should connect and show initial hierarchy (5 elements)
   - Tap "Parser" button in app
   - CLI should update showing the accessibilityInfo text changed
   - Tap "Private API" button
   - CLI should update again
   - Press 'r' in CLI to manually refresh
   - Press 'q' to quit

### Expected CLI Output Flow:
```
🔍 Accessibility Inspector CLI
==============================

Searching for iOS devices...
✅ Found device: test-aoo-iPhone 16
   Connecting...

✅ Connected!

Commands: [r]efresh  [q]uit

📱 Device Info
   App: test-aoo
   Bundle ID: com.example.test-aoo
   Device: iPhone 16
   iOS: 18.0
   Screen: 393×852

📋 Accessibility Hierarchy (12:34:56)
────────────────────────────────────────────────────────────
   [ 0] Globe icon (image)
   [ 1] Greeting (staticText)
   [ 2] Inspect with parser (button)
   [ 3] Explore private APIs (button)
   [ 4] Tap a button to inspect accessibility (staticText)
────────────────────────────────────────────────────────────
Total: 5 elements

💡 Press [r] to refresh, [q] to quit

[User taps Parser button]

📋 Accessibility Hierarchy (12:34:58)
────────────────────────────────────────────────────────────
   [ 0] Globe icon (image)
   [ 1] Greeting (staticText)
   [ 2] Inspect with parser (button)
   [ 3] Explore private APIs (button)
🔄 [ 4] === AccessibilitySnapshotParser Results === ... (staticText)
────────────────────────────────────────────────────────────
Total: 5 elements

💡 Press [r] to refresh, [q] to quit
```

## Performance Considerations

- Polling at 0.5s interval uses minimal CPU (just hash comparison)
- Hash-based change detection avoids unnecessary JSON encoding/network traffic
- Debouncing (300ms) prevents rapid-fire updates from flooding clients
- Hierarchy parsing is already fast (~1ms for simple UIs)

## References

- Server implementation: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeServer/AccessibilityBridgeServer.swift`
- CLI implementation: `AccessibilityInspector/AccessibilityInspector/CLI/CLIRunner.swift`
- Protocol messages: `AccessibilityBridgeProtocol/Sources/AccessibilityBridgeProtocol/Messages.swift`
- Test app: `test-aoo/test-aoo/`

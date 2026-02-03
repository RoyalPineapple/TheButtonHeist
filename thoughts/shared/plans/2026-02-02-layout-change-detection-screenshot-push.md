# Accessibility Notification Interception & Proactive Screenshot Push

## Overview

Update AccraHost to intercept all `UIAccessibility.post` notifications, send them across the wire to connected clients, and push hierarchy + screenshot when layout/screen changes occur.

## Current State Analysis

**What exists:**
- `AccraHost.swift` observes `elementFocusedNotification` and `voiceOverStatusDidChangeNotification`
- Screenshots are only sent on-demand via `requestScreenshot` command
- Hierarchy updates are broadcast via `broadcastHierarchyUpdate()` with debouncing

**Limitation:**
- `UIAccessibility.Notification.layoutChanged` and `.screenChanged` are for *posting* to VoiceOver, not observing
- No way to detect when the app posts these notifications
- Mac client has no visibility into what accessibility notifications are being posted

### Key Discoveries:
- `AccraHost.swift:276-284` - Debounce mechanism already exists (`scheduleHierarchyUpdate`)
- `AccraHost.swift:540-574` - Screenshot capture logic already implemented
- `AccraHost.swift:286-302` - Broadcast mechanism to all clients exists
- `Messages.swift:94-112` - `ServerMessage` enum needs new case for notifications

## Desired End State

1. AccraHost intercepts ALL `UIAccessibility.post` notifications via swizzling
2. Each notification is sent to connected clients as a new `ServerMessage.accessibilityNotification`
3. When `.layoutChanged` or `.screenChanged` is detected, also push hierarchy + screenshot
4. Mac app displays/logs received accessibility notifications

**Verification:**
- Connect AccraInspector to an app
- When the app posts any accessibility notification, Mac client receives it
- On `.layoutChanged`/`.screenChanged`, also receive hierarchy + screenshot

## What We're NOT Doing

- Not using RunLoop observation
- Not using polling

## Implementation Approach

1. Add new `AccessibilityNotificationPayload` and `ServerMessage.accessibilityNotification` to wire protocol
2. Swizzle `UIAccessibility.post(notification:argument:)` to intercept all notifications
3. Send each notification to clients immediately
4. For `.layoutChanged`/`.screenChanged`, also trigger debounced hierarchy + screenshot

---

## Phase 1: Add Wire Protocol Message for Notifications

### Overview
Add new message type to send accessibility notifications to clients.

### Changes Required:

#### 1. Messages.swift - Add AccessibilityNotificationPayload
**File**: `AccraCore/Sources/AccraCore/Messages.swift`

Add after `ScreenshotPayload`:
```swift
/// Payload for accessibility notifications posted by the app
public struct AccessibilityNotificationPayload: Codable, Sendable {
    /// The notification type name
    public let notificationType: String
    /// String representation of the argument (if any)
    public let argument: String?
    /// Timestamp when notification was posted
    public let timestamp: Date

    public init(notificationType: String, argument: String?, timestamp: Date = Date()) {
        self.notificationType = notificationType
        self.argument = argument
        self.timestamp = timestamp
    }
}
```

#### 2. Messages.swift - Add ServerMessage case
**File**: `AccraCore/Sources/AccraCore/Messages.swift`

Add to `ServerMessage` enum:
```swift
/// Accessibility notification was posted by the app
case accessibilityNotification(AccessibilityNotificationPayload)
```

### Success Criteria:
- [x] Project compiles with new message types

---

## Phase 2: Swizzle UIAccessibility.post to Intercept All Notifications

### Overview
Create observer that swizzles `UIAccessibility.post` and reports all notifications.

### Changes Required:

#### 1. Create AccessibilityNotificationObserver.swift
**File**: `AccraCore/Sources/AccraHost/AccessibilityNotificationObserver.swift`

```swift
#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Observes all UIAccessibility.post notifications via swizzling
final class AccessibilityNotificationObserver {

    static let shared = AccessibilityNotificationObserver()

    /// Called for every accessibility notification posted
    var onNotification: ((UIAccessibility.Notification, Any?) -> Void)?

    private static var isSwizzled = false

    private init() {}

    func startObserving() {
        Self.swizzleAccessibilityPost()
    }

    func stopObserving() {
        onNotification = nil
    }

    private static func swizzleAccessibilityPost() {
        guard !isSwizzled else { return }
        isSwizzled = true

        // UIAccessibility.post is a class method: +[UIAccessibility postNotification:argument:]
        guard let uiAccessibilityClass = NSClassFromString("UIAccessibility") else {
            NSLog("[AccessibilityNotificationObserver] Could not find UIAccessibility class")
            return
        }

        let originalSelector = NSSelectorFromString("postNotification:argument:")
        let swizzledSelector = #selector(swizzled_postNotification(_:argument:))

        guard let originalMethod = class_getClassMethod(uiAccessibilityClass, originalSelector),
              let swizzledMethod = class_getClassMethod(AccessibilityNotificationObserver.self, swizzledSelector) else {
            NSLog("[AccessibilityNotificationObserver] Could not find methods to swizzle")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
        NSLog("[AccessibilityNotificationObserver] Swizzled UIAccessibility.post")
    }

    @objc dynamic class func swizzled_postNotification(_ notification: UIAccessibility.Notification, argument: Any?) {
        // Call original implementation (now swizzled to this selector)
        swizzled_postNotification(notification, argument: argument)

        // Notify observer
        DispatchQueue.main.async {
            shared.onNotification?(notification, argument)
        }
    }

    /// Convert notification to human-readable name
    static func notificationName(_ notification: UIAccessibility.Notification) -> String {
        switch notification {
        case .screenChanged: return "screenChanged"
        case .layoutChanged: return "layoutChanged"
        case .announcement: return "announcement"
        case .pageScrolled: return "pageScrolled"
        default:
            return "unknown(\(notification.rawValue))"
        }
    }
}
#endif
```

#### 2. AccraHost.swift - Integrate Observer and Send Notifications
**File**: `AccraCore/Sources/AccraHost/AccraHost.swift`

Update `startAccessibilityObservation()`:
```swift
private func startAccessibilityObservation() {
    // Existing NotificationCenter observers...
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(accessibilityDidChange),
        name: UIAccessibility.elementFocusedNotification,
        object: nil
    )
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(accessibilityDidChange),
        name: UIAccessibility.voiceOverStatusDidChangeNotification,
        object: nil
    )

    // Observe all UIAccessibility.post notifications via swizzling
    AccessibilityNotificationObserver.shared.onNotification = { [weak self] notification, argument in
        self?.handleAccessibilityNotification(notification, argument: argument)
    }
    AccessibilityNotificationObserver.shared.startObserving()
}
```

Add handler method:
```swift
private func handleAccessibilityNotification(_ notification: UIAccessibility.Notification, argument: Any?) {
    let notificationName = AccessibilityNotificationObserver.notificationName(notification)
    serverLog("Accessibility notification: \(notificationName)")

    // Send notification to all clients
    let argumentString: String?
    if let arg = argument {
        argumentString = String(describing: arg)
    } else {
        argumentString = nil
    }

    let payload = AccessibilityNotificationPayload(
        notificationType: notificationName,
        argument: argumentString
    )

    if let data = try? JSONEncoder().encode(ServerMessage.accessibilityNotification(payload)) {
        socketServer?.broadcastToAll(data)
    }

    // For layout/screen changes, also push hierarchy + screenshot
    if notification == .layoutChanged || notification == .screenChanged {
        scheduleHierarchyAndScreenshotUpdate()
    }
}

private func scheduleHierarchyAndScreenshotUpdate() {
    updateDebounceTask?.cancel()
    updateDebounceTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: updateDebounceInterval)
        if !Task.isCancelled {
            broadcastHierarchyAndScreenshot()
        }
    }
}

private func broadcastHierarchyAndScreenshot() {
    guard let rootView = getRootView() else { return }

    // Broadcast hierarchy
    cachedElements = parser.parseAccessibilityElements(in: rootView)
    let elements = cachedElements.enumerated().map { convertMarker($0.element, index: $0.offset) }
    let hierarchyPayload = HierarchyPayload(timestamp: Date(), elements: elements)
    lastHierarchyHash = elements.hashValue

    if let data = try? JSONEncoder().encode(ServerMessage.hierarchy(hierarchyPayload)) {
        socketServer?.broadcastToAll(data)
    }

    // Broadcast screenshot
    guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
          let window = windowScene.windows.first(where: {
              $0.windowLevel <= .statusBar && $0.rootViewController?.view != nil
          }) else { return }

    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    let image = renderer.image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }

    guard let pngData = image.pngData() else { return }

    let screenshotPayload = ScreenshotPayload(
        pngData: pngData.base64EncodedString(),
        width: window.bounds.width,
        height: window.bounds.height
    )

    if let data = try? JSONEncoder().encode(ServerMessage.screenshot(screenshotPayload)) {
        socketServer?.broadcastToAll(data)
    }

    serverLog("Broadcast hierarchy + screenshot")
}
```

Update `stopAccessibilityObservation()`:
```swift
private func stopAccessibilityObservation() {
    NotificationCenter.default.removeObserver(self)
    AccessibilityNotificationObserver.shared.stopObserving()
}
```

### Success Criteria:

#### Automated Verification:
- [x] Project builds: `tuist generate && xcodebuild -workspace Accra.xcworkspace -scheme AccraCore -destination 'platform=iOS Simulator,name=iPhone 16' build`

#### Manual Verification:
- [ ] Connect to TestApp
- [ ] Trigger accessibility notifications - verify they appear in Mac client
- [ ] Trigger `.layoutChanged` - verify hierarchy + screenshot also received

---

## Phase 3: Update Mac Client to Handle Notifications

### Overview
Update AccraClient and DeviceConnection to handle the new notification message, and display in Mac app.

### Changes Required:

#### 1. DeviceConnection.swift - Handle New Message Type
**File**: `AccraCore/Sources/AccraClient/DeviceConnection.swift`

Add callback property:
```swift
var onAccessibilityNotification: ((AccessibilityNotificationPayload) -> Void)?
```

Update `handleMessage()` switch:
```swift
case .accessibilityNotification(let payload):
    debug("Received accessibility notification: \(payload.notificationType)")
    onAccessibilityNotification?(payload)
```

#### 2. AccraClient.swift - Expose Notification Events
**File**: `AccraCore/Sources/AccraClient/AccraClient.swift`

Add published property and callback:
```swift
@Published public private(set) var currentScreenshot: ScreenshotPayload?
@Published public private(set) var recentNotifications: [AccessibilityNotificationPayload] = []

public var onAccessibilityNotification: ((AccessibilityNotificationPayload) -> Void)?
```

In `connect()`, wire up the handler:
```swift
connection?.onAccessibilityNotification = { [weak self] payload in
    self?.recentNotifications.append(payload)
    // Keep last 50 notifications
    if self?.recentNotifications.count ?? 0 > 50 {
        self?.recentNotifications.removeFirst()
    }
    self?.onAccessibilityNotification?(payload)
}

connection?.onScreenshot = { [weak self] payload in
    self?.currentScreenshot = payload
    self?.onScreenshot?(payload)
}
```

In `disconnect()`:
```swift
currentScreenshot = nil
recentNotifications.removeAll()
```

#### 3. ContentView.swift - Display Notifications (Optional)
**File**: `AccraInspector/Sources/Views/ContentView.swift`

Add a notifications log panel or indicator showing recent accessibility notifications.

### Success Criteria:

#### Manual Verification:
- [ ] Connect to TestApp
- [ ] Post accessibility notification in TestApp
- [ ] Mac app receives and displays the notification
- [ ] Screenshot updates on layout/screen changed

---

## Testing Strategy

### Manual Testing:
1. Add test buttons to TestApp that post various notifications:
   - `UIAccessibility.post(notification: .layoutChanged, argument: nil)`
   - `UIAccessibility.post(notification: .screenChanged, argument: nil)`
   - `UIAccessibility.post(notification: .announcement, argument: "Hello")`
2. Connect AccraInspector
3. Tap each button - verify notification appears in Mac client
4. Verify layout/screen changed also triggers hierarchy + screenshot

## Wire Protocol Update

### New ServerMessage Type

```json
{
  "accessibilityNotification": {
    "notificationType": "layoutChanged",
    "argument": null,
    "timestamp": "2026-02-02T10:30:45.123Z"
  }
}
```

### Notification Types

| notificationType | Description |
|-----------------|-------------|
| `layoutChanged` | App posted layout changed notification |
| `screenChanged` | App posted screen changed notification |
| `announcement` | App posted announcement (argument = text) |
| `pageScrolled` | App posted page scrolled notification |

## References

- `AccraHost.swift` - Current accessibility observation
- `Messages.swift` - ServerMessage types
- `DeviceConnection.swift` - Message handling on client

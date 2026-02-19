# Multi-Window Traversal & Edit Actions Implementation Plan

## Overview

Implement two features inspired by KIF's approach to system UI:

1. **Multi-window accessibility traversal** — `get_interface` scans all windows in the foreground scene (alerts, action sheets, picker views, dimming views), not just the main app window.
2. **Edit actions via responder chain** — Standard edit operations (copy, paste, cut, select, selectAll) invocable through SafeCracker, exposed as a new MCP tool.

## Current State Analysis

- `InsideMan.getRootView()` (`InsideMan.swift:303`) picks **one** window with `windowLevel <= .statusBar`, missing all overlay windows.
- `SafeCracker` (`SafeCracker.swift`) already handles keyboard input via private `UIKeyboardImpl` API and already iterates all windows for keyboard detection (`findKeyboardFrame()` at line 203).
- `handleScreen` / `broadcastScreen` also only render the main app window.
- The wire protocol (`Messages.swift`) has no edit action message type.
- The MCP server (`main.swift`) has no edit action tool.

### Key Discoveries:
- `SafeCracker.findKeyboardFrame()` already uses the multi-window pattern we need: `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }`
- `TapVisualizerView` uses a window with `windowLevel > .statusBar` — we need to exclude it from traversal by class name, not by window level (since we now want to include high-level windows like alerts).
- `AccessibilityHierarchyParser.parseAccessibilityHierarchy(in:)` works on a single root view — we'll call it once per window and concatenate results.

## Desired End State

1. `get_interface` returns elements from **all visible windows** in the foreground scene, ordered frontmost-first. The tree includes per-window container nodes so callers know which window each element belongs to.
2. A new `edit_action` MCP tool invokes standard edit actions (copy, paste, cut, select, selectAll) on the current first responder via `UIApplication.shared.sendAction()`. Implementation lives in SafeCracker.
3. Screenshots composite all visible windows (not just the main app window).

### Verification:
- Launch TestApp, present an alert → `get_interface` shows both the alert's elements AND the underlying screen elements
- Focus a text field, type text, call `edit_action` with `selectAll` then `copy` → succeeds
- Present an alert → `get_screen` shows the alert overlay in the screenshot

## What We're NOT Doing

- System alerts from **outside the app process** (permission dialogs, etc.) — these are in a separate process and inaccessible without XCUITest/springboard. Documented as known limitation.
- `UIRemoteView` content (photo picker, document picker) — same process boundary issue.
- iOS 16+ `UIEditMenuInteraction` detection — we bypass the menu entirely via responder chain, so both old and new menu APIs are irrelevant.

## Implementation Approach

Two independent phases that can be built and verified separately.

---

## Phase 1: Multi-Window Accessibility Traversal

### Overview
Replace single-window `getRootView()` with multi-window traversal. Parse each window's accessibility hierarchy separately, concatenate into a unified element list with globally unique indices.

### Changes Required:

#### 1. InsideMan.swift — Replace `getRootView()` with `getTraversableWindows()`

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Replace the single-window `getRootView()` method (lines 303-316) with a method that returns all traversable windows sorted by window level (frontmost first):

```swift
/// Returns all windows that should be included in the accessibility traversal,
/// sorted by windowLevel descending (frontmost first).
/// Excludes our own overlay windows (TapVisualizerView).
private func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
    guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
        return []
    }

    return windowScene.windows
        .filter { window in
            // Exclude our tap visualizer overlay
            !(window is TapOverlayWindow) &&
            // Must have a root view to traverse
            window.rootViewController?.view != nil
        }
        .sorted { $0.windowLevel > $1.windowLevel }
        .map { ($0, $0.rootViewController!.view) }
}
```

#### 2. InsideMan.swift — Update `refreshAccessibilityData()` for multi-window

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Replace the current implementation (lines 446-459) to iterate over all windows:

```swift
@discardableResult
private func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
    let windows = getTraversableWindows()
    guard !windows.isEmpty else { return nil }

    var allHierarchy: [AccessibilityHierarchy] = []
    var newInteractiveObjects: [Int: WeakObject] = [:]
    var allElements: [AccessibilityMarker] = []

    for (window, rootView) in windows {
        let baseIndex = allElements.count
        let windowTree = parser.parseAccessibilityHierarchy(in: rootView) { _, index, object in
            let globalIndex = baseIndex + index
            if object.accessibilityRespondsToUserInteraction
                || object.accessibilityTraits.contains(.adjustable)
                || !(object.accessibilityCustomActions ?? []).isEmpty {
                newInteractiveObjects[globalIndex] = WeakObject(object: object)
            }
        }
        let windowElements = windowTree.flattenToElements()

        // Wrap this window's tree in a container node if we have multiple windows
        if windows.count > 1 {
            let windowName = NSStringFromClass(type(of: window))
            let container = AccessibilityContainer(
                type: .semanticGroup(
                    label: windowName,
                    value: "windowLevel: \(window.windowLevel.rawValue)",
                    identifier: nil
                ),
                frame: window.frame
            )
            // Re-index the tree nodes to use global indices
            let reindexed = windowTree.reindexed(offset: baseIndex)
            allHierarchy.append(.container(container, reindexed))
        } else {
            allHierarchy.append(contentsOf: windowTree)
        }

        allElements.append(contentsOf: windowElements)
    }

    interactiveObjects = newInteractiveObjects
    cachedElements = allElements
    return allHierarchy
}
```

**Note**: The `reindexed(offset:)` helper needs to be added to `AccessibilityHierarchy` — see below.

#### 3. AccessibilityHierarchy — Add `reindexed(offset:)` helper

**File**: `AccessibilitySnapshot/Sources/AccessibilitySnapshot/Parser/Swift/Classes/AccessibilityHierarchy.swift`

Add a method to offset traversal indices in a hierarchy tree:

```swift
extension AccessibilityHierarchy {
    /// Returns a copy of this node with all traversal indices offset by the given amount.
    func reindexed(offset: Int) -> AccessibilityHierarchy {
        guard offset != 0 else { return self }
        switch self {
        case let .element(element, traversalIndex):
            return .element(element, traversalIndex + offset)
        case let .container(container, children):
            return .container(container, children.map { $0.reindexed(offset: offset) })
        }
    }
}

extension Array where Element == AccessibilityHierarchy {
    /// Returns a copy with all traversal indices offset by the given amount.
    func reindexed(offset: Int) -> [AccessibilityHierarchy] {
        guard offset != 0 else { return self }
        return map { $0.reindexed(offset: offset) }
    }
}
```

#### 4. TapVisualizerView — Make `TapOverlayWindow` accessible for filtering

**File**: `ButtonHeist/Sources/InsideMan/TapVisualizerView.swift`

Verify that `TapOverlayWindow` is a named class (not a local/anonymous type) so `getTraversableWindows()` can filter it by type. Looking at the existing code, it's already a named class — just needs to be non-private so InsideMan can reference it:

Change `private class TapOverlayWindow` → `class TapOverlayWindow` (internal access).

#### 5. InsideMan.swift — Update `broadcastScreen()` and `handleScreen()` for multi-window

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Update both screen capture methods to composite all visible windows:

```swift
private func captureScreen() -> (image: UIImage, bounds: CGRect)? {
    let windows = getTraversableWindows()
    guard let first = windows.last else { return nil } // .last = lowest level = background
    let bounds = first.window.bounds

    let renderer = UIGraphicsImageRenderer(bounds: bounds)
    let image = renderer.image { _ in
        // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
        for (window, _) in windows.reversed() {
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
    return (image, bounds)
}
```

Then refactor `handleScreen()` and `broadcastScreen()` to use `captureScreen()`.

### Success Criteria:

#### Automated Verification:
- [x] All targets build: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [x] TheGoods builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build`
- [x] MCP server builds: `cd ButtonHeistMCP && swift build -c release`
- [x] Existing tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`

#### Manual Verification (via MCP tools):
- [ ] `get_interface` with no overlay shows same elements as before (regression check)
- [ ] Present an alert in TestApp → `get_interface` includes alert button elements
- [ ] `get_screen` with alert visible → screenshot shows the alert

---

## Phase 2: Edit Actions via Responder Chain

### Overview
Add standard edit actions (copy, paste, cut, select, selectAll) to SafeCracker, expose via a new wire message and MCP tool.

### Changes Required:

#### 1. SafeCracker.swift — Add edit action methods

**File**: `ButtonHeist/Sources/InsideMan/SafeCracker.swift`

Add after the text input section (after line 185):

```swift
// MARK: - Edit Actions (via Responder Chain)

/// Standard edit actions that can be invoked on the first responder.
enum EditAction: String, CaseIterable {
    case copy
    case paste
    case cut
    case select
    case selectAll

    var selector: Selector {
        switch self {
        case .copy:      return #selector(UIResponderStandardEditActions.copy(_:))
        case .paste:     return #selector(UIResponderStandardEditActions.paste(_:))
        case .cut:       return #selector(UIResponderStandardEditActions.cut(_:))
        case .select:    return #selector(UIResponderStandardEditActions.select(_:))
        case .selectAll: return #selector(UIResponderStandardEditActions.selectAll(_:))
        }
    }
}

/// Perform a standard edit action on the current first responder.
/// Uses UIApplication.sendAction to route through the responder chain,
/// following KIF's pattern of bypassing the edit menu UI entirely.
/// - Returns: true if the action was handled by some responder
func performEditAction(_ action: EditAction) -> Bool {
    UIApplication.shared.sendAction(action.selector, to: nil, from: nil, for: nil)
}
```

#### 2. Messages.swift — Add wire protocol types

**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add to `ClientMessage` enum:

```swift
/// Perform a standard edit action (copy, paste, cut, select, selectAll) on the first responder
case editAction(EditActionTarget)
```

Add target struct:

```swift
/// Target for edit actions dispatched via the responder chain
public struct EditActionTarget: Codable, Sendable {
    /// The edit action to perform: "copy", "paste", "cut", "select", "selectAll"
    public let action: String

    public init(action: String) {
        self.action = action
    }
}
```

Add to `ActionMethod` enum:

```swift
case editAction
```

#### 3. InsideMan.swift — Handle the new message

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add case to `handleClientMessage` switch:

```swift
case .editAction(let target):
    handleEditAction(target, respond: respond)
```

Add handler method:

```swift
private func handleEditAction(_ target: EditActionTarget, respond: @escaping (Data) -> Void) {
    refreshAccessibilityData()
    let beforeElements = snapshotElements()

    guard let action = SafeCracker.EditAction(rawValue: target.action) else {
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .editAction,
            message: "Unknown edit action '\(target.action)'. Valid: \(SafeCracker.EditAction.allCases.map(\.rawValue).joined(separator: ", "))"
        )), respond: respond)
        return
    }

    let success = safeCracker.performEditAction(action)
    let result = actionResultWithDelta(success: success, method: .editAction, beforeElements: beforeElements)
    sendMessage(.actionResult(result), respond: respond)
}
```

#### 4. MCP Server — Add `edit_action` tool

**File**: `ButtonHeistMCP/Sources/main.swift`

Add tool definition:

```swift
let editActionTool = Tool(
    name: "edit_action",
    description: "Perform a standard edit action (copy, paste, cut, select, selectAll) on the current first responder via the responder chain. Works regardless of whether the edit menu is visible.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "action": .object([
                "type": .string("string"),
                "description": .string("Edit action to perform: copy, paste, cut, select, selectAll"),
                "enum": .array([.string("copy"), .string("paste"), .string("cut"), .string("select"), .string("selectAll")]),
            ]),
        ]),
        "required": .array([.string("action")]),
    ]),
    annotations: .init(readOnlyHint: false, idempotentHint: false, openWorldHint: false)
)
```

Add to `allTools` array and add handler in `handleToolCall`:

```swift
case "edit_action":
    guard let action = stringArg(args, "action") else {
        return errorResult("action is required (copy, paste, cut, select, selectAll)")
    }
    let message = ClientMessage.editAction(EditActionTarget(action: action))
    return try await sendAction(message, client: client)
```

### Success Criteria:

#### Automated Verification:
- [x] All targets build (same as Phase 1)
- [x] MCP server builds: `cd ButtonHeistMCP && swift build -c release`
- [x] Existing tests pass

#### Manual Verification (via MCP tools):
- [ ] Focus a text field with text → `edit_action` `selectAll` → `edit_action` `copy` → tap another field → `edit_action` `paste` → text appears in second field
- [ ] `edit_action` with invalid action name → returns error with valid action names

---

## Testing Strategy

### Automated Tests:
- Verify `SafeCracker.EditAction` enum has correct selectors
- Verify `EditActionTarget` encodes/decodes correctly
- Verify `AccessibilityHierarchy.reindexed(offset:)` works correctly

### Integration Tests (via MCP tools on simulator):
- Multi-window: present alert, verify elements appear in interface
- Edit actions: type text, select all, copy, paste into another field
- Screen capture: present alert, verify screenshot shows it

## References

- KIF research: `thoughts/shared/research/2026-02-18-kif-system-dialog-handling.md`
- KIF's window traversal: `UIApplication-KIFAdditions.m` → `windowsWithKeyWindow`
- KIF's edit menu bypass: `UIMenuController.shared.menuItems` + `performSelector:` on first responder
- InsideMan's existing multi-window keyboard scan: `SafeCracker.swift:203-213`

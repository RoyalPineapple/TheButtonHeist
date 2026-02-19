# Stakeout "Smart Remote" Redesign — Implementation Plan

## Overview

Redesign the Stakeout Mac app from an **accessibility inspector** into a **remote driver**. The screenshot is the primary view, but interaction follows a **VoiceOver-style select-then-act model**: click to select an element, double-click to activate, and use explicit action buttons for everything else (swipe, long press, type text, increment/decrement, etc.). No gesture translation or direct manipulation — every action is deliberate and button-driven.

## Current State Analysis

The app currently has a three-pane "inspector" layout:
- **Left (280px)**: Element hierarchy list (tree or flat view with search)
- **Center**: Screenshot with colored element overlay rectangles
- **Right (250px)**: Element property inspector (label, value, identifier, frame, actions)

This layout is optimized for *reading accessibility metadata*. The only interaction is double-clicking an element to activate it (which calls `accessibilityActivate()`). None of the protocol's rich gesture vocabulary (swipe, drag, pinch, rotate, long press, text input, path drawing) is exposed in the GUI.

### Key Files Affected:
- `Stakeout/Sources/StakeoutApp.swift` — Window configuration
- `Stakeout/Sources/Views/ContentView.swift` — Root view, three-pane layout, state management
- `Stakeout/Sources/Views/ScreenshotView.swift` — Screenshot display + overlay hosting
- `Stakeout/Sources/Views/ElementOverlayView.swift` — Canvas element drawing + hit testing
- `Stakeout/Sources/Views/ElementInspectorView.swift` — Property inspector panel
- `Stakeout/Sources/Views/HierarchyTreeView.swift` — Tree view of elements
- `Stakeout/Sources/Views/HierarchyListView.swift` — Flat searchable list of elements
- `Stakeout/Sources/Design/ElementStyling.swift` — Color/icon mapping for elements

### What We Keep (No Changes):
- `ButtonHeist/Sources/ButtonHeist/HeistClient.swift` — Already has all needed plumbing
- `ButtonHeist/Sources/Wheelman/*` — Discovery and connection layer
- `ButtonHeist/Sources/TheGoods/Messages.swift` — Wire protocol (already supports all gestures)
- `ButtonHeist/Sources/InsideMan/*` — iOS-side implementation

## Desired End State

A Mac app that feels like a **VoiceOver-style remote control**:

1. The **device screenshot** is the primary view, taking most of the window space.
2. **Click** on the screenshot **selects** the element under the cursor (highlights it, shows its info).
3. **Double-click** on an element **activates** it (like VoiceOver's double-tap).
4. An **action panel** below or beside the screenshot shows explicit buttons for all available actions on the selected element:
   - **Element actions**: Activate, Increment, Decrement, custom actions (derived from selected element's `actions` array)
   - **Touch gestures**: Tap, Long Press, Swipe (Up/Down/Left/Right)
   - **Text input**: Text field + send button for typing into focused fields
   - **Advanced**: Pinch In/Out, Rotate, Two-Finger Tap
5. **Hover** shows a subtle highlight on the element under the cursor.
6. A **toolbar** at the top shows connection status and a device picker dropdown.
7. An optional **element overlay toggle** shows/hides subtle element boundaries.

### Verification:
- All gesture types from the wire protocol are accessible via explicit action buttons
- The app connects to the same iOS devices via the same protocol
- A developer can perform full app navigation (tap buttons, scroll lists, type text, use sliders) by selecting elements and pressing action buttons

## What We're NOT Doing

- **No changes to the wire protocol** — the protocol already supports everything we need
- **No changes to HeistClient** — the client API is already sufficient
- **No changes to InsideMan (iOS side)** — the server is already feature-complete
- **No CLI/MCP changes** — those are separate interfaces, unaffected
- **No new test targets** — we're reshaping existing SwiftUI views, not adding new frameworks
- **No multi-window support** — single window, single device connection

## Implementation Approach

Replace the inspector-oriented views with a remote-control interface. The core change is moving from "browse elements in a list, inspect properties" to "select elements visually on the screenshot, act on them with explicit buttons." The interaction model mirrors VoiceOver: click to select, double-click to activate, buttons for everything else.

---

## Phase 1: Layout Restructure — Screenshot + Action Panel

### Overview
Replace the three-pane inspector layout with a two-zone layout: screenshot view (primary) and action panel (secondary). Device picker moves to a toolbar. Element list and property inspector panels are removed.

### Changes Required:

#### 1. ContentView.swift — Complete Rewrite
**File**: `Stakeout/Sources/Views/ContentView.swift`

Replace the `NavigationSplitView` + `HStack` three-pane layout with a vertical split: screenshot on top/left, action panel on bottom/right.

```swift
struct ContentView: View {
    @StateObject private var client = HeistClient()
    @State private var selectedDevice: DiscoveredDevice?
    @State private var selectedElement: UIElement?
    @State private var hoveredElement: UIElement?
    @State private var showOverlay = false

    var body: some View {
        Group {
            switch client.connectionState {
            case .connected:
                remoteView
            case .connecting:
                ProgressView("Connecting...")
            case .failed(let error):
                errorView(error)
            case .disconnected:
                disconnectedView
            }
        }
        .toolbar { toolbarContent }
        .onAppear { client.startDiscovery() }
    }

    var remoteView: some View {
        HSplitView {
            // Left: Screenshot (primary, takes most space)
            RemoteScreenView(
                screenPayload: client.currentScreen,
                elements: client.currentInterface?.elements ?? [],
                selectedElement: $selectedElement,
                hoveredElement: $hoveredElement,
                showOverlay: showOverlay,
                onActivate: { element in activateElement(element) }
            )
            .frame(minWidth: 300)

            // Right: Action panel
            ActionPanelView(
                selectedElement: selectedElement,
                client: client
            )
            .frame(width: 260)
        }
    }
}
```

**Toolbar content:**
- Left: Device picker dropdown (Menu or Picker showing `client.discoveredDevices`)
- Center: Connected app name + device name
- Right: Overlay toggle button, connection status indicator

#### 2. StakeoutApp.swift — Window Adjustments
**File**: `Stakeout/Sources/StakeoutApp.swift`

- Adjust default window size to ~900x700 (landscape to accommodate screenshot + action panel side-by-side)
- Add `.windowToolbarStyle(.unified)` for compact toolbar

#### 3. Remove Inspector and List Views (Defer Deletion)
For this phase, simply stop referencing these views from ContentView. We'll clean them up in Phase 4. Files affected:
- `HierarchyTreeView.swift` — no longer imported/used
- `HierarchyListView.swift` — no longer imported/used
- `ElementInspectorView.swift` — no longer imported/used

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`
- [ ] App launches and shows toolbar with device picker
- [ ] Screenshot takes primary space with action panel to the right
- [ ] No element list or property inspector visible

---

## Phase 2: Selection + Action Panel — Core Interaction

### Overview
Build the select-then-act interaction model. Click on the screenshot selects an element. Double-click activates. The action panel shows explicit buttons for all available actions on the selected element.

### Changes Required:

#### 1. New View: RemoteScreenView
**File**: `Stakeout/Sources/Views/RemoteScreenView.swift` (new file)

Replaces the current `ScreenshotView`. Core responsibilities:
- Display the screenshot at native aspect ratio, centered in available space
- **Single click** → select the element under the cursor
- **Double-click** → activate the element (send `.activate`)
- Show subtle highlight on hovered element
- Show selection highlight on selected element

**Interaction model (VoiceOver-style):**

| Mac Input | Behavior |
|---|---|
| Click | Select element under cursor (highlight it, update action panel) |
| Double-click | Activate selected element (like VoiceOver double-tap) |
| Hover | Subtle highlight on element under cursor |

**No gesture translation.** All touch gestures (swipe, long press, pinch, etc.) are triggered exclusively via action panel buttons.

```swift
struct RemoteScreenView: View {
    let screenPayload: ScreenPayload?
    let elements: [UIElement]
    @Binding var selectedElement: UIElement?
    @Binding var hoveredElement: UIElement?
    let showOverlay: Bool
    let onActivate: (UIElement) -> Void

    @State private var showingActionFeedback = false

    var body: some View {
        ZStack {
            if let payload = screenPayload, let image = decodeScreen(payload) {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            ElementOverlayView(
                                elements: elements,
                                selectedElement: selectedElement,
                                hoveredElement: hoveredElement,
                                imageSize: CGSize(width: payload.width, height: payload.height),
                                viewSize: geo.size,
                                showAllElements: showOverlay,
                                onElementClicked: { element in
                                    selectedElement = element
                                },
                                onElementDoubleClicked: { element in
                                    selectedElement = element
                                    onActivate(element)
                                }
                            )
                        }
                        .onContinuousHover { phase in
                            // Update hovered element for highlight
                        }
                }
            } else {
                ContentUnavailableView("No Screenshot",
                    systemImage: "rectangle.dashed",
                    description: Text("Waiting for screen capture..."))
            }
        }
    }
}
```

**Coordinate translation:**
Reuse the existing scaling logic from `ElementOverlayView` — convert view coordinates to screenshot coordinates by dividing by `viewSize.width / imageSize.width`.

#### 2. New View: ActionPanelView
**File**: `Stakeout/Sources/Views/ActionPanelView.swift` (new file)

The action panel is the primary control surface. It shows buttons for all available actions. Layout is a vertical stack of grouped action sections.

```swift
struct ActionPanelView: View {
    let selectedElement: UIElement?
    @ObservedObject var client: HeistClient
    @State private var typeTextInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Selected element info header
                selectedElementHeader

                Divider()

                // Element-specific actions (from element's actions array)
                if let element = selectedElement {
                    elementActionsSection(element)
                }

                Divider()

                // Touch gesture buttons (always available when element selected)
                if selectedElement != nil {
                    touchGesturesSection
                    Divider()
                    textInputSection
                    Divider()
                    advancedGesturesSection
                }
            }
            .padding()
        }
        .background(.background)
    }
}
```

**Section 1: Selected Element Header**
Shows the selected element's key info:
- Label or description (primary text)
- Identifier (monospaced, secondary)
- Frame coordinates (tertiary)
- "No element selected" placeholder when nothing is selected

**Section 2: Element Actions** (dynamic, based on selected element's `actions` array)
Buttons that appear only when the selected element supports them:
- **Activate** button — sends `.activate(target)` — shown if `.activate` in actions
- **Increment** button — sends `.increment(target)` — shown if `.increment` in actions
- **Decrement** button — sends `.decrement(target)` — shown if `.decrement` in actions
- **Custom actions** — one button per custom action name — sends `.performCustomAction(...)` for each

```swift
func elementActionsSection(_ element: UIElement) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("ELEMENT ACTIONS").font(.caption).foregroundStyle(.secondary)

        if element.actions.contains(.activate) {
            Button("Activate") {
                client.send(.activate(actionTarget(for: element)))
            }
            .keyboardShortcut(.return)
        }
        if element.actions.contains(.increment) {
            HStack {
                Button("Decrement") {
                    client.send(.decrement(actionTarget(for: element)))
                }
                Button("Increment") {
                    client.send(.increment(actionTarget(for: element)))
                }
            }
        }
        for case .custom(let name) in element.actions {
            Button(name) {
                client.send(.performCustomAction(
                    CustomActionTarget(elementTarget: actionTarget(for: element), actionName: name)
                ))
            }
        }
    }
}
```

**Section 3: Touch Gestures** (applied to selected element's center point)
Always-visible buttons when an element is selected:
- **Tap** — sends `.touchTap` at element's center coordinates
- **Long Press** — sends `.touchLongPress` at element's center coordinates
- **Swipe** — 4 directional buttons (Up/Down/Left/Right) in a cross layout, sends `.touchSwipe` from element center in the chosen direction

```swift
var touchGesturesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("TOUCH GESTURES").font(.caption).foregroundStyle(.secondary)

        HStack {
            Button { sendTap() } label: {
                Label("Tap", systemImage: "hand.tap")
            }
            Button { sendLongPress() } label: {
                Label("Long Press", systemImage: "hand.tap.fill")
            }
        }

        // Swipe direction cross
        VStack(spacing: 4) {
            Button { sendSwipe(.up) } label: {
                Image(systemName: "chevron.up")
            }
            HStack(spacing: 4) {
                Button { sendSwipe(.left) } label: {
                    Image(systemName: "chevron.left")
                }
                // Center label
                Text("Swipe").font(.caption2)
                Button { sendSwipe(.right) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            Button { sendSwipe(.down) } label: {
                Image(systemName: "chevron.down")
            }
        }
    }
}
```

**Section 4: Text Input**
A text field + send button for typing text into focused fields:
- Text field bound to `typeTextInput`
- "Type" button sends `.typeText(TypeTextTarget(text: typeTextInput, elementTarget: ...))`
- "Delete" button sends `.typeText(TypeTextTarget(deleteCount: 1, elementTarget: ...))`
- Clears input after sending

**Section 5: Advanced Gestures** (collapsible, less commonly used)
- **Pinch In** / **Pinch Out** — sends `.touchPinch` at element center with scale <1.0 / >1.0
- **Rotate CW** / **Rotate CCW** — sends `.touchRotate` at element center
- **Two-Finger Tap** — sends `.touchTwoFingerTap` at element center

#### 3. Update ElementOverlayView — Three-State Highlighting
**File**: `Stakeout/Sources/Views/ElementOverlayView.swift` (modify existing)

Update to support three visual states:
- **Default**: Very subtle borders (when `showAllElements` is on), invisible otherwise
- **Hovered**: Slightly brighter border + faint fill (when mouse is over element)
- **Selected**: Prominent border (accent color) + light fill (when element is clicked/selected)

Add `hoveredElement` and `showAllElements` parameters alongside existing `selectedElement`.

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`
- [x] All existing tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test`

#### Manual Verification (requires device):
- [ ] Click on screenshot selects element (highlights it, shows info in action panel)
- [ ] Double-click on element activates it on iOS device
- [ ] "Tap" button sends tap to selected element
- [ ] Swipe direction buttons send swipe from selected element
- [ ] "Activate" button appears only for activatable elements
- [ ] "Increment"/"Decrement" buttons appear only for adjustable elements
- [ ] Text input field + "Type" button sends text to device
- [ ] "Long Press" button sends long press to selected element

---

## Phase 3: Hover Feedback + Element Overlay

### Overview
Add hover highlighting so users can see what they're about to select before clicking. Add the element overlay toggle for showing all element boundaries.

### Changes Required:

#### 1. Hover Tracking in RemoteScreenView
Add `onContinuousHover` to the overlay to track mouse position and find the element under the cursor:

```swift
.onContinuousHover { phase in
    switch phase {
    case .active(let location):
        hoveredElement = elementAt(point: location, in: elements)
    case .ended:
        hoveredElement = nil
    }
}
```

The `hoveredElement` is passed to `ElementOverlayView` which renders a subtle highlight (thin border + faint fill) around it, distinct from the selected element's more prominent highlight.

#### 2. Element Tooltip on Hover
When hovering over an element, show a small tooltip with:
- Element label or description (1 line)

Use the `.help()` modifier on the overlay, updating its value as `hoveredElement` changes. Keep it minimal — just enough context to know what you're about to select.

#### 3. Element Overlay Toggle
The `showOverlay` toggle in the toolbar draws subtle borders around all elements:
- Thin (0.5pt) borders in a neutral color (gray at 30% opacity)
- No fill by default
- Hovered element gets slightly brighter border
- Selected element gets accent color border
- Off by default

This is the simplified version of the current `ElementOverlayView` canvas — same hit-testing and drawing logic, but with muted styling when `showAllElements` is false (only hovered and selected elements are visible).

#### 4. Right-Click Context Menu (Quick Access)
Even though the action panel has all buttons, add a right-click context menu as a convenience shortcut for common actions:

```swift
.contextMenu {
    if let element = hoveredElement ?? selectedElement {
        Text(element.label ?? element.description).font(.headline)
        Divider()
        Button("Activate") { client.send(.activate(actionTarget(for: element))) }
        Button("Copy Identifier") {
            NSPasteboard.general.setString(element.identifier ?? "", forType: .string)
        }
        .disabled(element.identifier == nil)
    }
}
```

Keep this minimal — just Activate and Copy Identifier. Full action set lives in the action panel.

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`

#### Manual Verification (requires device):
- [ ] Hovering over an element shows subtle highlight
- [ ] Moving mouse away removes hover highlight
- [ ] Clicking selects the element (different highlight style than hover)
- [ ] Overlay toggle shows/hides all element boundaries
- [ ] Right-click shows quick context menu with Activate and Copy Identifier

---

## Phase 4: Feedback, Connection States + Polish

### Overview
Add visual feedback for actions, improve connection states, handle action results, and clean up removed code.

### Changes Required:

#### 1. Action Result Feedback
Subscribe to `client.onActionResult` to show feedback in the action panel:
- **Success**: Brief green checkmark flash next to the button that was pressed
- **Failure**: Error message displayed in the action panel header area (red text, auto-dismiss after 3s)
- For `typeText` results: show the returned `value` field in the text input section (confirms what was typed)

Additionally, show a brief visual flash on the screenshot overlay at the element's position:
- **Tap/Activate**: Small yellow circle fade (reuse existing `showingActionFeedback` pattern from `ScreenshotView`)
- **Swipe**: Brief directional arrow indicator

#### 2. Connection State Views
Improve the non-connected states:
- **Disconnected**: Show device picker prominently in center with "Select a device to connect" message and a list of discovered devices (not just toolbar)
- **Connecting**: Centered spinner with device name
- **Failed**: Error message with retry button

#### 3. Keyboard Shortcuts
- `Cmd+R`: Refresh interface (requestInterface + requestScreen)
- `Cmd+Shift+O`: Toggle overlay
- `Escape`: Deselect current element
- `Return`: Activate selected element (already handled via `.keyboardShortcut(.return)` on Activate button)

#### 4. Clean Up Removed Views
Delete files no longer used:
- `HierarchyTreeView.swift`
- `HierarchyListView.swift`
- `ElementInspectorView.swift`
- `ScreenshotView.swift` (replaced by `RemoteScreenView`)
- Remove unused design tokens from `ElementStyling.swift`, `Colors.swift`, `Typography.swift`, `Spacing.swift`

#### 5. Update Window Configuration
In `StakeoutApp.swift`:
- Default size to ~900x700 (landscape, accommodating screenshot + action panel)
- Title bar: show connected app name, or "Stakeout" when disconnected

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme Stakeout build`
- [x] All tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test`
- [x] No references to deleted files in remaining code
- [x] No compiler warnings related to unused imports

#### Manual Verification (requires device):
- [ ] Activate action shows yellow flash on element
- [ ] Failed action shows error message in action panel
- [ ] Disconnected state shows device list prominently
- [ ] Keyboard shortcuts work (Cmd+R refreshes, Escape deselects)

---

## Testing Strategy

### Automated Tests:
- Build verification for Stakeout scheme
- Existing unit tests for TheGoods, Wheelman, ButtonHeist (no changes needed)
- Coordinate translation logic (view→device point conversion) — add unit tests if extracted to a testable helper

### Integration Tests (CLI-driven):
- Boot simulator → install test app → connect Stakeout → verify screenshot appears
- Send CLI touch commands in parallel to verify they don't conflict with GUI interactions

### Manual Testing:
1. Connect to simulator app, select elements by clicking screenshot
2. Use action panel buttons to tap, swipe, long press, type text
3. Verify increment/decrement buttons work on sliders
4. Toggle overlay on/off
5. Use right-click context menu for quick activate
6. Disconnect and reconnect

## Performance Considerations

- **Screenshot decoding**: Currently decodes base64 PNG on every frame. Consider caching the decoded `NSImage` and only re-decoding when `ScreenPayload.timestamp` changes. This is already partially handled by SwiftUI's diffing but worth watching.
- **Hover hit testing**: `elementAt()` iterates all elements in reverse. For apps with many elements (100+), consider spatial indexing. For now, linear scan is fine given typical element counts.
- **Action panel reactivity**: The action panel must update immediately when `selectedElement` changes. Since it's driven by SwiftUI bindings this should be automatic, but test with rapid selection changes.

## References

- Current views: `Stakeout/Sources/Views/`
- Wire protocol: `ButtonHeist/Sources/TheGoods/Messages.swift`
- Client API: `ButtonHeist/Sources/ButtonHeist/HeistClient.swift`
- Architecture docs: `docs/ARCHITECTURE.md`
- Wire protocol docs: `docs/WIRE-PROTOCOL.md`

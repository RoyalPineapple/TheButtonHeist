# AccraInspector Visual Mode Implementation Plan

## Overview

Enhance the AccraInspector Mac app to display live screenshots from connected iOS devices with interactive element overlays. Users can visualize the accessibility tree spatially, select elements by clicking on the screenshot, and activate elements via double-click.

## Current State Analysis

**What exists:**
- AccraInspector displays device sidebar, element list with search, and element detail panel
- AccraClient already receives screenshots via `@Published currentScreenshot: ScreenshotPayload?`
- AccraClient can send actions via `send(.activate(ActionTarget))`
- Element data includes frame coordinates and activation points

**What's missing:**
- No screenshot display in the UI
- No visual overlay of element boundaries
- No interactive element selection on screenshot
- No action buttons to activate elements

### Key Discoveries:
- `ScreenshotPayload.pngData` is base64-encoded PNG (`Messages.swift:131`)
- `AccessibilityElementData` has `frameX/Y/Width/Height` for bounding boxes (`Messages.swift:208-211`)
- `AccessibilityElementData.traits` is `[String]` for trait-based coloring (`Messages.swift:205`)
- AccraClient is `@MainActor` and `ObservableObject` for SwiftUI binding (`AccraClient.swift:27-28`)

## Desired End State

After implementation:
1. When connected to a device, the right panel shows a live screenshot
2. All accessibility elements are outlined on the screenshot with trait-based colors
3. Clicking an element in the list highlights it on the screenshot
4. Clicking an element on the screenshot selects it in the list and shows details
5. Double-clicking an element on the screenshot activates it
6. An "Activate" button in the element detail allows activation from the list

### Verification:
- Connect to TestApp, see screenshot with element overlays
- Click "Test Button" on screenshot, verify it's selected in list
- Double-click "Test Button" on screenshot, verify tap count increments
- Click "Activate" button, verify action is sent

## What We're NOT Doing

- Zoom/pan functionality (fit-to-view only for now)
- Screenshot recording/history
- Element drag-and-drop reordering
- Custom action support (only activate for now)
- Adjustable element increment/decrement buttons (future enhancement)

## Implementation Approach

Replace the current `ElementDetailView` with a new `ScreenshotView` that shows the device screenshot with element overlays. The element list remains on the left. Selection state syncs between list and screenshot. Double-click on screenshot triggers activation.

---

## Phase 1: Screenshot Display

### Overview
Add a view that decodes and displays the base64 PNG screenshot from AccraClient.

### Changes Required:

#### 1. Create ScreenshotView
**File**: `AccraInspector/Sources/Views/ScreenshotView.swift` (new)
**Changes**: New file with screenshot decoding and display

```swift
import SwiftUI
import AppKit
import AccraCore

struct ScreenshotView: View {
    let screenshotPayload: ScreenshotPayload?

    var body: some View {
        GeometryReader { geometry in
            if let payload = screenshotPayload,
               let image = decodeScreenshot(payload) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            } else {
                ContentUnavailableView(
                    "No Screenshot",
                    systemImage: "photo",
                    description: Text("Waiting for screenshot from device...")
                )
            }
        }
    }

    private func decodeScreenshot(_ payload: ScreenshotPayload) -> NSImage? {
        guard let data = Data(base64Encoded: payload.pngData) else { return nil }
        return NSImage(data: data)
    }
}
```

#### 2. Update ContentView to show screenshot
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Replace ElementDetailView with ScreenshotView in detail pane

Update the `detailView` computed property to show screenshot:

```swift
@ViewBuilder
private var detailView: some View {
    switch client.connectionState {
    case .connected:
        if let hierarchy = client.currentHierarchy {
            HSplitView {
                HierarchyListView(
                    elements: hierarchy.elements,
                    selectedElement: $selectedElement
                )
                .frame(minWidth: 300)

                ScreenshotView(screenshotPayload: client.currentScreenshot)
                    .frame(minWidth: 400)
            }
        } else {
            ProgressView("Loading hierarchy...")
        }
    // ... other cases unchanged
    }
}
```

#### 3. Add selectedElement state to ContentView
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Add state for selected element

```swift
@State private var selectedElement: AccessibilityElementData?
```

#### 4. Update HierarchyListView to accept binding
**File**: `AccraInspector/Sources/Views/HierarchyListView.swift`
**Changes**: Change selectedElement from internal @State to @Binding

```swift
struct HierarchyListView: View {
    let elements: [AccessibilityElementData]
    @Binding var selectedElement: AccessibilityElementData?
    @State private var searchQuery = ""
    // ... rest unchanged
}
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector -destination 'platform=macOS'`

#### Manual Verification:
- [ ] Connect to TestApp, screenshot appears in right panel
- [ ] Screenshot scales to fit available space
- [ ] "No Screenshot" placeholder shows when disconnected
- [ ] Element list still works with search

---

## Phase 2: Element Overlay

### Overview
Draw colored bounding boxes on the screenshot for each accessibility element, with trait-based coloring.

### Changes Required:

#### 1. Create ElementOverlayView
**File**: `AccraInspector/Sources/Views/ElementOverlayView.swift` (new)
**Changes**: New view that draws element rectangles on top of screenshot

```swift
import SwiftUI
import AccraCore

struct ElementOverlayView: View {
    let elements: [AccessibilityElementData]
    let selectedElement: AccessibilityElementData?
    let imageSize: CGSize      // Original screenshot dimensions
    let viewSize: CGSize       // Current view dimensions
    let onElementTapped: (AccessibilityElementData) -> Void
    let onElementDoubleTapped: (AccessibilityElementData) -> Void

    var body: some View {
        ZStack {
            ForEach(elements, id: \.traversalIndex) { element in
                ElementRectangle(
                    element: element,
                    isSelected: selectedElement?.traversalIndex == element.traversalIndex,
                    scale: scale,
                    offset: offset
                )
                .onTapGesture {
                    onElementTapped(element)
                }
                .onTapGesture(count: 2) {
                    onElementDoubleTapped(element)
                }
            }
        }
    }

    private var scale: CGFloat {
        min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
    }

    private var offset: CGPoint {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        return CGPoint(
            x: (viewSize.width - scaledWidth) / 2,
            y: (viewSize.height - scaledHeight) / 2
        )
    }
}

struct ElementRectangle: View {
    let element: AccessibilityElementData
    let isSelected: Bool
    let scale: CGFloat
    let offset: CGPoint

    var body: some View {
        Rectangle()
            .strokeBorder(strokeColor, lineWidth: isSelected ? 3 : 1)
            .background(fillColor.opacity(isSelected ? 0.3 : 0.1))
            .frame(width: element.frameWidth * scale, height: element.frameHeight * scale)
            .position(
                x: offset.x + (element.frameX + element.frameWidth / 2) * scale,
                y: offset.y + (element.frameY + element.frameHeight / 2) * scale
            )
    }

    private var strokeColor: Color {
        if isSelected { return .yellow }
        return traitColor
    }

    private var fillColor: Color {
        if isSelected { return .yellow }
        return traitColor
    }

    private var traitColor: Color {
        let traits = element.traits
        if traits.contains("button") { return .blue }
        if traits.contains("link") { return .purple }
        if traits.contains("textField") || traits.contains("searchField") { return .green }
        if traits.contains("adjustable") { return .orange }
        if traits.contains("staticText") { return .gray }
        if traits.contains("image") { return .pink }
        if traits.contains("header") { return .red }
        return .cyan
    }
}
```

#### 2. Update ScreenshotView to include overlay
**File**: `AccraInspector/Sources/Views/ScreenshotView.swift`
**Changes**: Add overlay layer on top of screenshot image

```swift
struct ScreenshotView: View {
    let screenshotPayload: ScreenshotPayload?
    let elements: [AccessibilityElementData]
    @Binding var selectedElement: AccessibilityElementData?
    let onActivate: (AccessibilityElementData) -> Void

    var body: some View {
        GeometryReader { geometry in
            if let payload = screenshotPayload,
               let image = decodeScreenshot(payload) {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    ElementOverlayView(
                        elements: elements,
                        selectedElement: selectedElement,
                        imageSize: CGSize(width: payload.width, height: payload.height),
                        viewSize: geometry.size,
                        onElementTapped: { element in
                            selectedElement = element
                        },
                        onElementDoubleTapped: { element in
                            selectedElement = element
                            onActivate(element)
                        }
                    )
                }
                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            } else {
                ContentUnavailableView(
                    "No Screenshot",
                    systemImage: "photo",
                    description: Text("Waiting for screenshot from device...")
                )
            }
        }
    }

    private func decodeScreenshot(_ payload: ScreenshotPayload) -> NSImage? {
        guard let data = Data(base64Encoded: payload.pngData) else { return nil }
        return NSImage(data: data)
    }
}
```

#### 3. Update ContentView to pass elements and callbacks
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Pass hierarchy elements and activation callback to ScreenshotView

```swift
ScreenshotView(
    screenshotPayload: client.currentScreenshot,
    elements: hierarchy.elements,
    selectedElement: $selectedElement,
    onActivate: { element in
        activateElement(element)
    }
)

// Add helper method:
private func activateElement(_ element: AccessibilityElementData) {
    let target = ActionTarget(
        identifier: element.identifier,
        traversalIndex: element.traversalIndex
    )
    client.send(.activate(target))
}
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector -destination 'platform=macOS'`

#### Manual Verification:
- [ ] All elements have colored overlays on screenshot
- [ ] Buttons are blue, text fields green, sliders orange, etc.
- [ ] Selected element has yellow highlight with thicker border
- [ ] Click on element overlay selects it
- [ ] Double-click on element activates it (tap count increments)

---

## Phase 3: Selection Sync & Element Detail

### Overview
Sync selection between list and screenshot. Show element details in a collapsible inspector panel.

### Changes Required:

#### 1. Update HierarchyListView to sync selection
**File**: `AccraInspector/Sources/Views/HierarchyListView.swift`
**Changes**: Use List selection binding instead of internal state

```swift
struct HierarchyListView: View {
    let elements: [AccessibilityElementData]
    @Binding var selectedElement: AccessibilityElementData?
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(query: $searchQuery)
                .padding(TreeSpacing.unit)

            Divider()

            if filteredElements.isEmpty && !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                List(filteredElements, id: \.traversalIndex, selection: $selectedElement) { element in
                    ElementRowView(element: element)
                        .tag(element)
                }
            }
        }
    }

    // ... filteredElements unchanged
}
```

#### 2. Add Element Detail Inspector
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Add inspector panel that shows when element is selected

```swift
@ViewBuilder
private var detailView: some View {
    switch client.connectionState {
    case .connected:
        if let hierarchy = client.currentHierarchy {
            HSplitView {
                HierarchyListView(
                    elements: hierarchy.elements,
                    selectedElement: $selectedElement
                )
                .frame(minWidth: 250, maxWidth: 350)

                ScreenshotView(
                    screenshotPayload: client.currentScreenshot,
                    elements: hierarchy.elements,
                    selectedElement: $selectedElement,
                    onActivate: { element in
                        activateElement(element)
                    }
                )
                .frame(minWidth: 400)
            }
            .inspector(isPresented: .constant(selectedElement != nil)) {
                if let element = selectedElement {
                    ElementInspectorView(
                        element: element,
                        onActivate: { activateElement(element) }
                    )
                    .inspectorColumnWidth(min: 200, ideal: 250, max: 300)
                }
            }
        } else {
            ProgressView("Loading hierarchy...")
        }
    // ... other cases
    }
}
```

#### 3. Create ElementInspectorView
**File**: `AccraInspector/Sources/Views/ElementInspectorView.swift` (new)
**Changes**: New view for element details with Activate button

```swift
import SwiftUI
import AccraCore

struct ElementInspectorView: View {
    let element: AccessibilityElementData
    let onActivate: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with Activate button
                HStack {
                    Text("Element Details")
                        .font(.headline)
                    Spacer()
                    Button("Activate") {
                        onActivate()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                DetailSection(title: "Description") {
                    Text(element.description)
                        .textSelection(.enabled)
                }

                if let label = element.label {
                    DetailSection(title: "Label") {
                        Text(label)
                    }
                }

                if let value = element.value, !value.isEmpty {
                    DetailSection(title: "Value") {
                        Text(value)
                    }
                }

                if let hint = element.hint, !hint.isEmpty {
                    DetailSection(title: "Hint") {
                        Text(hint)
                    }
                }

                if !element.traits.isEmpty {
                    DetailSection(title: "Traits") {
                        Text(element.traits.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                DetailSection(title: "Frame") {
                    Text("(\(Int(element.frameX)), \(Int(element.frameY))) \(Int(element.frameWidth))×\(Int(element.frameHeight))")
                        .font(.system(.body, design: .monospaced))
                }

                DetailSection(title: "Activation Point") {
                    Text("(\(Int(element.activationPointX)), \(Int(element.activationPointY)))")
                        .font(.system(.body, design: .monospaced))
                }

                if let identifier = element.identifier, !identifier.isEmpty {
                    DetailSection(title: "Identifier") {
                        Text(identifier)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !element.customActions.isEmpty {
                    DetailSection(title: "Custom Actions") {
                        Text(element.customActions.joined(separator: ", "))
                    }
                }
            }
            .padding()
        }
    }
}

// Reuse DetailSection from HierarchyListView or extract to shared file
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector -destination 'platform=macOS'`

#### Manual Verification:
- [ ] Clicking element in list highlights it on screenshot
- [ ] Clicking element on screenshot selects it in list
- [ ] Inspector panel shows element details when selected
- [ ] "Activate" button in inspector triggers action
- [ ] Double-click on screenshot activates element

---

## Phase 4: Polish & Refinements

### Overview
Add visual polish, loading states, and connection status indicators.

### Changes Required:

#### 1. Add connection status bar
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Add status bar showing connected device and last update time

```swift
// Add to bottom of detail view:
.safeAreaInset(edge: .bottom) {
    if let device = client.connectedDevice {
        HStack {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            Text("Connected to \(device.name)")
                .font(.caption)
            Spacer()
            if let hierarchy = client.currentHierarchy {
                Text("Updated: \(hierarchy.timestamp.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
```

#### 2. Add loading overlay for actions
**File**: `AccraInspector/Sources/Views/ScreenshotView.swift`
**Changes**: Show brief flash when action is sent

```swift
@State private var showingActionFeedback = false

// In overlay:
if showingActionFeedback {
    Color.yellow.opacity(0.3)
        .ignoresSafeArea()
        .transition(.opacity)
}

// Update onActivate to show feedback:
onElementDoubleTapped: { element in
    selectedElement = element
    withAnimation(.easeOut(duration: 0.1)) {
        showingActionFeedback = true
    }
    onActivate(element)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        withAnimation(.easeIn(duration: 0.1)) {
            showingActionFeedback = false
        }
    }
}
```

#### 3. Add keyboard shortcuts
**File**: `AccraInspector/Sources/Views/ContentView.swift`
**Changes**: Add keyboard shortcuts for common actions

```swift
.keyboardShortcut(.return, modifiers: [])  // On Activate button - activates selected element
```

### Success Criteria:

#### Automated Verification:
- [x] Build succeeds: `xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector -destination 'platform=macOS'`

#### Manual Verification:
- [ ] Status bar shows connected device name
- [ ] Status bar shows last update timestamp
- [ ] Yellow flash appears when activating element
- [ ] Enter key activates selected element

---

## Testing Strategy

### Manual Testing Steps:
1. Launch AccraInspector
2. Start TestApp in simulator
3. Verify device appears in sidebar
4. Connect to device
5. Verify screenshot appears with element overlays
6. Click various elements on screenshot, verify selection syncs to list
7. Click elements in list, verify highlight on screenshot
8. Double-click "Test Button" on screenshot, verify tap count increments
9. Select element, click "Activate" button, verify action works
10. Change slider value, verify screenshot updates automatically
11. Disconnect, verify "No Screenshot" placeholder appears

### Edge Cases:
- Connect/disconnect rapidly
- Very long element labels
- Elements with no identifier (use traversalIndex)
- Screenshot updates while selecting elements

## Performance Considerations

- Base64 decoding happens on main thread - acceptable for ~300KB screenshots
- Element overlay uses `ForEach` - should handle 50+ elements smoothly
- Consider caching decoded NSImage if performance issues arise

## References

- AccraClient screenshot support: `AccraCore/Sources/AccraClient/AccraClient.swift:36`
- ScreenshotPayload structure: `AccraCore/Sources/AccraCore/Messages.swift:129-145`
- Current HierarchyListView: `AccraInspector/Sources/Views/HierarchyListView.swift`
- ActionTarget for activation: `AccraCore/Sources/AccraCore/Messages.swift:49-59`

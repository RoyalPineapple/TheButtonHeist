# InsideMan Interface Delta Tracking

## Overview

Move hierarchy change detection from the MCP server into InsideMan itself. After each successful action, InsideMan snapshots the accessibility tree, diffs it against the pre-action state, and includes a compact `InterfaceDelta` in the `ActionResult`. This eliminates post-action polling from the MCP server and gives clients immediate, precise change information with zero extra round-trips.

## Current State Analysis

**InsideMan already snapshots before every action.** Every action handler calls `refreshAccessibilityData()` at the top to find the target element. This populates `cachedElements` — the "before" snapshot is free.

**The MCP server currently does diffing.** `main.swift` has `InterfaceDiff`, `diffInterfaces()`, `fetchInterfaceDiff()`, and `previousInterface` state. This was recently stripped from `sendAction()` because the 500ms sleep + round-trip per action was too slow.

**InsideMan has polling-based change detection.** `checkForChanges()` uses `elements.hashValue` to detect hierarchy changes and broadcasts to subscribers. But this is for background monitoring, not per-action feedback.

### Key Discoveries:
- `refreshAccessibilityData()` at `InsideMan.swift:446` already gives us the before-snapshot for free
- `cachedElements` at `InsideMan.swift:457` holds the flattened element list
- `convertElement(_:index:)` at `InsideMan.swift:1334` converts parser `AccessibilityElement` to wire `UIElement` (to be renamed `HeistElement`)
- `UIElement` at `Messages.swift:710` is currently a thin struct (order, description, label, value, identifier, frame, actions) — it drops rich accessibility data like traits, hint, activationPoint, customContent, and respondsToUserInteraction
- `AccessibilityElement` (from AccessibilitySnapshot parser) has the full picture: traits, hint, customActions, customContent, customRotors, activationPoint, userInputLabels, accessibilityLanguage, respondsToUserInteraction
- `ActionResult` at `Messages.swift:408-421` has 4 fields: `success`, `method`, `message`, `value`
- `UIElement` conforms to `Equatable` and `Hashable` — we can use hash comparison for quick change detection
- Sync handlers (activate, increment, decrement, tap) are directly on MainActor
- Async handlers (longPress, swipe, drag, pinch, etc.) wrap in `Task { @MainActor in }`

## Desired End State

After every successful action, `ActionResult` includes an optional `interfaceDelta` field:
- `nil` when the action failed
- `.noChange` when the hierarchy didn't change (e.g., save button)
- Compact diff when specific elements changed (e.g., slider value, toggle state)
- Full new interface when the screen changed entirely (e.g., navigation push)

The MCP server reads the delta from ActionResult and passes it through. No polling, no sleeping, no extra interface fetches.

### Verification:
1. Build all targets: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build && xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build && swift build -c release -C ButtonHeistMCP`
2. Run tests: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test`
3. Install test app on simulator, tap a button, verify ActionResult contains delta
4. Tap a button that doesn't change anything, verify delta shows `noChange`
5. Navigate to a new screen, verify delta shows `screenChanged` with full interface

## What We're NOT Doing

- No changes to the polling/subscription system — that stays for background monitoring
- No changes to `get_interface` — it still returns the full hierarchy
- No tree structure in deltas — flat element diffs only (tree is optional and expensive)
- No frame-change tracking — only tracking value/label/element-count changes for now
- No animation settle detection — using a single 100ms runloop yield

## Implementation Approach

The action already refreshes the hierarchy to find the target element. After the action succeeds, we yield briefly to let the UI update, refresh again, and diff. The diff is cheap (hash comparison first, then element-level comparison if needed).

---

## Phase 1: Wire Protocol Types — HeistElement + InterfaceDelta

### Overview
Rename `UIElement` → `HeistElement`, enrich it with fields from the parser's `AccessibilityElement`, add `InterfaceDelta` and supporting types to TheGoods, and extend `ActionResult` with an optional delta field.

### Changes Required:

#### 1. TheGoods/Messages.swift — Rename UIElement → HeistElement and add richer fields

**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Replace the current `UIElement` struct (~line 710) with `HeistElement`. The new type wraps the same data the parser's `AccessibilityElement` provides, serialized into wire-friendly primitives:

```swift
// MARK: - Heist Element

/// A UI element captured from the accessibility hierarchy.
/// Wraps the parser's AccessibilityElement with all its rich data in a wire-friendly form.
public struct HeistElement: Codable, Equatable, Hashable, Sendable {
    /// Element order in the snapshot (0-based)
    public var order: Int
    /// Human-readable description of the element
    public var description: String
    public var label: String?
    public var value: String?
    public var identifier: String?
    /// Accessibility hint (read by VoiceOver after the description)
    public var hint: String?
    /// Accessibility traits as human-readable strings (e.g. ["button", "adjustable"])
    public var traits: [String]
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double
    /// Activation point X coordinate (where VoiceOver would tap)
    public var activationPointX: Double
    /// Activation point Y coordinate
    public var activationPointY: Double
    /// Whether the element responds to user interaction
    public var respondsToUserInteraction: Bool
    /// Custom content label/value pairs provided by the element
    public var customContent: [HeistCustomContent]?
    /// Available actions for this element
    public var actions: [ElementAction]

    public init(
        order: Int,
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String?,
        traits: [String],
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        activationPointX: Double,
        activationPointY: Double,
        respondsToUserInteraction: Bool,
        customContent: [HeistCustomContent]?,
        actions: [ElementAction]
    ) {
        self.order = order
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.activationPointX = activationPointX
        self.activationPointY = activationPointY
        self.respondsToUserInteraction = respondsToUserInteraction
        self.customContent = customContent
        self.actions = actions
    }
}

/// Custom content attached to a HeistElement (maps to AccessibilityElement.CustomContent)
public struct HeistCustomContent: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var value: String
    public var isImportant: Bool

    public init(label: String, value: String, isImportant: Bool) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }
}

// MARK: - Convenience Extensions

extension HeistElement {
    /// Computed frame as CGRect
    public var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    }

    /// Computed activation point as CGPoint
    public var activationPoint: CGPoint {
        CGPoint(x: activationPointX, y: activationPointY)
    }
}
```

**New fields vs current UIElement:**

| Field | Source in AccessibilityElement | Why |
|---|---|---|
| `hint` | `.hint` | Describes what activating the element does — critical for fuzzer understanding |
| `traits` | `.traits` (UIAccessibilityTraits → string array) | Distinguishes buttons/links/headers/adjustables — core element classification |
| `activationPointX/Y` | `.activationPoint` | Precise tap target (differs from frame center for sliders, etc.) |
| `respondsToUserInteraction` | `.respondsToUserInteraction` | Filters interactive vs decorative elements — saves fuzzer time |
| `customContent` | `.customContent` | AXCustomContent label/value pairs — semantic data beyond label/value |

**Fields intentionally NOT included:**
- `customRotors` — complex nested type, rarely useful over the wire
- `userInputLabels` — Voice Control labels, not needed for automation
- `accessibilityLanguage` — localization metadata, not actionable
- `shape.path` — UIBezierPath can't serialize; frame is sufficient

#### 2. TheGoods/Messages.swift — Update Interface to use HeistElement

**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Update `Interface` (~line 651) to use `HeistElement`:

```swift
public struct Interface: Codable, Sendable {
    public let timestamp: Date
    public let elements: [HeistElement]
    public let tree: [ElementNode]?

    public init(timestamp: Date, elements: [HeistElement], tree: [ElementNode]? = nil) {
        self.timestamp = timestamp
        self.elements = elements
        self.tree = tree
    }
}
```

#### 3. TheGoods/Messages.swift — Add InterfaceDelta types

**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add after the `ActionResult` struct (~line 421):

```swift
// MARK: - Interface Delta

/// Compact description of what changed in the accessibility hierarchy after an action.
public struct InterfaceDelta: Codable, Sendable {
    /// What kind of change occurred
    public let kind: DeltaKind

    /// Total element count after the action
    public let elementCount: Int

    /// Elements that were added (present for .elementsChanged)
    public let added: [HeistElement]?

    /// Orders of elements that were removed (present for .elementsChanged)
    public let removedOrders: [Int]?

    /// Value changes on existing elements (present for .valuesChanged or .elementsChanged)
    public let valueChanges: [ValueChange]?

    /// Full new interface (present only for .screenChanged)
    public let newInterface: Interface?

    public init(
        kind: DeltaKind,
        elementCount: Int,
        added: [HeistElement]? = nil,
        removedOrders: [Int]? = nil,
        valueChanges: [ValueChange]? = nil,
        newInterface: Interface? = nil
    ) {
        self.kind = kind
        self.elementCount = elementCount
        self.added = added
        self.removedOrders = removedOrders
        self.valueChanges = valueChanges
        self.newInterface = newInterface
    }

    public enum DeltaKind: String, Codable, Sendable {
        case noChange
        case valuesChanged
        case elementsChanged
        case screenChanged
    }
}

/// A single value change on an element
public struct ValueChange: Codable, Sendable {
    public let order: Int
    public let identifier: String?
    public let oldValue: String?
    public let newValue: String?

    public init(order: Int, identifier: String?, oldValue: String?, newValue: String?) {
        self.order = order
        self.identifier = identifier
        self.oldValue = oldValue
        self.newValue = newValue
    }
}
```

#### 4. TheGoods/Messages.swift — Extend ActionResult

**File**: `ButtonHeist/Sources/TheGoods/Messages.swift`

Add `interfaceDelta` field to `ActionResult`:

```swift
public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let method: ActionMethod
    public let message: String?
    public let value: String?
    public let interfaceDelta: InterfaceDelta?

    public init(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        interfaceDelta: InterfaceDelta? = nil
    ) {
        self.success = success
        self.method = method
        self.message = message
        self.value = value
        self.interfaceDelta = interfaceDelta
    }
}
```

Since the new field is optional and `Codable`, existing JSON without it will decode as `nil` — fully backwards-compatible.

### Success Criteria:

#### Automated Verification:
- [x] TheGoods builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build`
- [x] Existing tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test` (54/54 passed)

---

## Phase 2: InsideMan — HeistElement Conversion + Diffing Engine

### Overview
Update `convertElement()` to produce `HeistElement` with the richer field set, add diffing logic to InsideMan, and wire up delta computation to action handlers.

### Changes Required:

#### 1. InsideMan.swift — Update convertElement to produce HeistElement

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Update `convertElement(_:index:)` at line 1334 to populate the new fields:

```swift
private func convertElement(_ element: AccessibilityElement, index: Int) -> HeistElement {
    let frame = element.shape.frame
    return HeistElement(
        order: index,
        description: element.description,
        label: element.label,
        value: element.value,
        identifier: element.identifier,
        hint: element.hint,
        traits: traitNames(element.traits),
        frameX: frame.origin.x,
        frameY: frame.origin.y,
        frameWidth: frame.size.width,
        frameHeight: frame.size.height,
        activationPointX: element.activationPoint.x,
        activationPointY: element.activationPoint.y,
        respondsToUserInteraction: element.respondsToUserInteraction,
        customContent: element.customContent.isEmpty ? nil : element.customContent.map {
            HeistCustomContent(label: $0.label, value: $0.value, isImportant: $0.isImportant)
        },
        actions: buildActions(for: index, element: element)
    )
}

/// Convert UIAccessibilityTraits bitmask to human-readable string array.
private func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
    var names: [String] = []
    if traits.contains(.button) { names.append("button") }
    if traits.contains(.link) { names.append("link") }
    if traits.contains(.image) { names.append("image") }
    if traits.contains(.staticText) { names.append("staticText") }
    if traits.contains(.header) { names.append("header") }
    if traits.contains(.adjustable) { names.append("adjustable") }
    if traits.contains(.searchField) { names.append("searchField") }
    if traits.contains(.selected) { names.append("selected") }
    if traits.contains(.notEnabled) { names.append("notEnabled") }
    if traits.contains(.keyboardKey) { names.append("keyboardKey") }
    if traits.contains(.summaryElement) { names.append("summaryElement") }
    if traits.contains(.updatesFrequently) { names.append("updatesFrequently") }
    if traits.contains(.playsSound) { names.append("playsSound") }
    if traits.contains(.startsMediaSession) { names.append("startsMediaSession") }
    if traits.contains(.allowsDirectInteraction) { names.append("allowsDirectInteraction") }
    if traits.contains(.causesPageTurn) { names.append("causesPageTurn") }
    if traits.contains(.tabBar) { names.append("tabBar") }
    return names
}
```

#### 2. InsideMan.swift — Add diff computation

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add a method to compute the delta between two HeistElement arrays:

```swift
/// Compare two element snapshots and return a compact delta.
private func computeDelta(
    before: [HeistElement],
    after: [HeistElement],
    afterTree: [AccessibilityHierarchy]?
) -> InterfaceDelta {
    // Quick check: if hash is identical, nothing changed
    if before.hashValue == after.hashValue && before == after {
        return InterfaceDelta(kind: .noChange, elementCount: after.count)
    }

    // Build identifier sets for screen-change detection
    let oldIDs = Set(before.compactMap(\.identifier))
    let newIDs = Set(after.compactMap(\.identifier))
    let commonIDs = oldIDs.intersection(newIDs)
    let maxCount = max(oldIDs.count, newIDs.count, 1)

    // Screen change: fewer than 50% of identifiers overlap
    if commonIDs.count < maxCount / 2 {
        let tree = afterTree?.map { convertHierarchyNode($0) }
        let fullInterface = Interface(timestamp: Date(), elements: after, tree: tree)
        return InterfaceDelta(
            kind: .screenChanged,
            elementCount: after.count,
            newInterface: fullInterface
        )
    }

    // Element-level diff
    let oldByID = Dictionary(grouping: before.filter { $0.identifier != nil }, by: { $0.identifier! })
    let newByID = Dictionary(grouping: after.filter { $0.identifier != nil }, by: { $0.identifier! })

    // Added elements
    let addedIDs = newIDs.subtracting(oldIDs)
    let added = addedIDs.flatMap { newByID[$0] ?? [] }

    // Removed elements
    let removedIDs = oldIDs.subtracting(newIDs)
    let removedOrders = removedIDs.flatMap { oldByID[$0] ?? [] }.map(\.order)

    // Value changes on common elements
    var valueChanges: [ValueChange] = []
    for id in commonIDs {
        if let oldEl = oldByID[id]?.first, let newEl = newByID[id]?.first {
            if oldEl.value != newEl.value {
                valueChanges.append(ValueChange(
                    order: newEl.order,
                    identifier: id,
                    oldValue: oldEl.value,
                    newValue: newEl.value
                ))
            }
        }
    }

    // Determine delta kind
    if added.isEmpty && removedOrders.isEmpty && valueChanges.isEmpty {
        if before.count != after.count {
            return InterfaceDelta(
                kind: .elementsChanged,
                elementCount: after.count,
                added: after.count > before.count ? Array(after.suffix(after.count - before.count)) : nil,
                removedOrders: after.count < before.count ? Array((after.count..<before.count)) : nil
            )
        }
        return InterfaceDelta(kind: .noChange, elementCount: after.count)
    }

    if added.isEmpty && removedOrders.isEmpty {
        return InterfaceDelta(
            kind: .valuesChanged,
            elementCount: after.count,
            valueChanges: valueChanges.isEmpty ? nil : valueChanges
        )
    }

    return InterfaceDelta(
        kind: .elementsChanged,
        elementCount: after.count,
        added: added.isEmpty ? nil : added,
        removedOrders: removedOrders.isEmpty ? nil : removedOrders,
        valueChanges: valueChanges.isEmpty ? nil : valueChanges
    )
}
```

#### 3. InsideMan.swift — Add post-action snapshot helper

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Add a method that snapshots, diffs, and builds the ActionResult:

```swift
/// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
private func actionResultWithDelta(
    success: Bool,
    method: ActionMethod,
    message: String? = nil,
    value: String? = nil,
    beforeElements: [HeistElement]
) -> ActionResult {
    guard success else {
        return ActionResult(success: false, method: method, message: message, value: value)
    }

    // Brief yield to let the runloop process UI updates
    // (accessibility tree updates are synchronous but may be deferred one cycle)
    let afterTree = refreshAccessibilityData()
    let afterElements = snapshotElements()

    let delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)
    return ActionResult(success: true, method: method, message: message, value: value, interfaceDelta: delta)
}
```

#### 4. InsideMan.swift — Update snapshotElements to return [HeistElement]

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Update `snapshotElements()` at line 596:

```swift
/// Convert current cachedElements to wire HeistElements for delta comparison.
private func snapshotElements() -> [HeistElement] {
    cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
}
```

#### 5. InsideMan.swift — Capture before-snapshot in action handlers

**File**: `ButtonHeist/Sources/InsideMan/InsideMan.swift`

Each action handler already calls `refreshAccessibilityData()` at the top. Right after that, capture the before-elements. Example for `handleActivate`:

```swift
private func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) {
    refreshAccessibilityData()

    // Capture before-snapshot for delta computation
    let beforeElements = snapshotElements()

    guard let element = findElement(for: target) else {
        sendMessage(.actionResult(ActionResult(
            success: false, method: .elementNotFound, message: "Element not found for target"
        )), respond: respond)
        return
    }
    // ... existing interactivity check and activation logic ...

    // On success, replace direct ActionResult construction with:
    let result = actionResultWithDelta(
        success: true, method: .activate, beforeElements: beforeElements
    )
    sendMessage(.actionResult(result), respond: respond)
}
```

Apply the same pattern to all action handlers:
- `handleActivate` — sync, straightforward
- `handleIncrement` — sync
- `handleDecrement` — sync
- `handleTouchTap` — sync
- `handlePerformCustomAction` — sync
- `handleTouchLongPress` — async (capture before outside Task, use inside)
- `handleTouchSwipe` — async
- `handleTouchDrag` — async
- `handleTouchPinch` — async
- `handleTouchRotate` — async
- `handleTouchTwoFingerTap` — async
- `handleTouchDrawPath` — async
- `handleTouchDrawBezier` — async
- `handleTypeText` — async (already reads value back; add delta too)

For async handlers, the pattern is:
```swift
private func handleTouchLongPress(_ target: LongPressTarget, respond: @escaping (Data) -> Void) {
    // Capture before-snapshot while still synchronous
    let beforeElements = snapshotElements()

    guard let point = resolvePoint(...) else { return }

    Task { @MainActor in
        let success = await self.safeCracker.longPress(at: point, duration: target.duration)
        if success { TapVisualizerView.showTap(at: point) }
        let result = self.actionResultWithDelta(
            success: success, method: .syntheticLongPress, beforeElements: beforeElements
        )
        self.sendMessage(.actionResult(result), respond: respond)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] InsideMan builds: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideMan -destination 'generic/platform=iOS' build`
- [x] TheGoods tests still pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test` (54/54 passed)

---

## Phase 3: MCP Server — Thin Pass-Through

### Overview
The MCP server should be as thin as possible. It just JSON-encodes the `interfaceDelta` from ActionResult and passes it through. Remove all server-side diffing infrastructure.

### Changes Required:

#### 1. main.swift — Update sendAction to pass through delta JSON

**File**: `ButtonHeistMCP/Sources/main.swift`

```swift
@MainActor
func sendAction(_ message: ClientMessage, client: HeistClient) async throws -> CallTool.Result {
    client.send(message)
    let result = try await client.waitForActionResult(timeout: 15)
    if result.success {
        var content: [Tool.Content] = [
            .text("Success (method: \(result.method.rawValue))"),
        ]
        if let delta = result.interfaceDelta {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let json = try? encoder.encode(delta), let str = String(data: json, encoding: .utf8) {
                content.append(.text(str))
            }
        }
        return CallTool.Result(content: content)
    } else {
        let errorMsg = result.message ?? result.method.rawValue
        return CallTool.Result(content: [.text("Failed: \(errorMsg)")], isError: true)
    }
}
```

No `formatDelta()`, no interpretation. Just encode and forward.

#### 2. main.swift — Update type_text handler the same way

```swift
if typeResult.success {
    var content: [Tool.Content] = [
        .text("Success (method: \(typeResult.method.rawValue))"),
    ]
    if let value = typeResult.value {
        content.append(.text("Value: \(value)"))
    }
    if let delta = typeResult.interfaceDelta {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let json = try? encoder.encode(delta), let str = String(data: json, encoding: .utf8) {
            content.append(.text(str))
        }
    }
    return CallTool.Result(content: content)
}
```

#### 3. main.swift — Remove all server-side diffing code

Delete everything that was doing diffing in the MCP server:
- `previousInterface` state variable
- `fetchInterfaceDiff()` function
- `InterfaceDiff` struct
- `diffInterfaces()` function
- `fetchInterface()` function
- `encodeInterface()` / `formatFullInterface()` (keep `encodeInterface` only for `get_interface` handler)

Simplify `requestInterface()` — just fetch and encode, no state tracking:
```swift
@MainActor
func requestInterface(client: HeistClient) async throws -> String {
    client.send(.requestInterface)
    let iface = try await withCheckedThrowingContinuation { continuation in
        var didResume = false
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            if !didResume { didResume = true; continuation.resume(throwing: HeistClient.ActionError.timeout) }
        }
        client.onInterfaceUpdate = { payload in
            if !didResume { didResume = true; timeoutTask.cancel(); continuation.resume(returning: payload) }
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let json = try encoder.encode(iface)
    return String(data: json, encoding: .utf8) ?? "{}"
}
```

### Success Criteria:

#### Automated Verification:
- [x] MCP server builds: `cd ButtonHeistMCP && swift build -c release`
- [x] All tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoodsTests test && xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeistTests test`

---

## Phase 4: Update Fuzzer Documentation

### Overview
Update SKILL.md and command files to explain the new delta format.

### Changes Required:

#### 1. ai-fuzzer/SKILL.md — Update efficiency rules

Replace the current "Key efficiency rules" section with:

```markdown
**Key efficiency rules:**
- **Action tools return interface deltas.** Every successful action includes a delta showing what changed:
  - `NO_CHANGE: N elements` — nothing happened, move on
  - `VALUES_CHANGED:` — same screen, specific values changed (listed)
  - `ELEMENTS_CHANGED: N elements` — elements added/removed (listed)
  - `SCREEN_CHANGED: N elements` — navigated to a new screen, full interface JSON included
- **Only call `get_interface` at session start** or when you need the full hierarchy without performing an action. The deltas give you everything you need during action sequences.
- Only call `get_screen` when investigating a finding or on a brand new screen
- Only read your session notes file at session start and after compaction
- Write session notes every 5 actions, not every action
- Write trace entries in batches
```

#### 2. ai-fuzzer/SKILL.md — Add element classification guidance

Add a section to the fuzzer's core loop about using deltas to classify elements:

```markdown
**Using deltas to guide exploration:**

The delta tells you whether an element is **live** (causes changes) or **inert** (does nothing):
- `NO_CHANGE` after activating an element → **inert**. It's a label, decorative, or its effect is invisible to the hierarchy. Deprioritize it.
- `VALUES_CHANGED` → **live, stateful**. This element controls state (toggle, slider, text field, picker). Try different values, boundary conditions, rapid toggling.
- `ELEMENTS_CHANGED` → **live, structural**. This element adds/removes UI (expand/collapse, show/hide sections, add list items). Explore the new elements that appeared.
- `SCREEN_CHANGED` → **live, navigational**. This element navigates (push, modal, tab switch). Map the new screen, explore it, then come back.

Track which elements are live in your session notes. Focus fuzzing effort on live elements — they're where the bugs are.
```

#### 3. Command files — Update CRITICAL blocks

Update the CRITICAL blocks in `fuzz.md`, `explore.md`, and other commands to reference deltas instead of the old diff format.

### Success Criteria:
- [ ] Documentation accurately describes the delta format and element classification
- [ ] No references to old diff format remain in fuzzer docs

---

## Testing Strategy

### Unit Tests (TheGoods):
- HeistElement round-trip encoding (all new fields: traits, hint, activationPoint, customContent, respondsToUserInteraction)
- HeistElement backwards compat: JSON without new fields decodes gracefully (optional fields nil out)
- HeistCustomContent encoding
- ActionResult with nil delta encodes/decodes correctly (backwards compat)
- ActionResult with each delta kind encodes/decodes correctly
- InterfaceDelta round-trip encoding for each kind (deltas reference HeistElement in `added` arrays)
- ValueChange encoding

### Integration Testing:
- Deploy to simulator, call `get_interface` → verify HeistElement JSON includes traits, hint, activationPoint
- Tap a static button → delta shows `noChange`
- Tap a toggle → delta shows `valuesChanged` with old/new value
- Navigate to a new screen → delta shows `screenChanged` with full interface containing HeistElements
- Increment a slider → delta shows `valuesChanged`
- Verify a button element has `traits: ["button"]` and `respondsToUserInteraction: true`
- Verify a static text element has `traits: ["staticText"]` and `respondsToUserInteraction: false`

## Performance Considerations

- **Hash comparison first**: `elements.hashValue` check means the common case (no change) is O(1)
- **No extra network round-trip**: Delta is computed inside InsideMan and sent with the ActionResult
- **No sleep/timer**: The only delay is a single `refreshAccessibilityData()` call (~5ms)
- **Small payloads**: Most deltas are a few lines of text (NO_CHANGE or VALUES_CHANGED). Only SCREEN_CHANGED includes full interface JSON.
- **HeistElement is larger than UIElement**: The richer fields (traits, hint, activationPoint, customContent) add ~100-200 bytes per element. For a typical 50-element screen, a SCREEN_CHANGED delta grows by ~5-10KB — negligible over localhost/USB. The tradeoff is worth it: clients no longer need to call `get_interface` to understand element types.

## References

- Wire protocol: `docs/WIRE-PROTOCOL.md`
- Current UIElement (to be renamed HeistElement): `ButtonHeist/Sources/TheGoods/Messages.swift:710-748`
- Current Interface struct: `ButtonHeist/Sources/TheGoods/Messages.swift:651-662`
- Parser AccessibilityElement (wrapped by HeistElement): `AccessibilitySnapshot/Sources/AccessibilitySnapshot/Parser/Swift/Classes/AccessibilityElement.swift`
- convertElement (UIElement construction): `ButtonHeist/Sources/InsideMan/InsideMan.swift:1334-1348`
- snapshotElements: `ButtonHeist/Sources/InsideMan/InsideMan.swift:595-597`
- Current MCP diffing: `ButtonHeistMCP/Sources/main.swift:704-802`
- InsideMan action handlers: `ButtonHeist/Sources/InsideMan/InsideMan.swift:554-607`
- ActionResult type: `ButtonHeist/Sources/TheGoods/Messages.swift:408-421`

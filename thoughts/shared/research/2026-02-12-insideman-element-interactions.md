---
date: 2026-02-12T19:06:43Z
researcher: Claude
git_commit: eb36fb015c62a07c008387dbda9466c1debd0bf4
branch: RoyalPineapple/heist-rebrand
repository: accra
topic: "InsideMan Element Interaction System"
tags: [research, codebase, insideman, interactions, touch-injection, safecracker, wheelman, cli]
status: complete
last_updated: 2026-02-12
last_updated_by: Claude
---

# Research: InsideMan Element Interaction System

**Date**: 2026-02-12T19:06:43Z
**Researcher**: Claude
**Git Commit**: eb36fb015c62a07c008387dbda9466c1debd0bf4
**Branch**: RoyalPineapple/heist-rebrand
**Repository**: accra

## Research Question
How does InsideMan interact with accessibility elements? What interactions are available, how is each implemented end-to-end, how are elements targeted, what wire protocol messages are involved, and how does the CLI trigger interactions?

## Summary

InsideMan provides **two categories of element interactions**: accessibility-based actions (activate, increment, decrement, custom action) and synthetic touch gestures (tap, long press, swipe, drag, pinch, rotate, two-finger tap). Accessibility actions use UIKit's accessibility API methods on resolved views, while touch gestures use a low-level IOKit-based touch injection system called SafeCracker. Elements are targeted by accessibility identifier or snapshot order index, and touch gestures can alternatively target raw screen coordinates. The CLI sends JSON-encoded `ClientMessage` enums over newline-delimited TCP sockets, and the server responds with `ActionResult` containing success status and execution method.

## Detailed Findings

### 1. Available Interactions

#### Accessibility Actions (element-only targeting)

| Action | ClientMessage | Handler | Method |
|--------|--------------|---------|--------|
| Activate | `.activate(ActionTarget)` | `handleActivate()` | `accessibilityActivate()` → SafeCracker tap fallback |
| Increment | `.increment(ActionTarget)` | `handleIncrement()` | `accessibilityIncrement()` on resolved view |
| Decrement | `.decrement(ActionTarget)` | `handleDecrement()` | `accessibilityDecrement()` on resolved view |
| Custom Action | `.performCustomAction(CustomActionTarget)` | `handleCustomAction()` | Finds action by name, calls handler or target/selector |

#### Synthetic Touch Gestures (element or coordinate targeting)

| Gesture | ClientMessage | Handler | SafeCracker Method |
|---------|--------------|---------|-------------------|
| Tap | `.touchTap(TouchTapTarget)` | `handleTouchTap()` | `tap(at:)` |
| Long Press | `.touchLongPress(LongPressTarget)` | `handleTouchLongPress()` | `longPress(at:duration:)` |
| Swipe | `.touchSwipe(SwipeTarget)` | `handleTouchSwipe()` | `swipe(from:to:duration:)` |
| Drag | `.touchDrag(DragTarget)` | `handleTouchDrag()` | `drag(from:to:duration:)` |
| Pinch | `.touchPinch(PinchTarget)` | `handleTouchPinch()` | `pinch(center:scale:spread:duration:)` |
| Rotate | `.touchRotate(RotateTarget)` | `handleTouchRotate()` | `rotate(center:angle:radius:duration:)` |
| Two-Finger Tap | `.touchTwoFingerTap(TwoFingerTapTarget)` | `handleTouchTwoFingerTap()` | `twoFingerTap(at:spread:)` |

### 2. How Each Interaction Works

#### Activate (`InsideMan.swift:459-505`)

1. Refreshes cached hierarchy by re-parsing from root view
2. Resolves element via `findElement(for:)` using identifier or order
3. Checks interactivity via `checkElementInteractivity()` — rejects disabled elements, warns on static-only traits
4. Gets element's `activationPoint`
5. **First attempt**: Hit-tests to find UIView at that point, calls `view.accessibilityActivate()`
6. **Fallback**: If activate returns false, calls `safeCracker.tap(at: point)` for synthetic touch injection
7. Shows visual feedback via `TapVisualizerView.showTap(at: point)` on success
8. Returns `ActionResult` with method `.activate` or `.syntheticTap`

#### Increment / Decrement (`InsideMan.swift:507-553`)

1. Refreshes cached hierarchy
2. Resolves element via `findElement(for:)`
3. Hit-tests to find UIView at element's activation point
4. Calls `view.accessibilityIncrement()` or `view.accessibilityDecrement()`
5. Shows visual feedback, returns `ActionResult` with method `.increment` / `.decrement`

#### Custom Action (`InsideMan.swift:702-754`)

1. Refreshes cached hierarchy
2. Resolves element via `findElement(for:)` using `target.elementTarget`
3. Hit-tests to find UIView at element's activation point
4. Iterates `view.accessibilityCustomActions` to find action matching `target.actionName`
5. If action has `actionHandler` closure: calls it, returns the Bool result
6. If action has target/selector: performs selector via `(actionTarget as AnyObject).perform(action.selector)`
7. Returns `ActionResult` with method `.customAction`

#### Touch Tap (`InsideMan.swift:557-575`)

1. Resolves point via `resolvePoint()` — from element's activation point OR explicit coordinates
2. **First attempt**: Hit-tests for UIView, calls `accessibilityActivate()`
3. **Fallback**: `safeCracker.tap(at: point)` — synthetic touch down then up
4. Shows visual feedback on success

#### Touch Long Press (`InsideMan.swift:577-585`)

1. Resolves point from element or coordinates
2. Calls `safeCracker.longPress(at: point, duration: target.duration)` (async)
3. SafeCracker performs: touch down → sleep(duration) → touch up
4. Shows visual feedback on success

#### Touch Swipe (`InsideMan.swift:587-613`)

1. Resolves start point from element or coordinates
2. Resolves end point from either:
   - Explicit `endX`/`endY` coordinates, OR
   - `direction` (up/down/left/right) + `distance` (default 200pt)
3. Calls `safeCracker.swipe(from:to:duration:)` (async, default 0.15s)
4. SafeCracker performs: touch down → linear interpolation moves (min 3 steps, 10ms apart) → touch up

#### Touch Drag (`InsideMan.swift:615-624`)

1. Resolves start point from element or coordinates
2. End point from `target.endPoint` (required `endX`/`endY`)
3. Calls `safeCracker.drag(from:to:duration:)` (async, default 0.5s)
4. SafeCracker performs: touch down → linear interpolation moves (min 5 steps, 10ms apart) → touch up

#### Touch Pinch (`InsideMan.swift:626-636`)

1. Resolves center point from element or coordinates
2. Calls `safeCracker.pinch(center:scale:spread:duration:)` (async)
3. SafeCracker places two fingers at 45° diagonal, interpolates spread from `initial` to `initial * scale`
4. Scale >1.0 = zoom in (spread apart), <1.0 = zoom out (pinch together)

#### Touch Rotate (`InsideMan.swift:638-648`)

1. Resolves center point from element or coordinates
2. Calls `safeCracker.rotate(center:angle:radius:duration:)` (async)
3. SafeCracker places two fingers 180° apart at given radius, rotates both by angle in radians

#### Touch Two-Finger Tap (`InsideMan.swift:650-656`)

1. Resolves center point from element or coordinates
2. Calls `safeCracker.twoFingerTap(at:spread:)` (synchronous)
3. SafeCracker places two fingers horizontally, performs down then up with no movement

### 3. Element Targeting

#### ActionTarget Structure (`Messages.swift:69-79`)

```swift
public struct ActionTarget: Codable, Sendable {
    public let identifier: String?  // Accessibility identifier
    public let order: Int?          // 0-based index in snapshot
}
```

#### Resolution in InsideMan (`InsideMan.swift:411-419`)

```swift
private func findElement(for target: ActionTarget) -> AccessibilityMarker? {
    if let identifier = target.identifier {
        return cachedElements.first { $0.identifier == identifier }
    }
    if let index = target.order, index >= 0, index < cachedElements.count {
        return cachedElements[index]
    }
    return nil
}
```

Priority: identifier first, then order index. The `cachedElements` array is refreshed from the accessibility hierarchy before each action.

#### Point Resolution for Touch Gestures (`InsideMan.swift:660-681`)

Touch gestures support three targeting modes:

1. **Element target** — resolves to `element.activationPoint` (center of element frame)
2. **Explicit coordinates** — `pointX`/`pointY` used directly as `CGPoint`
3. **Neither** — returns error "No target specified"

#### Hit Testing (`InsideMan.swift:422-431`)

After resolving a point, `findViewAtPoint()` uses UIKit hit testing to find the actual UIView:
```swift
window.hitTest(windowPoint, with: nil)
```
This is used by accessibility actions to call methods on the resolved UIView.

#### Interactivity Check (`InsideMan.swift:435-457`)

Before activate actions, `checkElementInteractivity()` checks:
- Rejects elements with `.notEnabled` trait
- Warns (but allows) elements with only static traits (`.staticText`, `.image`, `.header`)
- Considers interactive: `.button`, `.link`, `.adjustable`, `.searchField`, `.keyboardKey`

### 4. Wire Protocol Messages

#### Client → Server (Action-Related)

| Message | Payload | Targeting |
|---------|---------|-----------|
| `activate` | `ActionTarget` | identifier or order |
| `increment` | `ActionTarget` | identifier or order |
| `decrement` | `ActionTarget` | identifier or order |
| `performCustomAction` | `CustomActionTarget` | identifier or order + action name |
| `touchTap` | `TouchTapTarget` | element or coordinates |
| `touchLongPress` | `LongPressTarget` | element or coordinates + duration |
| `touchSwipe` | `SwipeTarget` | element or coordinates + end/direction + duration |
| `touchDrag` | `DragTarget` | element or coordinates + end + duration |
| `touchPinch` | `PinchTarget` | element or coordinates + scale + spread + duration |
| `touchRotate` | `RotateTarget` | element or coordinates + angle + radius + duration |
| `touchTwoFingerTap` | `TwoFingerTapTarget` | element or coordinates + spread |

#### Server → Client (Action Response)

| Message | Payload |
|---------|---------|
| `actionResult` | `ActionResult { success: Bool, method: ActionMethod, message: String? }` |

#### ActionMethod Values

- `activate` — `accessibilityActivate()` succeeded
- `syntheticTap` — SafeCracker touch injection used
- `syntheticLongPress`, `syntheticSwipe`, `syntheticDrag`, `syntheticPinch`, `syntheticRotate`, `syntheticTwoFingerTap` — SafeCracker gesture injection
- `increment`, `decrement` — Accessibility adjustment methods
- `customAction` — Custom accessibility action executed
- `elementNotFound` — Target element could not be resolved
- `elementDeallocated` — Element was deallocated (unused in current code)

#### Transport

- TCP socket, newline-delimited JSON (`0x0A` separator)
- Messages are `Codable` enums with associated values
- Bonjour discovery via `_buttonheist._tcp` service type

### 5. CLI Interaction Commands

#### Action Command (`ButtonHeistCLI/Sources/ActionCommand.swift`)

```
buttonheist action --identifier <id> --type <activate|increment|decrement|custom> [--custom-action <name>]
buttonheist action --index <n> --type activate
```

Arguments:
- `--identifier` — Element accessibility identifier
- `--index` — Element order (0-based)
- `--type` — Action type (default: "activate")
- `--custom-action` — Required when type is "custom"
- `--timeout` — Wait timeout in seconds (default: 10)
- `--quiet` — Suppress status messages

#### Touch Command (`ButtonHeistCLI/Sources/TouchCommand.swift`)

**Tap**:
```
buttonheist touch tap --identifier <id>
buttonheist touch tap --x <x> --y <y>
```

**Long Press**:
```
buttonheist touch long-press --identifier <id> --duration 1.0
buttonheist touch long-press --x <x> --y <y> --duration 0.5
```

**Swipe**:
```
buttonheist touch swipe --identifier <id> --direction up --distance 300
buttonheist touch swipe --from-x 100 --from-y 400 --to-x 100 --to-y 100
buttonheist touch swipe --from-x 200 --from-y 300 --direction left --duration 0.2
```

**Drag**:
```
buttonheist touch drag --identifier <id> --to-x 200 --to-y 500 --duration 1.0
buttonheist touch drag --from-x 100 --from-y 100 --to-x 300 --to-y 300
```

**Pinch**:
```
buttonheist touch pinch --identifier <id> --scale 2.0 --spread 80
buttonheist touch pinch --x 200 --y 400 --scale 0.5 --duration 0.3
```

**Rotate**:
```
buttonheist touch rotate --identifier <id> --angle 1.57 --radius 120
buttonheist touch rotate --x 200 --y 400 --angle -0.78
```

**Two-Finger Tap**:
```
buttonheist touch two-finger-tap --identifier <id> --spread 50
buttonheist touch two-finger-tap --x 200 --y 400
```

#### CLI → Server Flow

1. CLI creates `Wheelman()` client
2. Starts Bonjour discovery (5s timeout)
3. Connects to first discovered device via TCP
4. Constructs `ClientMessage` from arguments
5. Calls `client.send(message)`
6. Calls `client.waitForActionResult(timeout:)` (async continuation)
7. Outputs "success" or "failed: \<error\>" to stdout
8. Exits with code 0 (success) or 1 (failure)

### 6. SafeCracker: Touch Injection Engine

**Location**: `ButtonHeist/Sources/InsideMan/SafeCracker.swift` (324 lines)

**Supporting files**:
- `SyntheticTouchFactory.swift` — Creates UITouch instances via private UIKit selectors
- `SyntheticEventFactory.swift` — Creates UIEvent instances via private UIKit methods
- `IOHIDEventBuilder.swift` — Creates IOHIDEvent structures via dynamically loaded IOKit

#### Three-Layer Architecture

1. **IOKit/IOHIDEvent** — Hardware-level digitizer events with hand container + per-finger events (position, pressure, radius)
2. **UIKit/UITouch** — Touch objects created via private selectors (`setWindow:`, `setView:`, `_setLocationInWindow:resetPrevious:`, `setPhase:`)
3. **UIKit/UIEvent** — Event container delivered via `UIApplication.shared.sendEvent(event)`

#### Touch Lifecycle

1. `touchesDown(at: [CGPoint])` — Hit-tests points, creates UITouch + IOHIDEvent + UIEvent, sends to UIApplication
2. `moveTouches(to: [CGPoint])` — Updates touch locations/phases, creates fresh events (iOS 26 fix), sends
3. `touchesUp()` — Sets phases to `.ended`, creates final events, clears state

#### Gesture Timing Defaults

| Gesture | Duration | Step Delay | Min Steps |
|---------|----------|------------|-----------|
| Tap | instant | — | — |
| Long Press | 0.5s | — | — |
| Swipe | 0.15s | 10ms | 3 |
| Drag | 0.5s | 10ms | 5 |
| Pinch | 0.5s | 10ms | 5 |
| Rotate | 0.5s | 10ms | 5 |
| Two-Finger Tap | instant | — | — |

### 7. Visual Feedback: TapVisualizerView

**Location**: `ButtonHeist/Sources/InsideMan/TapVisualizerView.swift`

- Passthrough overlay window at `.statusBar + 100` window level
- White circle (40pt diameter, 50% opacity fill, 90% opacity border, drop shadow)
- Animates: scales to 150% + fades to transparent over 0.8s
- Triple passthrough (window, root view, circle view all return nil from `hitTest`)
- Shown after: activate, synthetic tap, increment, decrement, long press
- Not shown for: swipe, drag, pinch, rotate, two-finger tap

## Code References

- `ButtonHeist/Sources/InsideMan/InsideMan.swift:174-213` — Message dispatch switch
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:411-419` — Element resolution
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:435-457` — Interactivity check
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:459-505` — Activate handler
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:557-656` — Touch gesture handlers
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:660-681` — Point resolution
- `ButtonHeist/Sources/InsideMan/InsideMan.swift:702-754` — Custom action handler
- `ButtonHeist/Sources/InsideMan/SafeCracker.swift` — Touch injection engine
- `ButtonHeist/Sources/InsideMan/SyntheticTouchFactory.swift` — UITouch creation via private APIs
- `ButtonHeist/Sources/InsideMan/SyntheticEventFactory.swift` — UIEvent creation via private APIs
- `ButtonHeist/Sources/InsideMan/IOHIDEventBuilder.swift` — IOKit digitizer event creation
- `ButtonHeist/Sources/InsideMan/TapVisualizerView.swift` — Visual tap feedback
- `ButtonHeist/Sources/TheGoods/Messages.swift:12-64` — ClientMessage enum
- `ButtonHeist/Sources/TheGoods/Messages.swift:69-268` — Target structs
- `ButtonHeist/Sources/TheGoods/Messages.swift:277-344` — ServerMessage + ActionResult
- `ButtonHeist/Sources/Wheelman/Wheelman.swift:192-219` — Send + waitForActionResult
- `ButtonHeist/Sources/Wheelman/DeviceConnection.swift:146-162` — Socket transmission
- `ButtonHeistCLI/Sources/ActionCommand.swift` — CLI action command
- `ButtonHeistCLI/Sources/TouchCommand.swift` — CLI touch gesture commands

## Architecture Documentation

### Interaction Dispatch Flow

```
CLI (ArgumentParser)
  → Wheelman.send(ClientMessage)
    → DeviceConnection.send() [JSON + newline over TCP]
      → InsideMan.handleClientMessage() [decode + switch]
        → handler method (handleActivate, handleTouchSwipe, etc.)
          → resolvePoint() or findElement() [targeting]
            → UIKit accessibility API or SafeCracker [execution]
              → TapVisualizerView.showTap() [visual feedback]
        → sendMessage(.actionResult(...)) [response]
      → DeviceConnection.handleMessage() [decode response]
    → Wheelman.onActionResult [callback]
  → CLI outputs result
```

### Two Execution Strategies

1. **Accessibility API path** — Used for activate, increment, decrement, custom actions. Calls UIAccessibility methods on the resolved UIView. Higher fidelity, respects accessibility behaviors.

2. **SafeCracker injection path** — Used for all touch gestures and as fallback for activate. Synthesizes IOHIDEvent + UITouch + UIEvent and injects via `sendEvent()`. Works at hardware event level, bypasses accessibility layer.

## Related Research

- `thoughts/shared/research/2026-02-04-ios26-interaction-support.md` — iOS 26 touch injection investigation
- `thoughts/shared/research/2026-02-12-external-api-surface-review.md` — External API surface review

## Open Questions

- None identified — the interaction system is well-documented through this research.

---
date: 2026-02-04T15:31:01+01:00
researcher: Claude
git_commit: c5d26834af32770895d39cad81699bd3b25fe87f
branch: RoyalPineapple/ios26-interaction-fix
repository: memphis
topic: "iOS 26 Interaction Support - Current Implementation Analysis"
tags: [research, codebase, ios26, interaction, touch-injection, accessibility]
status: complete
last_updated: 2026-02-04
last_updated_by: Claude
last_updated_note: "Added KIF touch injection reference and iOS 26 fix details"
---

# Research: iOS 26 Interaction Support

**Date**: 2026-02-04T15:31:01+01:00
**Researcher**: Claude
**Git Commit**: c5d26834af32770895d39cad81699bd3b25fe87f
**Branch**: RoyalPineapple/ios26-interaction-fix
**Repository**: memphis

## Research Question

Understanding the current state of iOS 26 interaction support in the Accra codebase, specifically how element interactions (tap, activate, increment, decrement, custom actions) are implemented and what iOS 26-specific limitations exist.

## Summary

The Accra codebase implements element interactions through a multi-tier fallback system in `TouchInjector.swift`. iOS 26 compatibility notes indicate that **low-level private API touch injection has been disabled** due to API changes, leaving only high-level methods:

1. `accessibilityActivate()` - highest priority
2. `UIControl.sendActions(for: .touchUpInside)` - for UIControl subclasses
3. Responder chain walk to find parent UIControls

The system returns `false` (failure) when all three methods fail to activate an element. There are **no runtime iOS version checks** (`@available` or `#available`) - the code simply doesn't include the low-level touch injection path that previously existed.

## Detailed Findings

### TouchInjector Implementation

**Location**: `AccraCore/Sources/AccraHost/TouchInjector.swift`

The TouchInjector class is the primary component for simulating taps:

```swift
@MainActor
final class TouchInjector {
    func tap(at point: CGPoint) -> Bool
}
```

#### Current Fallback Chain (Lines 17-56)

1. **Get key window** (lines 18-21) - Early exit if no window found
2. **Hit test at coordinates** (line 27) - Find view at tap location
3. **Tier 1: accessibilityActivate()** (lines 28-32) - First attempt
4. **Tier 2: Direct UIControl** (lines 34-39) - Cast to UIControl, call sendActions
5. **Tier 3: Responder chain** (lines 41-50) - Walk up to find UIControl ancestor
6. **Failure** (lines 53-56) - Return false with diagnostic log

#### iOS 26 Documentation (Lines 15-16, 53-54)

```swift
/// On iOS 26+ Simulator, synthetic taps may not be available.
```

```swift
// Low-level touch injection is disabled on iOS 26+ as the private APIs have changed.
// The high-level methods (accessibilityActivate, sendActions) should be used instead.
```

### AccraHost Action Handlers

**Location**: `AccraCore/Sources/AccraHost/AccraHost.swift`

#### handleActivate() (Lines 419-449)

1. Refreshes hierarchy via `parser.parseAccessibilityElements()`
2. Finds element using `findElement(for: target)`
3. Calls `touchInjector.tap(at: element.activationPoint)`
4. Returns `ActionResult` with `method: .syntheticTap` on success

#### handleTap() (Lines 499-534)

Supports two modes:
- **Element-based**: Uses `element.activationPoint`
- **Coordinate-based**: Uses raw `CGPoint` from `target.point`

Both paths use `touchInjector.tap()` and return `.syntheticTap` method.

#### handleIncrement() / handleDecrement() (Lines 451-497)

These use a different approach:
1. Find element via identifier/index
2. Call `findViewAtPoint()` to get the actual UIView
3. Call `view.accessibilityIncrement()` or `view.accessibilityDecrement()`
4. Return `ActionResult` with `.accessibilityIncrement` or `.accessibilityDecrement` method

#### handleCustomAction() (Lines 555-607)

1. Find element and view at activation point
2. Iterate `view.accessibilityCustomActions` array
3. Match by `action.name == target.actionName`
4. Execute via handler closure or target-selector

### Unused Private API Code (Historical)

**Location**: `AccraCore/Sources/AccraHost/AccraHost.swift` (Lines 741-862)

There is an `AccessibilityMarker` extension with a `simulateTouchOnView()` method that uses private APIs:

```swift
private func simulateTouchOnView(_ view: UIView, at point: CGPoint, in window: UIWindow) {
    guard let touchClass = NSClassFromString("UITouch") as? NSObject.Type,
          let touch = touchClass.init() as? UITouch else { return }

    touch.setValue(point, forKey: "locationInWindow")
    touch.setValue(window, forKey: "window")
    touch.setValue(view, forKey: "view")
    touch.setValue(UITouch.Phase.began.rawValue, forKey: "phase")
    // ...
    view.touchesBegan(touches, with: event)
    view.touchesEnded(touches, with: event)
}
```

**This code exists but is NOT currently called** from the main action handlers. The `activate` closure in `AccessibilityMarker` contains this code, but the actual `handleActivate()` and `handleTap()` methods use `TouchInjector` instead.

### Visual Feedback System

**Location**: `AccraCore/Sources/AccraHost/TapVisualizerView.swift`

After successful tap actions, visual feedback is provided:
- White 40x40 circle at tap location
- Scales to 1.5x and fades out over 0.8 seconds
- Overlay window at `.statusBar + 100` level
- Passthrough for all touch events

### Version-Specific Research Documents

**Location**: `research/private-api-findings.md`

Documents experimental results from iOS 18.2 Simulator:
- AXRuntime classes load successfully
- Standard UIAccessibility APIs work for SwiftUI
- `_accessibilityUserTestingChildren` returns SwiftUI.AccessibilityNode objects
- Private API external tree access returns nil from within the app

**Location**: `research/external-accessibility-client.md`

Notes that iOS 17.0.1+ and iOS 18.x have patched external accessibility client techniques.

## Code References

| File | Line(s) | Description |
|------|---------|-------------|
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 16 | iOS 26 Simulator note |
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 53-54 | iOS 26 private API disabled comment |
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 17-56 | `tap(at:)` implementation |
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 28-32 | accessibilityActivate() tier |
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 34-39 | UIControl sendActions tier |
| `AccraCore/Sources/AccraHost/TouchInjector.swift` | 41-50 | Responder chain tier |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 36 | TouchInjector instantiation |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 419-449 | handleActivate() |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 499-534 | handleTap() |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 451-473 | handleIncrement() |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 475-497 | handleDecrement() |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 555-607 | handleCustomAction() |
| `AccraCore/Sources/AccraHost/AccraHost.swift` | 791-820 | Unused simulateTouchOnView() |
| `AccraCore/Sources/AccraHost/TapVisualizerView.swift` | 63-97 | showTap() implementation |

## Architecture Documentation

### Current Interaction Flow

```
Client Request (.activate / .tap)
        ↓
    AccraHost
        ↓
  Refresh Hierarchy
        ↓
   Find Element
        ↓
  TouchInjector.tap(at: activationPoint)
        ↓
    ┌─────────────────────────────────┐
    │  Tier 1: accessibilityActivate()│ → Success → Return true
    └─────────────────────────────────┘
                ↓ Failure
    ┌─────────────────────────────────┐
    │  Tier 2: UIControl.sendActions()│ → Success → Return true
    └─────────────────────────────────┘
                ↓ Failure
    ┌─────────────────────────────────┐
    │  Tier 3: Responder chain walk   │ → Success → Return true
    └─────────────────────────────────┘
                ↓ Failure
    ┌─────────────────────────────────┐
    │  Return false (no iOS 26 path)  │
    └─────────────────────────────────┘
```

### Deployment Targets

- Project minimum: iOS 17.0+ (`Project.swift`, `TestApp/Project.swift`)
- AccraCore package: iOS 17+ (`AccraCore/Package.swift`)

### Action Result Methods

| Method | Usage |
|--------|-------|
| `.syntheticTap` | TouchInjector success |
| `.accessibilityActivate` | handleActivate failure (legacy) |
| `.accessibilityIncrement` | handleIncrement success |
| `.accessibilityDecrement` | handleDecrement success |
| `.customAction` | handleCustomAction success |
| `.elementNotFound` | Element lookup failure |

## Key Observations

1. **No runtime iOS version detection**: The codebase does not check `ProcessInfo.operatingSystemVersion` or use `@available`/`#available` guards for interaction code paths.

2. **Private API code exists but unused**: The `AccessibilityMarker.simulateTouchOnView()` method at lines 791-820 contains KVC-based touch injection, but it's not called by the current handlers.

3. **SwiftUI compatibility**: The `accessibilityActivate()` method is the first fallback tier, which works well with SwiftUI views that implement accessibility activation.

4. **UIControl dependency**: Tiers 2 and 3 rely on finding a `UIControl` in the view hierarchy. Pure SwiftUI views without UIControl backing may only work via Tier 1.

5. **No low-level fallback**: When all three tiers fail, the system returns `false` rather than attempting private API touch injection.

## Related Research

- `thoughts/shared/research/2026-02-02-notification-swizzling-failure.md` - UIAccessibility notification research
- `thoughts/shared/research/2026-01-31-accessibility-tree-visualization.md` - Accessibility tree visualization
- `research/private-api-findings.md` - iOS 18 private API exploration
- `research/swiftui-accessibility-insights.md` - SwiftUI accessibility research

## Follow-up Research: KIF Touch Injection Reference

### KIF iOS 26 Fix (PR #1334)

**Source**: [github.com/kif-framework/KIF/pull/1334](https://github.com/kif-framework/KIF/pull/1334)

#### Root Cause Identified

> On iOS 26, KIF's current touch injection logic in `-tapAtPoint:` sometimes fails to trigger taps on non-UIControl views (e.g. `UILabel`, `UIView`).
>
> The root cause is that KIF reuses the **same `UIEvent` instance** for multiple touch phases (`Began` and `Ended`).
>
> In earlier iOS versions this worked, but starting with iOS 26, UIKit appears to enforce stricter validation of `UIEvent` snapshots. If the event does not match the current `UITouch` phase, the system may ignore the injected event, resulting in taps being dropped.

#### The Fix

**Before (broken on iOS 26):**
```objc
UITouch *touch = [[UITouch alloc] initAtPoint:point inView:self];
[touch setPhaseAndUpdateTimestamp:UITouchPhaseBegan];

UIEvent *event = [self eventWithTouch:touch];       // One event
[[UIApplication sharedApplication] kif_sendEvent:event];

[touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
[[UIApplication sharedApplication] kif_sendEvent:event];  // Reuse same event ❌
```

**After (works on iOS 26):**
```objc
UITouch *touch = [[UITouch alloc] initAtPoint:point inView:self];
[touch setPhaseAndUpdateTimestamp:UITouchPhaseBegan];

UIEvent *beganEvent = [self eventWithTouch:touch];  // Event for began
[[UIApplication sharedApplication] kif_sendEvent:beganEvent];

[touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
UIEvent *endedEvent = [self eventWithTouch:touch];  // NEW event for ended ✓
[[UIApplication sharedApplication] kif_sendEvent:endedEvent];
```

### KIF's Touch Injection Architecture

#### 1. UITouch Creation (`UITouch-KIFAdditions.m`)

KIF creates UITouch objects using private API setters:

```objc
// Initialization
- (id)initAtPoint:(CGPoint)point inView:(UIView *)view;

// Private setters used:
- setWindow:          // Must be called first (wipes some values)
- setView:
- setPhase:
- _setLocationInWindow:resetPrevious:
- setTapCount:
- _setIsFirstTouchForView:
- setIsTap:
- _setHidEvent:       // Required for iOS 9+ (sets IOHIDEvent)
```

#### 2. UIEvent Creation (`UIView-KIFAdditions.m`)

```objc
- (UIEvent *)eventWithTouches:(NSArray *)touches {
    // Get the private _touchesEvent from UIApplication
    UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];

    // Clear any existing touches
    [event _clearTouches];

    // Set the IOHIDEvent on the event
    [event kif_setEventWithTouches:touches];

    // Add each touch to the event
    for (UITouch *aTouch in touches) {
        [event _addTouch:aTouch forDelayedDelivery:NO];
    }

    return event;
}
```

#### 3. IOHIDEvent Creation (`IOHIDEvent+KIF.m`)

For iOS 8+, KIF creates IOHIDEvent structures:

```objc
IOHIDEventRef kif_IOHIDEventWithTouches(NSSet *touches) {
    // Create parent "hand" event
    IOHIDEventRef handEvent = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        mach_absolute_time(),
        kIOHIDDigitizerTransducerTypeHand,
        0,    // index
        0,    // identity
        eventMask,
        0,    // buttonMask
        0, 0, // x, y
        0,    // z
        0, 0, // tipPressure, barrelPressure
        0,    // twist
        isTouching,
        isTouching,
        0     // options
    );

    // Create finger events for each touch
    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:touch.window];

        IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(
            kCFAllocatorDefault,
            mach_absolute_time(),
            index + 1,    // index
            2,            // identity
            eventMask,
            location.x,
            location.y,
            0,            // z
            0,            // tipPressure
            0,            // twist
            5.0,          // majorRadius
            5.0,          // minorRadius
            1.0,          // quality
            1.0,          // density
            1.0,          // irregularity
            isTouching,   // range
            isTouching,   // touch
            0             // options
        );

        IOHIDEventAppendEvent(handEvent, fingerEvent, 0);
    }

    return handEvent;
}
```

#### 4. Event Dispatch

```objc
// Simple wrapper that visualizes then sends
- (void)kif_sendEvent:(UIEvent *)event {
    [[KIFEventVisualizer sharedVisualizer] visualizeEvent:event];
    [self sendEvent:event];
}
```

### Private APIs Required

| API | Source | Purpose |
|-----|--------|---------|
| `[UIApplication _touchesEvent]` | UIApplication | Get singleton touch event |
| `[UIEvent _clearTouches]` | UIEvent | Reset event state |
| `[UIEvent _addTouch:forDelayedDelivery:]` | UIEvent | Add touch to event |
| `[UIEvent _setHIDEvent:]` | UIEvent | Attach IOHIDEvent |
| `[UITouch setWindow:]` | UITouch | Set touch window |
| `[UITouch setView:]` | UITouch | Set touch view |
| `[UITouch setPhase:]` | UITouch | Set touch phase |
| `[UITouch _setLocationInWindow:resetPrevious:]` | UITouch | Set coordinates |
| `[UITouch _setHidEvent:]` | UITouch | Set IOHIDEvent (iOS 9+) |
| `IOHIDEventCreateDigitizerEvent` | IOKit | Create HID container event |
| `IOHIDEventCreateDigitizerFingerEventWithQuality` | IOKit | Create finger event |
| `IOHIDEventAppendEvent` | IOKit | Add child to parent event |

### iOS 18 Hit Testing Changes

KIF also fixed hit testing for iOS 18 (PR #1323):

- iOS 18 introduced aggressive root view hit testing for SwiftUI
- Root view may capture all touch events, even for non-interactive areas
- Solution: Depth-based recursive hit testing to find the deepest interactive view

### Key Takeaways for Accra

1. **Fresh UIEvent per phase**: iOS 26 requires a new `UIEvent` for each touch phase (began, ended)

2. **IOHIDEvent is required**: For iOS 9+, UITouch objects need an internal IOHIDEvent set via `_setHidEvent:`

3. **Event creation flow**:
   - Get `_touchesEvent` from UIApplication
   - Clear existing touches
   - Create and attach IOHIDEvent
   - Add touch(es) to event
   - Send via `sendEvent:`

4. **Hit testing may need updates**: iOS 18+ has stricter hit testing for SwiftUI views

## Comparison: Accra vs KIF

| Aspect | Accra (Current) | KIF |
|--------|-----------------|-----|
| Touch creation | KVC on UITouch (unused) | Private UITouch setters |
| Event creation | None (uses high-level APIs) | `_touchesEvent` + `_addTouch:` |
| IOHIDEvent | Not used | Created and attached |
| Event dispatch | `accessibilityActivate()` / `sendActions()` | `sendEvent:` |
| iOS 26 handling | Disabled low-level path | Fresh event per phase |

## Implementation Recommendations

Based on KIF's approach, to fix iOS 26 tap issues:

1. **Implement proper UITouch creation** using private setters (not KVC)
2. **Create IOHIDEvent** and attach to UITouch via `_setHidEvent:`
3. **Use `_touchesEvent`** to get the event singleton
4. **Create fresh UIEvent for each phase** (began, ended)
5. **Dispatch via `sendEvent:`** instead of `accessibilityActivate()`

## Open Questions

1. **What specific scenarios fail on iOS 26?** The code mentions iOS 26 limitations but doesn't document which element types or view hierarchies fail.

2. **Is the unused private API code intentionally preserved?** The `simulateTouchOnView()` method exists but isn't called - unclear if this is for future use or should be removed.

3. **SwiftUI-only apps**: How well does `accessibilityActivate()` work for complex SwiftUI views like Lists, NavigationLinks, or custom button implementations?

4. **Simulator vs Device**: The iOS 26 notes specifically mention "Simulator" - are there different behaviors on physical devices?

5. **Error reporting**: When taps fail, the current diagnostic logging is minimal - users see "[TouchInjector] No tappable control found" without guidance on why.

## External References

- [KIF GitHub Repository](https://github.com/kif-framework/KIF)
- [KIF PR #1334 - iOS 26 tap fix](https://github.com/kif-framework/KIF/pull/1334)
- [KIF PR #1323 - iOS 18 hit testing fix](https://github.com/kif-framework/KIF/pull/1323)
- [Fixing Tap Interactions in iOS 18](https://medium.com/@adarsh.ranjan/fixing-tap-interactions-in-ios-18-understanding-and-resolving-the-root-view-hit-testing-issue-37c6c858e2d4)

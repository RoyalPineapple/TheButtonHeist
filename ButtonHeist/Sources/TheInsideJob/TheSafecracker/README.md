# TheSafecracker

Touch injection, text input, and gesture synthesis. Receives screen coordinates from TheBrains — never resolves element targets.

## Reading order

1. **`SyntheticTouch.swift`** — The three-stage touch pipeline, enforced at the type level:

   **`TouchTarget.resolve(at:in:)`** — hit-tests the window. On iOS 18+, uses `_UIHitTestContext` with `_hitTestWithContext:` to catch `UIKitGestureContainer` responders that standard `hitTest(_:with:)` misses. Stores the resolved `responder: AnyObject`.

   **`TouchTarget.makeTouch(phase:)`** — allocates `UITouch()` and configures it via 7 ObjC message sends: `setWindow:`, `setView:`, `_setLocationInWindow:resetPrevious:`, `setPhase:`, `setTapCount:`, timestamp. Returns a `SyntheticTouch` struct.

   **`TouchEvent(touches:)`** — retrieves the shared `UIEvent` via `_touchesEvent`, clears it, builds an `IOHIDEvent` via `IOHIDEventBuilder.createEvent(for:)`, attaches the HID event to both the UIEvent and each touch, adds touches via raw IMP call.

   **`TouchEvent.send()`** — `UIApplication.shared.sendEvent(event)`.

2. **`TheSafecracker+IOHIDEventBuilder.swift`** — Dynamically loads four IOKit functions via `dlopen`/`dlsym` on first use. Builds a parent "hand" digitizer event with child finger events. Each finger carries position, phase-derived event mask, `tipPressure: 1.0` while touching, `majorRadius: 5.0`.

3. **`ObjCRuntime.swift`** — All private API calls flow through `ObjCRuntime.Message`. The `message(_:to:)` factory validates the selector via `responds(to:)` before returning. `.call()` overloads use `perform(_:with:)` for object args and `unsafeBitCast` to typed IMP for value types.

4. **`TheSafecracker.swift`** — The `@MainActor final class`. Core primitives:
   - `touchesDown(at:)` / `moveTouches(to:)` / `touchesUp()` — N-finger versions that drive the pipeline
   - `tap(at:)` — touchDown → 50ms delay (`gestureYieldDelay`) → touchUp
   - `longPress(at:duration:)` — touchDown → loop of 10ms stationary events → touchUp
   - `swipe(from:to:duration:)` / `drag(...)` — pre-compute waypoints via linear interpolation, 10ms per step

   `windowForPoint(_:)` finds the frontmost non-overlay window whose `hitTest` succeeds, filtering out `TheFingerprints.FingerprintWindow` instances.

5. **`TheSafecracker+MultiTouch.swift`** — `pinch(center:scale:)`, `rotate(center:angle:)`, `twoFingerTap(at:spread:)`. All use `touchesDown(at: [p1, p2])` + interpolated `moveTouches(to:)` steps.

6. **`TheSafecracker+Scroll.swift`** — `scrollByPage(sv, direction:)` calls `setContentOffset(_:animated:)` for a full viewport jump. `scrollToEdge(sv, edge:)` sets offset to 0 or contentSize-bounds. `scrollToMakeVisible(frame:in:)` computes minimum offset to bring a rect into the comfort zone. `scrollBySwipe(frame:direction:)` — synthetic swipe fallback when no UIScrollView reference exists.

7. **`TheSafecracker+Actions.swift`** — `drawPath(points:duration:)` and `drawBezier(...)`. Draw path uses the touch pipeline with duration-derived step delay.

8. **`TheSafecracker+Bezier.swift`** — `BezierSampler.sampleBezierPath(startPoint:segments:samplesPerSegment:)` evaluates cubic bezier curves at evenly-spaced t values.

9. **`KeyboardBridge.swift`** — Wraps `UIKeyboardImpl` private API. `shared()` resolves via `ObjCRuntime.classMessage("sharedInstance", on: "UIKeyboardImpl")`. `type(_:)` calls `addInputString:` then `drainTaskQueue()` (waits on the impl's task queue to prevent character drops). `deleteBackward()` calls `deleteFromInput`. `hasActiveInput` checks `delegate is UIKeyInput`.

10. **`TheFingerprints.swift`** — Visual feedback overlay. `FingerprintWindow` is a passthrough UIWindow at `.statusBar + 100` filtered out of accessibility traversal and hit-testing via `is FingerprintWindow` checks. `showFingerprint(at:)` creates a 40pt white circle, holds 0.5s, fades 0.5s. `beginTrackingFingerprints` / `updateTrackingFingerprints` / `endTrackingFingerprints` manage continuous gesture indicators. Disabled via `INSIDEJOB_DISABLE_FINGERPRINTS` env var.

## How a tap flows end-to-end

```
safecracker.tap(at: point)
  → touchesDown(at: [point])
    → windowForPoint(point)                    // frontmost non-overlay window
    → TouchTarget.resolve(at: point, in: window)  // hit test + _UIHitTestContext
    → target.makeTouch(phase: .began)          // UITouch + 7 ObjC messages
    → TouchEvent(touches: [syntheticTouch])    // IOHIDEvent via dlsym'd IOKit
    → event.send()                             // UIApplication.shared.sendEvent
  → Task.cancellableSleep(50ms)               // gesture recognizer run-loop time
  → touchesUp()
    → touch.update(phase: .ended)
    → TouchEvent → send()
```

> Full dossiers: [`docs/dossiers/14-THESAFECRACKER.md`](../../../../docs/dossiers/14-THESAFECRACKER.md), [`docs/dossiers/17-THEFINGERPRINTS.md`](../../../../docs/dossiers/17-THEFINGERPRINTS.md)

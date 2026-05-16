# TheSafecracker Deep Dive: Touch Injection

> **Source:** `ButtonHeist/Sources/TheInsideJob/TheSafecracker/` — `SyntheticTouch.swift`, `ObjCRuntime.swift`, `TheSafecracker+IOHIDEventBuilder.swift`, `TheSafecracker.swift`, `TheSafecracker+MultiTouch.swift`, `TheSafecracker+Bezier.swift`
> **Parent dossier:** [14-THESAFECRACKER.md](14-THESAFECRACKER.md)

TheSafecracker injects synthetic touch events by constructing the same data structures the real hardware stack produces — IOHIDEvents from IOKit, UITouch objects mutated via private ObjC selectors, and UIEvents delivered through `UIApplication.sendEvent`. This is the same technique used by the KIF testing framework.

## The 3-Layer Pipeline

Every gesture — tap, swipe, pinch, draw — flows through the same three layers:

```
Layer 1: TouchTarget     — hit test resolution (which view receives the touch?)
Layer 2: SyntheticTouch   — UITouch creation and mutation (private API)
Layer 3: TouchEvent       — IOHIDEvent assembly + UIEvent delivery
```

### Layer 1: TouchTarget (hit test resolution)

`SyntheticTouch.swift` — `TouchTarget` is a struct holding `window: UIWindow`, `windowPoint: CGPoint`, and `responder: AnyObject`.

**`resolve(at:in:)`** converts a screen-coordinate point to window coordinates, then calls `resolveHitTestTarget` to find the gesture recipient.

**`resolveHitTestTarget`** has two paths:

1. **Standard (all iOS versions):** `window.hitTest(windowPoint, with: nil)` — UIKit's built-in hit testing. Returns the deepest view in the hierarchy whose bounds contain the point and whose `isUserInteractionEnabled` is true.

2. **iOS 18+ SwiftUI fix:** SwiftUI routes gesture handling through `UIKitGestureContainer` (a `UIResponder`, not a `UIView`). Standard `hitTest` returns the rendering leaf view, which ignores touches. The fix:
   - Creates a `_UIHitTestContext` via `ObjCRuntime.classMessage("contextWithPoint:radius:", on: "_UIHitTestContext")`
   - Walks up the superview chain from the standard hit view, calling `_hitTestWithContext:` on each ancestor
   - Returns the first non-nil result — typically the `UIKitGestureContainer` that owns the SwiftUI gesture recognizer

If any step of the iOS 18 path fails (wrong OS, private API removed), falls back to the standard hit view.

### Layer 2: SyntheticTouch (UITouch mutation)

`SyntheticTouch.swift` — `SyntheticTouch` wraps a `UITouch` with tracked `location` and `phase`.

**`TouchTarget.makeTouch(phase:)`** creates a `UITouch()` via public API, then mutates it entirely through private ObjC selectors dispatched via `ObjCRuntime.Message`:

| Selector | What it sets | Dispatch path |
|----------|-------------|---------------|
| `setWindow:` | Target window | `call(_ arg: AnyObject)` |
| `setView:` | Hit view / responder | `call(_ arg: AnyObject)` |
| `setGestureView:` | Gesture routing target | `call(_ arg: AnyObject)` |
| `_setLocationInWindow:resetPrevious:` | CGPoint + reset flag | IMP `(CGPoint, Bool)` |
| `setPhase:` | Touch phase raw value | IMP `(Int)` |
| `setTapCount:` | Always 1 | IMP `(Int)` |
| `_setIsFirstTouchForView:` | First touch flag | IMP `(Bool)` |
| `setIsTap:` | Tap flag | IMP `(Bool)` |
| `setTimestamp:` | `ProcessInfo.systemUptime` | IMP `(Double)` |

**Update methods** for multi-step gestures:
- `update(phase:)` — refreshes phase + timestamp (timestamp refresh is critical for iOS 26)
- `update(location:)` — calls `_setLocationInWindow:resetPrevious:` with `resetPrevious: false` (preserves previous location for delta calculation)
- `update(phase:location:)` — both in one call
- `setHIDEvent(_:)` — attaches the IOHIDEvent pointer via `_setHidEvent:`

### Layer 3: TouchEvent (IOHIDEvent + UIEvent delivery)

`SyntheticTouch.swift` + `TheSafecracker+IOHIDEventBuilder.swift`

**`TouchEvent(touches:)`** assembles and delivers the event:

1. Gets the application's preallocated touches event: `UIApplication.shared._touchesEvent` (unretained)
2. Clears it: `event._clearTouches`
3. Builds the IOHIDEvent tree via `IOHIDEventBuilder.createEvent(for:)` (see below)
4. Attaches HID data: `event._setHIDEvent:` on the UIEvent, `_setHidEvent:` on each UITouch
5. Adds each touch: `_addTouch:forDelayedDelivery:` (mixed object+value argument, requires IMP escape hatch)
6. **`send()`**: `UIApplication.shared.sendEvent(event)` — the terminus

**IOHIDEventBuilder** constructs the IOKit event tree. All four IOKit functions are loaded dynamically via `dlsym` at first use — never linked at compile time:

```
dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
dlsym → IOHIDEventCreateDigitizerEvent
dlsym → IOHIDEventCreateDigitizerFingerEventWithQuality
dlsym → IOHIDEventAppendEvent
dlsym → IOHIDEventSetFloatValue
```

**`createEvent(for:)`** builds a two-level tree:

1. **Hand event** (parent): `IOHIDEventCreateDigitizerEvent` with `transducerType = kIOHIDDigitizerTransducerTypeHand (3)`. The `range` and `touch` bools are true if any finger is touching.

2. **Finger events** (children): One per finger via `IOHIDEventCreateDigitizerFingerEventWithQuality`. Each finger gets:
   - `index = arrayIndex + 1` (1-based position slot)
   - `identity = arrayIndex + 2` (stable finger ID: finger 0 → 2, finger 1 → 3)
   - `tipPressure = 1.0` while touching, `0` when ended
   - `majorRadius = minorRadius = 5.0` (matching KIF)
   - `quality = density = irregularity = 1.0`
   - `eventMask`: `Range|Touch` for began/ended/cancelled, `Position` for moved/stationary
   - `kIOHIDEventFieldDigitizerIsDisplayIntegrated = 1.0`

3. Each finger is appended to the hand: `IOHIDEventAppendEvent(hand, finger, 0)`

### iOS 26 fresh-event-per-phase fix

iOS 26 added validation that rejects reused UIEvent objects across touch phases. The fix: `TouchEvent(touches:)` is called fresh before every `send()` — in `touchesDown`, `moveTouches`, `sendStationary`, and `touchesUp`. No UIEvent instance is retained between phases.

## ObjCRuntime — Private API Dispatch

`ObjCRuntime.swift` provides nil-safe wrappers around private ObjC selector dispatch:

- `ObjCRuntime.message(_:to:)` — resolves selector via `NSSelectorFromString`, checks `responds(to:)`, returns `Message?`
- `ObjCRuntime.classMessage(_:on:)` — resolves a private class via `NSClassFromString`, then delegates to `message`
- `Message.call()` overloads — dispatch for void, object, Int, Bool, Double, pointer, and CGPoint+Bool arguments
- `Message.imp(as:)` — raw IMP escape hatch for mixed-type arguments that don't fit any `call` overload

All IMP extraction uses `target.method(for:)` + `unsafeBitCast` to typed `@convention(c)` function pointers. The five IMP typealiases follow the ObjC ABI: first two arguments are always `(AnyObject, Selector)`.

Every call site is crash-safe: if the selector doesn't exist on the target, `message` returns nil and the calling code falls back or returns false.

## The N-Finger Primitive Layer

All gestures share four building blocks in `TheSafecracker.swift`:

| Method | What it does |
|--------|-------------|
| `touchesDown(at: [CGPoint])` | Finds the target window, creates `TouchTarget` + `SyntheticTouch` per finger, sends `.began` event |
| `moveTouches(to: [CGPoint])` | Updates each finger's location + phase to `.moved`, sends event |
| `sendStationary()` | Updates all fingers to `.stationary` (no location change), sends event (**private**) |
| `touchesUp()` | Updates all fingers to `.ended`, sends event, clears state |

Single-finger convenience wrappers (`touchDown`, `moveTo`, `touchUp`) call the array versions with a one-element array.

**`windowForPoint(_:)`** finds the target window by iterating `TheTripwire.orderedVisibleWindows()` frontmost first and returning the first window that passes `hitTest`.

**`activeTouches`** stores the `[SyntheticTouch]` array for the gesture's lifetime. `moveTouches` enforces `points.count == activeTouches.count`. Because `TheSafecracker` is `@MainActor`, all gesture methods are actor-serialized — no concurrent touch state conflicts.

## Gesture Implementations

### Single-finger tap

```
touchDown(at: point)           → .began event
Task.sleep(50ms)               → gestureYieldDelay
touchUp()                      → .ended event
```

The 50ms `gestureYieldDelay` between `.began` and `.ended` exists because SwiftUI gesture recognizers process events asynchronously. The main run loop needs time to transition a recognizer from "possible" to "recognized" before the lift occurs. Without this delay, SwiftUI buttons don't register taps.

### Long press

```
touchDown(at: point)           → .began event
while elapsed < duration:
    Task.sleep(10ms)
    sendStationary()           → .stationary events at 10ms intervals
touchUp()                      → .ended event
```

Default duration: 0.5s. Stationary events keep the touch alive so the system doesn't time it out.

### Swipe and drag

Both pre-compute the full waypoint array before entering the gesture loop (KIF's `dragPointsAlongPaths` pattern — ensures path stability even if the view moves during execution):

```
touchDown(at: start)           → .began event
for each waypoint:
    moveTo(waypoint)           → .moved event
    Task.sleep(10ms)
touchUp()                      → .ended event
```

Waypoints use linear interpolation: `start + progress * (end - start)` for each step.

| Gesture | Min steps | Step formula | Default duration |
|---------|-----------|-------------|-----------------|
| swipe | 3 | `max(Int(duration / 0.01), 3)` | 0.15s → 15 steps |
| drag | 5 | `max(Int(duration / 0.01), 5)` | 0.5s → 50 steps |

### Draw path (polyline)

Arc-length parameterized interpolation across multi-segment polylines. Pre-computes per-segment Euclidean lengths and total length, then for each step computes `targetDist = progress * totalLength`, walks the segment list accumulating distance until the target segment is found, and lerps within that segment. Result: uniform speed across the path regardless of segment length variations.

Degeneracy: returns `false` early if `points.count < 2`. If `totalLength == 0` (all points identical), dispatches `touchDown` + `touchUp` (no yield between phases, unlike a full tap which includes `gestureYieldDelay`).

Steps: `max(Int(duration / 0.01), points.count)`.

### Draw bezier

`BezierSampler` (in `TheSafecracker+Bezier.swift`) converts cubic Bezier segments to a polyline using the standard Bernstein polynomial, then hands off to `drawPath`:

- `sampleCubicBezier(p0:p1:p2:p3:sampleCount:)` — evaluates the cubic at `count` evenly-spaced `t` values
- `sampleBezierPath(startPoint:segments:samplesPerSegment:)` — chains segments, dropping duplicate junction points
- Default 20 samples per segment, clamped to max 1000 per segment at the executor

### Pinch

Two fingers on a 45-degree diagonal axis, both always diametrically opposite through the center:

```
finger1 = center + (cos(π/4), sin(π/4)) * spread
finger2 = center - (cos(π/4), sin(π/4)) * spread
```

Each step interpolates `currentSpread = startSpread + progress * (endSpread - startSpread)` where `endSpread = spread * scale`. Scale > 1.0 = zoom in (spread), scale < 1.0 = zoom out (pinch).

Steps: `max(Int(duration / 0.01), 5)`. Default duration: 0.5s.

### Rotate

Two fingers orbiting the center at constant radius, 180 degrees apart:

```
finger1 = center + (cos(angle), sin(angle)) * radius
finger2 = center + (cos(angle + π), sin(angle + π)) * radius
```

Each step interpolates `currentAngle = startAngle + progress * angle`. Positive angle = counter-clockwise (standard math convention). Start angle is always 0.

Steps: same as pinch.

### Two-finger tap

Two fingers horizontally centered, separated by `spread` (default 40pt):

```
finger1 = (center.x - spread/2, center.y)
finger2 = (center.x + spread/2, center.y)

touchesDown(at: [finger1, finger2])    → .began event
Task.sleep(50ms)                        → gestureYieldDelay (same as single tap)
touchesUp()                             → .ended event
```

## Timing Constants

| Constant | Value | Used by |
|----------|-------|---------|
| `gestureYieldDelay` | 50ms | tap, twoFingerTap — between .began and .ended |
| step delay | 10ms | swipe, drag, drawPath, pinch, rotate, longPress — between movement steps |
| `defaultGestureDuration` | 0.5s | fallback when no duration specified |
| `minGestureDuration` | 10ms | lower clamp |
| `maxGestureDuration` | 60s | upper clamp (prevents runaway gestures) |

`clampDuration(_:)` enforces `min(max(value ?? 0.5, 0.01), 60.0)`.

`resolveDuration(_:velocity:points:)` supports velocity-based duration: if `velocity > 0`, computes total path length and divides by velocity. Used by `drawPath` and `drawBezier`.

## Multi-Touch Finger Identity

IOHIDEvent identifies fingers by two numbers:
- **index** (1-based): position slot in the current gesture — finger 0 gets index 1, finger 1 gets index 2
- **identity** (2-based): stable finger ID across the gesture lifetime — finger 0 gets identity 2, finger 1 gets identity 3

These are separate parameters to `IOHIDEventCreateDigitizerFingerEventWithQuality`. The identity stays constant across all phases for a given finger, which is how the system tracks which finger is which during moves.

## Requirements

- **DEBUG builds only.** All touch injection code is wrapped in `#if DEBUG`. This is not shipped in release builds.
- **IOKit framework present.** The four IOKit symbols must be resolvable via `dlsym`. If IOKit reorganizes or removes them, touch injection silently fails (returns false from gesture methods).
- **Private UIKit selectors present.** All UITouch mutation, UIEvent access, and hit test context use private selectors guarded by `responds(to:)`. Missing selectors cause graceful fallback or failure, never crashes.
- **Main actor.** All gesture methods are `@MainActor` — UIKit touch processing must happen on the main thread.

## Limitations

- **Private API surface.** The entire stack depends on undocumented ObjC selectors and IOKit symbols. Apple can change or remove any of them. The `responds(to:)` guards protect against missing selectors but not against signature changes — an `unsafeBitCast` to the wrong IMP type would crash.
- **No multi-touch beyond 2 fingers.** The N-finger primitives support any count, but no gesture method currently uses more than 2. Three-finger gestures (screenshot, app switcher) are not implemented.
- **SwiftUI hit test path is heuristic.** The `_hitTestWithContext:` superview walk finds the first responder, not necessarily the correct one if multiple overlapping SwiftUI gesture recognizers exist.
- **No force touch / 3D Touch.** `tipPressure` is hardcoded to 1.0 (touching) or 0 (not touching). Pressure-sensitive gestures are not supported.
- **Timing is best-effort.** `Task.sleep` granularity depends on system load. The 10ms step delay and 50ms yield delay are targets, not guarantees.

# SwiftUI Synthetic Touch Injection — FIXED

## Summary

Synthetic touch injection via `TheSafecracker` didn't work on any SwiftUI view. All touch types failed silently — taps, long presses, swipes. UIKit/Blueprint views worked fine.

**Status**: Fixed. The root cause was a type-casting bug in the `_UIHitTestContext` hit test resolution.

## Root Cause

### The problem chain

1. `touchesDown(at:)` calls `window.hitTest(point, with: nil)` to find the touch target
2. On SwiftUI screens, `hitTest` returns `SwiftUI.CGDrawingView` — a rendering leaf that doesn't handle gestures
3. Touch events sent to `CGDrawingView` are silently ignored by SwiftUI's gesture system

### The iOS 18 solution

iOS 18 introduced `_UIHitTestContext` and `_hitTestWithContext:` for SwiftUI gesture routing (KIF fixed this in v3.11.2, PR #1323). The `_UIHostingView` responds to `_hitTestWithContext:` and returns `SwiftUI.UIKitGestureContainer` — the actual gesture target.

### The subtle bug

`UIKitGestureContainer` is a `UIResponder` subclass, **NOT** a `UIView`. It responds to UIView selectors (`setView:`, `setGestureView:`) via ObjC dynamic dispatch, but fails Swift's `as? UIView` type check.

Our initial implementation used:
```swift
if let resultView = result as? UIView {  // ← silently returns nil!
    return resultView
}
```

### The fix

Store the hit test result as `AnyObject` throughout the pipeline — never cast to `UIView`. The `TouchTarget.responder` field holds the raw result from `_hitTestWithContext:`, and it flows through to `UITouch.setView:` and `setGestureView:` via ObjC messaging (`ObjCRuntime.message(...).call(responder)`). Since these selectors accept any `NSObject` at the ObjC level, no cast is needed.

## View hierarchy (debugger trace)

```
SwiftUI.CGDrawingView                    ← hitTest returns this (rendering leaf)
  PlatformGroupContainer
    HostingScrollView
      PlatformContainer
        _UIHostingView<MDatePickerDemoView>  ← _hitTestWithContext: returns UIKitGestureContainer from HERE
          MarketNavigation.ContentView
            MarketNavigation.View
              UIView
                UIView
                  PagingView.ContainerView
                    ...
                      UIWindow
```

## Files changed

| File | Change |
|------|--------|
| `SyntheticTouch.swift` | New. Type-safe pipeline: `TouchTarget.resolve` → `SyntheticTouch` → `TouchEvent`. Hit test resolution with `_UIHitTestContext`, `AnyObject` responder throughout |
| `ObjCRuntime.swift` | New. Reusable ObjC message dispatch with typed `call()` overloads |
| `TheSafecracker.swift` | Touch primitives now use pipeline. Extracted `gestureYieldDelay` constant. Keyboard methods use ObjCRuntime |
| `TheSafecracker+MultiTouch.swift` | `twoFingerTap` now async with gesture yield |
| `TheSafecracker+Actions.swift` | `executeTwoFingerTap` now async |
| `TheInsideJob+Dispatch.swift` | `await` on twoFingerTap dispatch |
| `TheSafecracker+TextEntry.swift` | `await tap(at:)` |

## Key lesson

When working with Apple's private APIs across Swift/ObjC boundaries, `as? UIView` is not equivalent to ObjC's `isKindOfClass:UIView`. SwiftUI's internal types (`UIKitGestureContainer`) implement UIView-compatible ObjC interfaces without actually inheriting from `UIView`. The safest approach is to keep private API results as `AnyObject` and pass them through ObjC messaging — never cast to a Swift type that the runtime object doesn't actually inherit from.

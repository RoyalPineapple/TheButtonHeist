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

The fix uses:
```swift
return unsafeBitCast(result, to: UIView.self)  // ← works because ObjC doesn't care
```

This is safe because `UITouch.setView:` and `setGestureView:` accept any `NSObject` via ObjC messaging — they don't actually require a `UIView` despite the method signature suggesting otherwise. **The poorly-named `setView:` API is what enables this to work.**

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
| `TheSafecracker.swift` | Added `resolveHitTestView(in:at:)` with `_UIHitTestContext` pathway, `setGestureView` on touch, async `tap(at:)` with 50ms yield |
| `TheSafecracker+SyntheticTouchFactory.swift` | Added `setGestureView(_:view:)` |
| `TheSafecracker+Actions.swift` | `executeActivate` and `executeTap` now async |
| `TheInsideJob+Dispatch.swift` | Added `await` to activate and tap dispatch closures |
| `TheSafecracker+TextEntry.swift` | `await tap(at:)` |

## Key lesson

When working with Apple's private APIs across Swift/ObjC boundaries, `as? UIView` is not equivalent to ObjC's `isKindOfClass:UIView`. SwiftUI's internal types (`UIKitGestureContainer`) implement UIView-compatible ObjC interfaces without actually inheriting from `UIView`. Always use `unsafeBitCast` when the target API uses ObjC messaging (like `UITouch.setView:`).

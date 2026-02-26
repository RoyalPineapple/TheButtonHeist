# ThePlant - Performance Improvement Plan

## Summary

Minor cleanup: replace `@_cdecl` with `@objc` class method for clarity. No major changes needed.

## Phase 1: Replace @_cdecl with @objc Class Method

**Goal:** Use the standard, well-documented pattern instead of `@_cdecl`.

### Current:
```swift
// InsideJob+AutoStart.swift
@_cdecl("InsideJob_autoStartFromLoad")
public func insideJobAutoStartFromLoad() { ... }

// ThePlantAutoStart.m
+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        InsideJob_autoStartFromLoad();
    });
}
```

### New:
```swift
// InsideJob+AutoStart.swift
@objc public class InsideJobAutoStarter: NSObject {
    @objc public static func autoStart() { ... }
}

// ThePlantAutoStart.m
#import "ButtonHeist-Swift.h"
+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [InsideJobAutoStarter autoStart];
    });
}
```

- [ ] **Replace `@_cdecl` function** with `@objc` class `InsideJobAutoStarter`
- [ ] **Update `ThePlantAutoStart.m`** to call `[InsideJobAutoStarter autoStart]`
- [ ] **Verify app still auto-starts** InsideJob on framework load
- [ ] **Build passes**

## Phase 2: No Other Changes

- `+load` timing is fine (confirmed by review)
- ThePlant's dependency on InsideJob is required and correct

## Verification

- [ ] `@_cdecl` removed from codebase
- [ ] `@objc` class method used instead
- [ ] App still auto-starts InsideJob on framework load
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp -destination 'platform=iOS Simulator,name=iPhone 16' build`

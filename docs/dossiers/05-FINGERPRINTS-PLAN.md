# Fingerprints → TheFingerprints - Performance Improvement Plan

## Summary

Rename to TheFingerprints. Enforce minimum 0.5s display time for all indicators. Eliminate the need for CGContext compositing in TheStakeout by keeping indicators visible long enough for frame capture.

## Phase 1: Rename to TheFingerprints

- [x] **Rename class** from `Fingerprints` to `TheFingerprints`
- [x] **Update references in `InsideJob.swift`**
- [x] **Update references in `TheSafecracker.swift`**
- [x] **Update references in `Stakeout.swift`**
- [x] **Build passes** after phase

## Phase 2: Enforce Minimum Display Duration

**All types:** minimum 0.5s fully visible, then 0.5s fade-out.

```swift
private static let minimumDisplayDuration: TimeInterval = 0.5
private static let fadeOutDuration: TimeInterval = 0.5
```

- [x] **Tap:** 0.5s visible → 0.5s fade (1.0s total)
- [x] **Long press:** visible for duration (min 0.5s) → 0.5s fade
- [x] **Swipe/drag:** visible for duration → 0.5s fade
- [x] **Pinch/rotate:** visible for duration → 0.5s fade
- [x] **Build passes** after phase

## Phase 3: Coordinate with TheStakeout on Compositing Elimination

- [ ] **Guarantee indicators on-screen >= 0.5s**
- [ ] **Verify >= 4 frames at 8fps** for natural capture
- [ ] **Optional: add `onFingerprintReady?()` closure** if needed

## Phase 4: Add Configuration to Disable Fingerprints

- [x] **Add env var:** `INSIDEJOB_DISABLE_FINGERPRINTS`
- [x] **Add plist key:** `InsideJobDisableFingerprints`
- [x] **No-op when disabled**

## Phase 5: Passthrough Window Accessibility

- [ ] **Set `isAccessibilityElement = false`** on `FingerprintWindow`
- [ ] **Set `accessibilityElementsHidden = true`** on `FingerprintWindow`
- [ ] **Remove explicit `FingerprintWindow` filter** in `getTraversableWindows()` if no longer needed
- [ ] **Build passes** after phase

## Verification

- [x] Class renamed to `TheFingerprints`
- [x] All indicators visible for minimum 0.5s before fade
- [x] Fade-out duration is 0.5s for all indicator types
- [x] `INSIDEJOB_DISABLE_FINGERPRINTS` env var supported
- [ ] Passthrough window has `accessibilityElementsHidden = true`
- [ ] No compositing code references TheFingerprints
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build`

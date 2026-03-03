# Fingerprints - The Evidence

> **File:** `ButtonHeist/Sources/TheInsideJob/TheFingerprints.swift`
> **Platform:** iOS 17.0+ (UIKit)
> **Role:** Visual touch indicators - shows where interactions happen, composited into recordings

## Responsibilities

Fingerprints provides visual feedback for all touch interactions:

1. **Passthrough overlay window** at window level `statusBar + 100`
2. **Instant fingerprints** for taps - 40pt white circle, scales 1.5x and fades over 0.8s
3. **Continuous tracking** for swipes/drags/pinches - multi-finger circles that follow touch
4. **Recording integration** - positions reported to Stakeout for video frame compositing
5. **Accessibility exclusion** - window excluded from hierarchy traversal

## Architecture Diagram

```mermaid
graph TD
    subgraph FingerprintSystem["Fingerprints"]
        Window["FingerprintWindow - UIWindow, hitTest → nil always - windowLevel: statusBar + 100"]
        InstantFP["Instant Fingerprints - showFingerprint(at:)"]
        TrackingFP["Continuous Tracking - begin/update/endTracking"]
    end

    subgraph Visual["Visual Properties"]
        Circle["40pt white circle - cornerRadius: 20 - alpha: 0.8"]
        AnimIn["Animate in: 0.12s - scale 0.1 → 1.0"]
        AnimOut["Animate out: 0.6-0.8s - scale 1.0 → 1.5, alpha → 0"]
    end

    subgraph Consumers["Consumers"]
        Safecracker["TheSafecracker - calls show/begin/update/end"]
        StakeoutComp["Stakeout - composites circles into video frames"]
        Hierarchy["TheInsideJob+Accessibility - excludes window from traversal"]
    end

    Safecracker --> InstantFP
    Safecracker --> TrackingFP
    InstantFP --> Window
    TrackingFP --> Window
    TrackingFP -->|positions| StakeoutComp
    Window -.->|excluded| Hierarchy
```

## Interaction Types

```mermaid
flowchart LR
    subgraph Instant["Instant (Tap/Activate)"]
        TapShow["showFingerprint(at:)"]
        TapAnim["Scale 1.0→1.5 - Alpha 1.0→0 - Duration: 0.8s"]
        TapShow --> TapAnim
    end

    subgraph Continuous["Continuous (Swipe/Drag/Pinch/Rotate/LongPress)"]
        Begin["beginTrackingFingerprints - Create circle views per finger"]
        Update["updateTrackingFingerprints - Move circles to new positions"]
        End["endTrackingFingerprints - Animate out + remove"]
        Begin --> Update --> End
    end

    subgraph Recording["In Recording Frames"]
        Positions["Active positions with timestamps"]
        Fade["0.5s fade-out in CGContext"]
        Composite["40pt circle drawn Y-flipped"]
        Positions --> Fade --> Composite
    end
```

## Items Flagged for Review

### LOW PRIORITY

**No configuration to disable fingerprints**
- Every interaction shows visual feedback
- For automated testing at high speed, the overlay animations may add slight overhead
- Not configurable via any env var or plist key

**Y-flip required for CGContext compositing in Stakeout**
- CGContext has origin at bottom-left, UIKit at top-left
- The Y-flip transform in Stakeout's fingerprint drawing is correct but non-obvious
- Worth verifying if device rotation is ever supported

**Passthrough window always in the hierarchy**
- `FingerprintWindow` is created and added to the scene
- Even when no fingerprints are showing, the window exists
- It's excluded from accessibility traversal via `getTraversableWindows()` filter

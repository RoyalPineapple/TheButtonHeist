# Fingerprints - The Evidence

> **File:** `ButtonHeist/Sources/TheInsideJob/TheSafecracker/TheFingerprints.swift`
> **Platform:** iOS 17.0+ (UIKit)
> **Role:** Visual touch indicators - shows where interactions happen, included in recordings

## Responsibilities

Fingerprints provides visual feedback for all touch interactions:

1. **Passthrough overlay window** at window level `statusBar + 100`
2. **Instant fingerprints** for taps - 40pt white circle, holds for 0.5s then fades out over 0.5s
3. **Continuous tracking** for swipes/drags/pinches - multi-finger circles that follow touch; on end, scales 1.5x and fades out over 0.5s
4. **Recording integration** - FingerprintWindow is drawn with all windows in captureScreenForRecording(), so recordings include the overlay
5. **Accessibility exclusion** - window excluded from hierarchy traversal
6. **DEBUG-only** - entire class is inside `#if DEBUG` (and `#if canImport(UIKit)`)

## Architecture Diagram

```mermaid
graph TD
    subgraph FingerprintSystem["Fingerprints"]
        Window["FingerprintWindow - UIWindow, hitTest → nil always - windowLevel: statusBar + 100"]
        InstantFP["Instant Fingerprints - showFingerprint(at:)"]
        TrackingFP["Continuous Tracking - begin/update/endTracking"]
    end

    subgraph Visual["Visual Properties"]
        Circle["40pt white circle - cornerRadius: 20 - alpha: 0.5"]
        AnimIn["Animate in: 0.12s - scale 0.1 → 1.0"]
        AnimOut["Fade out: 0.5s - alpha → 0 (instant)\nScale 1.0 → 1.5 + fade 0.5s (continuous end)"]
    end

    subgraph Consumers["Consumers"]
        Safecracker["TheSafecracker - calls show/begin/update/end"]
        Capture["captureScreenForRecording - draws all windows incl. FingerprintWindow"]
        Hierarchy["TheInsideJob+Accessibility - excludes window from traversal"]
    end

    Safecracker --> InstantFP
    Safecracker --> TrackingFP
    InstantFP --> Window
    TrackingFP --> Window
    Window -.->|drawn by| Capture
    Window -.->|excluded| Hierarchy
```

## Interaction Types

```mermaid
flowchart LR
    subgraph Instant["Instant (Tap/Activate)"]
        TapShow["showFingerprint(at:)"]
        TapAnim["Hold 0.5s then fade - Alpha 1.0→0 - Duration: 0.5s"]
        TapShow --> TapAnim
    end

    subgraph Continuous["Continuous (Swipe/Drag/Pinch/Rotate/LongPress)"]
        Begin["beginTrackingFingerprints - Create circle views per finger"]
        Update["updateTrackingFingerprints - Move circles to new positions"]
        End["endTrackingFingerprints - Animate out + remove"]
        Begin --> Update --> End
    end

    subgraph Recording["In Recordings"]
        DrawAll["captureScreenForRecording draws all windows"]
        Include["FingerprintWindow included in drawHierarchy"]
        DrawAll --> Include
    end
```

## Items Flagged for Review

### LOW PRIORITY

**Fingerprints can be disabled via configuration**
- Set `INSIDEJOB_DISABLE_FINGERPRINTS=1` (env var) or `InsideJobDisableFingerprints=true` (Info.plist) to suppress all visual feedback
- When disabled, all `showFingerprint` / `beginTrackingFingerprints` / `updateTrackingFingerprints` / `endTrackingFingerprints` calls are no-ops
- Useful for automated testing at high speed where overlay animations add overhead

**Fingerprints captured via drawHierarchy**
- captureScreenForRecording() draws all windows (including FingerprintWindow)
- No separate CGContext compositing; the overlay is captured when visible at frame capture time

**Passthrough window always in the hierarchy**
- `FingerprintWindow` is created and added to the scene
- Even when no fingerprints are showing, the window exists
- It's excluded from accessibility traversal via `getTraversableWindows()` filter

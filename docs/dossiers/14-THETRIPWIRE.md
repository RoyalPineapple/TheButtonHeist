# TheTripwire - The Timing Coordinator

> **File:** `ButtonHeist/Sources/TheInsideJob/TheTripwire.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Centralized timing coordinator — gates all "is the UI ready?" decisions for TheInsideJob

## Responsibilities

TheTripwire is the timing coordinator for TheInsideJob. Every path that reads or broadcasts the accessibility tree goes through TheTripwire first to ensure the UI is stable.

1. **Window access** - returns the active scene's visible, non-overlay windows sorted by level (`getTraversableWindows()`)
2. **View controller identity** - walks the VC hierarchy (presented, nav, tab, children) to find the topmost visible VC (`topmostViewController()`)
3. **Screen change detection (VC identity)** - compares `ObjectIdentifier` snapshots of the topmost VC before/after an action (`isScreenChange()`). This is the primary gate; TheBagman supplements with topology-based detection for cases where the VC is reused (e.g., Workflow-style navigation)
4. **Synchronous animation gate** - cheap DFS check for active `CAAnimation` keys, filtering out persistent system animations like `_UIParallaxMotionEffect` (`allClear()`)
5. **Presentation layer fingerprinting** - sums `CALayer` presentation positions and opacities across all windows to detect movement (`PresentationFingerprint`)
6. **Unified settle wait** - async wait using `CADisplayLink` (vsync-synced) until presentation layers stop moving, requiring 2 consecutive quiet frames (`waitForAllClear(timeout:)`)

## Architecture Diagram

```mermaid
graph TD
    subgraph TheTripwire["TheTripwire (@MainActor, internal)"]
        subgraph Windows["Window Access"]
            GetWindows["getTraversableWindows()"]
        end

        subgraph VCIdentity["View Controller Identity"]
            TopVC["topmostViewController()"]
            DeepVC["deepestViewController(from:)"]
            ScreenChange["isScreenChange(before:after:)"]
        end

        subgraph TimingGate["Timing Gate"]
            AllClear["allClear() → Bool (sync)"]
            IgnoredPrefixes["ignoredAnimationKeyPrefixes"]
        end

        subgraph Fingerprint["Presentation Layer Fingerprinting"]
            TakeFP["takePresentationFingerprint()"]
            FPStruct["PresentationFingerprint"]
        end

        subgraph Settling["Unified Settle"]
            WaitAllClear["waitForAllClear(timeout:)"]
            DisplayLink["DisplayLinkObserver (CADisplayLink)"]
        end
    end

    Polling["checkForChanges()"] -->|"allClear()"| AllClear
    Debounce["broadcastHierarchyUpdate()"] -->|"waitForAllClear(0.25)"| WaitAllClear
    SendIF["sendInterface()"] -->|"waitForAllClear(0.5)"| WaitAllClear
    ActionResult["actionResultWithDelta()"] -->|"waitForAllClear(1.0)"| WaitAllClear
    WaitIdle["handleWaitForIdle()"] -->|"waitForAllClear(timeout)"| WaitAllClear
```

## View Controller Walk

```mermaid
flowchart TD
    Root["rootViewController from first window"]
    Root --> Presented{has presentedVC?}
    Presented -->|yes| Recurse1["deepestViewController(presented)"]
    Presented -->|no| IsNav{is UINavigationController?}
    IsNav -->|yes| NavTop["deepestViewController(topVC)"]
    IsNav -->|no| IsTab{is UITabBarController?}
    IsTab -->|yes| TabSel["deepestViewController(selectedVC)"]
    IsTab -->|no| Children["Check children for nav/tab"]
    Children --> Deepest["Return VC"]
```

## waitForAllClear Flow

```mermaid
flowchart TD
    Start["waitForAllClear(timeout)"]
    Start --> Sleep["30ms initial delay (SwiftUI run loop tick)"]
    Sleep --> InitFP["Take initial fingerprint"]
    InitFP --> DL["Start CADisplayLink (~10 Hz)"]
    DL --> Frame["onFrame callback (vsync)"]
    Frame --> FPCompare{"fingerprint matches\nprevious?"}
    FPCompare -->|yes| FPQuiet["quietFrames += 1"]
    FPCompare -->|no| FPReset["quietFrames = 0\nupdate previous fingerprint"]
    FPQuiet --> Check{"quietFrames >= 2?"}
    FPReset --> Timeout{timeout exceeded?}
    Check -->|yes| Settled["Return true (all clear)"]
    Check -->|no| Timeout
    Timeout -->|yes| NotSettled["Return false (timed out)"]
    Timeout -->|no| Frame
```

## Design Decisions

- **Separation from TheBagman**: TheTripwire reads UIKit timing signals; TheBagman reads the accessibility tree. TheTripwire never imports or reads the accessibility tree directly.
- **VC identity over element overlap**: Screen change is detected by comparing `ObjectIdentifier` of the topmost VC, replacing the old heuristic of checking element identifier overlap ratios. This is more reliable and cheaper. For cases where the VC is reused (e.g., Workflow-style navigation), TheBagman provides a supplementary topology-based check using back button trait and header labels.
- **CADisplayLink over polling**: Settling uses vsync-synced display link callbacks instead of a polling loop with `Task.sleep`. Zero drift, zero wasted polls.
- **Presentation layer fingerprinting**: Summing `CALayer.presentation()` positions/opacities catches any layer movement without needing to enumerate specific animation types.
- **Unified settle loop**: `waitForAllClear(timeout:)` uses presentation layer fingerprinting in a CADisplayLink loop, replacing the prior two-phase approach (settle then poll).

## Items Flagged for Review

### LOW PRIORITY

**`getTraversableWindows()` is called from both TheTripwire and TheBagman**
- TheBagman calls `tripwire.getTraversableWindows()` for hierarchy parsing and screen capture
- This is by design (shared window set), but the method is on TheTripwire rather than being shared infrastructure

# TheTripwire — The Early Warning System

> **File:** `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Persistent UI pulse — samples all timing signals on a single ~10 Hz clock, gates settle decisions, and emits transition events

## Overview

TheTripwire is the UI state sensor for TheInsideJob. It owns a single persistent `CADisplayLink` that fires at ~10 Hz, sampling the layer tree, public navigation state, and ordered visible windows on every tick. Multiple concurrent callers can wait for the UI to settle, each tracking their own quiet-frame count against an independent deadline.

TheTripwire never reads the accessibility tree. It reads UIKit timing signals (layers, animations, public navigation state, window stack). TheStash reads the accessibility tree. The two are cleanly separated.

Tripwire is a check signal, not a classifier: when Tripwire triggers, TheBrains re-parses the accessibility tree and `ScreenClassifier` decides whether the parsed result is no-change, element-change, or screen-change.

## Nested Types

| Type | Kind | Purpose |
|------|------|---------|
| `PulseReading` | `struct` | Snapshot of all sampled signals from one tick |
| `PulseTransition` | `enum` | Discrete state-change events emitted via `onTransition` |
| `PresentationFingerprint` | `struct` | Sum of all presentation layer positions and opacities |
| `LayerScan` | `struct` | Accumulator filled during `scanLayers()` |
| `SettleWaiter` | `private struct` | Per-caller state for `waitForSettle` |
| `RunningContext` | `private class` | Mutable context that exists only while the pulse is running — holds link, tick count, latest reading, settle waiters |
| `PulsePhase` | `private enum` | State machine: `.idle` or `.running(RunningContext)` |
| `PulseTick` | file-private top-level `class` | `NSObject` target for `CADisplayLink` (weak-ref indirection) |

## Pulse Architecture

TheTripwire runs a single `CADisplayLink` at ~10 Hz. Every tick runs the full set of checks in one pass — there is no tiered cadence; all signals are sampled on every tick:

1. `CATransaction.flush()` — commit deferred SwiftUI layout
2. `scanLayers()` — single layer-tree walk for fingerprint, animations, layout, window count
3. Sample Tripwire signal (`topmostViewController`, public navigation state, ordered visible windows)
4. Build a `PulseReading` snapshot with all signals + derived quiet-frame count
5. Diff against the previous `latestReading` and fire `PulseTransition` callbacks for any changes
6. Resolve settle waiters

**`latestReading` is the single source of truth.** There are no shadow variables — the new reading is diffed directly against the previous one for transition detection.

```mermaid
graph TD
    subgraph TheTripwire["TheTripwire (@MainActor, internal)"]
        subgraph Pulse["Persistent Pulse (~10 Hz)"]
            PulseTick["PulseTick (weak ref target)"]
            DisplayLink["CADisplayLink (8–12 fps)"]
            OnTick["onTick() — main loop"]
        end

        subgraph Scan["scanLayers() — Single Layer Walk"]
            FP["PresentationFingerprint"]
            Anim["hasRelevantAnimations"]
            Layout["hasPendingLayout"]
            WinCount["windowCount"]
        end

        subgraph TripwireSignal["Tripwire Signal (every tick)"]
            TopVC["topmostViewController()"]
            DeepVC["deepestViewController(from:)"]
            NavSignal["navigationSignal(for:)"]
            WindowSignal["windowStackSignal(for:)"]
        end

        subgraph Settle["Settle Wait (per-waiter)"]
            WaitSettle["waitForSettle(timeout:requiredQuietFrames:)"]
            WaitAllClear["waitForAllClear(timeout:)"]
            Waiters["settleWaiters: [SettleWaiter]"]
        end

        subgraph FrameYield["Lightweight Frame Yield"]
            YieldFrames["yieldFrames(count)<br/>CATransaction.flush() + Task.yield()"]
        end

        subgraph Windows["Window Access"]
            GetWindows["getTraversableWindows()"]
            GetAXWindows["getAccessibleWindows()"]
        end
    end

    DisplayLink --> PulseTick
    PulseTick -->|"weak ref"| OnTick
    OnTick -->|"every tick"| Scan
    OnTick -->|"every tick"| TripwireSignal
    OnTick -->|"every tick"| Settle

    subgraph Consumers["Consumers"]
        IJ["TheInsideJob"]
        BM["TheStash"]
    SC["TheSafecracker"]
    end

    IJ -->|"owns, sets onTransition"| TheTripwire
    BM -->|"getAccessibleWindows/getTraversableWindows,<br/>waitForAllClear, yieldFrames, tripwireSignal"| TheTripwire
    SC -->|"waitForAllClear"| TheTripwire
```

## The Pulse Model

### Lifecycle

`startPulse()` is idempotent. When first called:

1. Allocates a `PulseTick` (NSObject) and stores it in `pulseTarget`.
2. Creates `CADisplayLink(target: pulseTarget, selector: handleTick)` — the display link retains `PulseTick`, not `TheTripwire`. If `TheTripwire` deallocates, `handleTick` sees `nil` and invalidates the link.
3. Sets `preferredFrameRateRange(minimum: 8, maximum: 12, preferred: 10)`.
4. Adds to `.main` run loop, `.common` mode (fires during scrolling too).
5. Starts the pulse.

`stopPulse()` invalidates the link, resumes all pending settle waiters with `false`, and resets all state.

### Tick Cadence

All signals are sampled on every tick (~10 Hz). There is no tiered cadence — `onTick()` runs all checks unconditionally:

```mermaid
flowchart LR
    subgraph EveryTick["Every Tick (~10 Hz)"]
        SL["scanLayers()"]
        VC["topmostViewController()"]
        QF["quietFrameCount update"]
        SW["resolveSettleWaiters()"]
    end
```

Every tick builds a complete `PulseReading` snapshot from all current signal values.

### Tick Processing (`onTick()`)

1. **`CATransaction.flush()`** — commits SwiftUI's deferred implicit layout before sampling.
2. **`scanLayers()`** — single DFS walk of every layer in every traversable window. Returns `LayerScan` with fingerprint, animation flag, layout flag, window count.
3. **Quiet frame logic** — a tick is quiet if: no pending layout, no relevant animations, AND fingerprint matches previous. Quiet increments `quietFrameCount`; not quiet resets to 0.
4. **Tripwire signal** — `topmostViewController()`, public navigation state, and ordered visible windows. Change fires `.tripwireTriggered(from:to:)`.
5. **Build `PulseReading`** from all current signal values.
6. **Settle edge detection** — fires `.settled` on false→true, `.unsettled` on true→false.
7. **`resolveSettleWaiters()`** — increments or resets each waiter's quiet count, resumes those that are done.

## `scanLayers()` — Single Combined Layer Walk

Replaces three separate passes (fingerprint, animation check, layout check) with one DFS using an explicit stack:

```mermaid
flowchart TD
    Start["Get traversable windows"]
    Start --> Stack["Push all window layers onto stack"]
    Stack --> Pop{"Pop layer"}
    Pop -->|empty| Done["Return LayerScan"]
    Pop -->|layer| Pres["Resolve presentation() ?? model layer"]
    Pres --> AccumFP["Accumulate positionX/Y, opacity sums"]
    AccumFP --> CheckLayout{"needsLayout()?"}
    CheckLayout -->|yes| SetLayout["hasPendingLayout = true"]
    CheckLayout -->|no| Skip1[" "]
    SetLayout --> CheckAnim
    Skip1 --> CheckAnim{"hasRelevantAnimations\nalready true?"}
    CheckAnim -->|yes| Push["Push sublayers"]
    CheckAnim -->|no| AnimKeys["Check animationKeys()"]
    AnimKeys --> Filter["Filter ignored prefixes"]
    Filter --> Any{"Any surviving keys?"}
    Any -->|yes| SetAnim["hasRelevantAnimations = true"]
    Any -->|no| Push
    SetAnim --> Push
    Push --> Pop
```

**Ignored animation prefixes:** `["_UIParallaxMotionEffect", "match-"]` — parallax motion effects and matchedGeometryEffect transitions are persistent/transient system animations that would block settlement.

## `PresentationFingerprint` — Structure and Comparison

Fields: `positionXSum`, `positionYSum`, `opacitySum` (all `CGFloat`), `layerCount` (`Int`).

`matches(_ other:)` uses toleranced comparison:
- `layerCount` must match exactly (layer additions/removals are always significant)
- Position tolerance: `0.5 pt` (catches any perceptible movement, ignores sub-pixel noise)
- Opacity tolerance: `0.05` (catches fades, ignores floating-point drift)

All four conditions must pass. Reading `presentation()` instead of the model layer captures in-flight animated values.

## Per-Waiter Settle Tracking

```mermaid
sequenceDiagram
    participant C1 as Caller A (action result)
    participant C2 as Caller B (send interface)
    participant TW as TheTripwire
    participant DL as CADisplayLink

    C1->>TW: waitForSettle(timeout: 1.0)
    Note over TW: SettleWaiter A: quiet=0, deadline=now+1.0

    C2->>TW: waitForSettle(timeout: 0.5)
    Note over TW: SettleWaiter B: quiet=0, deadline=now+0.5

    DL->>TW: tick (quiet)
    Note over TW: A.quiet=1, B.quiet=1

    DL->>TW: tick (not quiet — animation started)
    Note over TW: A.quiet=0, B.quiet=0

    DL->>TW: tick (quiet)
    Note over TW: A.quiet=1, B.quiet=1

    DL->>TW: tick (quiet)
    Note over TW: A.quiet=2 ≥ 2 → resume(true)<br/>B.quiet=2 ≥ 2 → resume(true)

    TW-->>C1: true (settled)
    TW-->>C2: true (settled)
```

Key design: each waiter starts its own quiet-frame counter at zero, independent of the global `quietFrameCount`. A waiter registered after the UI is already settled must still accumulate its own 2 quiet frames. This prevents false positives where a settle happened before the caller started waiting.

`resolveSettleWaiters` iterates in reverse for safe removal — prevents index shifting from affecting unprocessed waiters.

### Callers

| Call site | Timeout | Purpose |
|-----------|---------|---------|
| `checkForChanges()` | sync `allClear()` | Gate settled capture checks |
| `sendInterface()` | 0.5s | Wait before sending interface snapshot |
| `actionResultWithDelta()` | 1.0s | Wait after action before computing delta |
| `handleWaitForIdle()` | user-specified (clamped to 60s) | Explicit idle wait command |

## Lightweight Frame Yielding

`yieldFrames(_:)` is a minimal alternative to `waitForSettle` for scroll loops that need layout to run but don't need to wait for animations to finish. Each iteration does:

1. `CATransaction.flush()` — commit pending Core Animation transactions (flushes SwiftUI layout)
2. `Task.yield()` — yield to the main run loop so layout and rendering can execute

This is used by `TheStash`'s scroll scan loop and scroll-to-edge re-jump loop. Two frames is enough for SwiftUI lazy containers to materialize content after a `contentOffset` change, without the overhead of the full pulse-based settle detection.

**Why not `waitForSettle`:** The settle path waits for presentation layers to match model layers (no in-flight animations). In a scroll scan, we don't care about animations finishing — we just need layout to run so new accessibility elements appear. `yieldFrames` is ~2 orders of magnitude faster per step.

| Caller | Frames | Purpose |
|--------|--------|---------|
| `scanLoop()` | 2 | Let lazy content materialize between page scrolls |
| `executeScrollToEdge()` | 2 | Let lazy content grow `contentSize` between re-jumps |
| `executeScrollToVisible()` Phase 2 | 2 | Let layout settle after jumping to opposite edge |

### `yieldRealFrames(_:intervalMs:)`

A heavier variant of `yieldFrames` that uses `Task.sleep` instead of `Task.yield()` to give `CADisplayLink` animations time to process. Required for accessibility SPI scroll methods that queue animated scrolls — `Task.yield()` alone doesn't advance the animation. Default interval is 16ms (one display frame).

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

Sampled every tick. A changed Tripwire signal fires `.tripwireTriggered(from:to:)`, which means "parse and check now." It does not guarantee that the parsed accessibility interface changed.

### Parsed Screen Classification

TheBrains classifies screen changes after parsing, not inside TheTripwire:
- **Modal boundary**: parsed modal container changed = screen change
- **Navigation marker**: selected tab, back button, or primary header changed = screen change
- **Root shape replacement**: most structural accessibility roles were replaced = screen change
- **Stable interaction context**: the same parsed first responder can keep filtered-list churn on the same screen

Window-stack changes are Tripwire triggers only. Key-window status is input routing, not accessibility scope.

## `PulseTransition` Events

| Transition | Trigger | Cadence |
|-----------|---------|---------|
| `.tripwireTriggered(from:to:)` | Tripwire signal differs from the prior tick | Every tick |
| `.settled` | quiet → settled edge | Every tick |
| `.unsettled` | settled → not-quiet edge | Every tick |

TheInsideJob wires `onTransition` and uses `.settled` to trigger deferred settled-change tracking when `hierarchyInvalidated` is true.

## Window Filtering

`getTraversableWindows()` scans the `foregroundActive` `UIWindowScene`. Filters out:
- `TheFingerprints.FingerprintWindow` (tap-indicator overlay)
- Hidden windows
- Zero-size windows

Sorts by `windowLevel` descending (frontmost first). Returns `[(window: UIWindow, rootView: UIView)]`.

Used by `scanLayers()` for visual fingerprinting and screenshot capture so visual work sees the full composited window stack.

`getAccessibleWindows()` starts from the traversable set and applies the accessibility parse scope:
- System passthrough windows (`UIRemoteKeyboardWindow`, `UITextEffectsWindow`) are dropped because they sit above the app but do not contain app content.
- Every remaining app window is preserved. Key-window status is input routing, not accessibility scope.
- Each remaining window with a presented-view-controller chain is parsed from the deepest presented view.
- `TheTripwire` does not walk views for `accessibilityViewIsModal`. The parser reports modal boundary containers, and `TheBurglar` stops parsing lower windows when that signal appears.

Used by `TheBurglar.parse()` for accessibility hierarchy parsing, invoked through `stash.refresh()`.

## Crew Interactions

```mermaid
graph LR
    IJ["TheInsideJob"] -->|"owns, start/stopPulse, onTransition"| TW["TheTripwire"]
    BM["TheStash"] -->|"let tripwire (strong)"| TW
    SC["TheSafecracker"] -->|"weak var tripwire"| TW

    TW -->|".settled → noteSettledChangeIfNeeded()"| IJ
    TW -->|"window access, waitForAllClear, tripwireSignal, topmostVC"| BM
    TW -->|"waitForAllClear"| SC
```

- **TheInsideJob** owns the instance. Sets `onTransition` in `start()`, calls `startPulse()`/`stopPulse()` on suspend/resume. On `.settled`, tracks the settled change if invalidated.
- **TheStash** holds a strong ref passed at init. Uses accessible windows for parsing, traversable windows for capture, and `waitForAllClear()` post-action.
- **TheSafecracker** uses `waitForAllClear()` for scroll-settle in `ensureOnScreen`.

## Design Decisions

- **Persistent pulse over on-demand sampling**: A single ~10 Hz clock replaces ad-hoc polling loops and per-settle display links. Lower overhead, better timing coherence, and the pulse detects transitions even when no one is actively waiting.
- **Flat cadence**: All Tripwire signals are sampled on every tick. The simplicity of running all checks unconditionally outweighs the marginal CPU savings of tiered sampling.
- **Weak-ref indirection via PulseTick**: `CADisplayLink` retains its target. If TheTripwire were the target, deallocating it would leave a dangling display link. The `PulseTick` intermediary checks a weak ref and self-invalidates.
- **`CATransaction.flush()` before scanning**: SwiftUI batches layout commits. Without the flush, `scanLayers()` would see stale layer positions and report false "quiet" readings.
- **Per-waiter quiet frames**: Global quiet-frame count can't serve multiple concurrent callers with different start times. Each waiter tracks its own count from registration, preventing false positives from stale settle state.
- **Separation from TheStash**: TheTripwire reads UIKit timing signals; TheStash reads the accessibility tree. Neither imports the other's domain. The shared surface is window selection plus settle and Tripwire triggers.
- **Tripwire trigger over screen-change guess**: cheap UIKit changes prompt a parse; parsed accessibility signatures decide no-change, element-change, or screen-change.
- **Presentation layer fingerprinting**: Summing `CALayer.presentation()` positions/opacities catches any layer movement without enumerating specific animation types. The tolerances (0.5 pt position, 0.05 opacity) filter sub-pixel noise while catching all perceptible motion.

## Items Flagged for Review

### LOW PRIORITY

**Window selection is owned by TheTripwire**
- TheBurglar parses `tripwire.getAccessibleWindows()` so accessibility scope follows modal and passthrough policy.
- Capture and fingerprinting use `tripwire.getTraversableWindows()` so visual work sees the full composited window stack.
- This is by design, but the policy still lives on TheTripwire rather than a standalone window-selection type.

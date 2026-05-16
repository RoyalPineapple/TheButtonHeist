# TheTripwire

10 Hz UI pulse. Samples all timing signals on a single `CADisplayLink`, gates settle decisions, and emits transition events. Zero crew dependencies — pure sensor.

Tripwire is a check signal, not a classifier: when Tripwire triggers, TheBrains re-parses the accessibility tree and then the parsed hierarchy decides whether the result is no-change, element-change, or screen-change.

## The one file

**`TheTripwire.swift`** — `@MainActor final class`.

### The pulse loop

`startPulse()` creates a `CADisplayLink` targeting 8-12 fps (preferred 10). Each tick calls `onTick()`:

1. `CATransaction.flush()` — commit pending implicit animations before scanning
2. `scanLayers()` — single DFS over all layer trees from `getTraversableWindows()`:
   - Accumulates `positionXSum`, `positionYSum`, `opacitySum`, `layerCount` from presentation layers
   - Checks `needsLayout()` on each layer
   - Checks `animationKeys()` — ignores `_UIParallaxMotionEffect` and `match-` prefixed keys
   - Returns `LayerScan` with a `PresentationFingerprint`
3. Compute `isQuiet`: no pending layout AND no relevant animations AND fingerprint matches previous (0.5pt position tolerance, 0.05 opacity tolerance)
4. Get `tripwireSignal()` — top VC identity, public navigation state, and ordered visible windows
5. Build `PulseReading` with `quietFrames = isQuiet ? (prev + 1) : 0`
6. Diff against previous reading:
   - Tripwire triggered → fire `onTransition?(.tripwireTriggered(from:to:))`
   - Newly settled → fire `.settled`
   - Newly unsettled → fire `.unsettled`
7. `resolveSettleWaiters(context:now:isQuiet:)` — check each waiter

### Per-waiter settle detection

Each `waitForSettle(timeout:requiredQuietFrames:)` caller gets its own `SettleWaiter` with an independent quiet-frame counter. The waiter is created via `withCheckedContinuation` and appended to `context.settleWaiters`. On each tick, if quiet: increment the waiter's counter. If `quietFrames >= requiredQuietFrames`: resume with `true`. If past deadline: resume with `false`. This prevents false positives from pre-registration quiet frames.

`waitForAllClear(timeout:)` — the most common entry point. Calls `waitForSettle(timeout:requiredQuietFrames: 2)`.

### Window access

`getTraversableWindows()` — all non-hidden, non-zero-bounds windows from the `foregroundActive` scene, sorted by `windowLevel` descending. Filters out `TheFingerprints.FingerprintWindow` instances.

`getAccessibleWindows()` — calls `getTraversableWindows()`, drops system passthrough windows (keyboard/text effects), preserves every remaining app window, and resolves each window with a presentation chain to its deepest presented view. Modal boundaries are reported by the accessibility parser and consumed by `TheBurglar`, not detected by walking views here.

### State machine

`PulsePhase`: `.idle` or `.running(RunningContext)`. `RunningContext` is a reference type holding the display link, tick count, latest reading, and settle waiters.

### Other utilities

- `yieldFrames(_:)` — lightweight: `CATransaction.flush()` + `Task.yield()`. For scroll loops needing layout but not full settle.
- `yieldRealFrames(_:intervalMs:)` — heavier: `Task.sleep` between frames. For animated scroll SPI.
- `tripwireSignal()` — cheap UIKit signal/context signal. It never classifies no-change vs element-change vs screen-change.
- `didTripwireTrigger(before:after:)` — compares tripwire signals.

> Full dossier: [`docs/dossiers/15-THETRIPWIRE.md`](../../../../docs/dossiers/15-THETRIPWIRE.md)

#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {

    // MARK: - Pulse State

    /// Mutable context that exists only while the pulse is running.
    /// Reference type so tick mutations don't require enum reconstruction.
    final class RunningContext {
        let link: CADisplayLink
        let target: PulseTick
        var latestReading: PulseReading?
        var tickCount: UInt64 = 0
        var settleWaiters: [SettleWaiter] = []

        init(link: CADisplayLink, target: PulseTick) {
            self.link = link
            self.target = target
        }
    }

    enum PulsePhase {
        case idle
        case running(RunningContext)
    }

    /// The latest pulse reading, if the pulse is running.
    private(set) var latestReading: PulseReading? {
        get { runningContext?.latestReading }
        set { runningContext?.latestReading = newValue }
    }

    struct SettleWaiter {
        var quietFrames: Int
        let requiredQuietFrames: Int
        let deadline: CFAbsoluteTime
        let continuation: CheckedContinuation<Bool, Never>
    }

    // MARK: - Pulse Lifecycle

    var isPulseRunning: Bool { runningContext != nil }

    func startPulse() {
        guard case .idle = pulsePhase else { return }
        let target = PulseTick(tripwire: self)
        let link = CADisplayLink(target: target, selector: #selector(PulseTick.handleTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
        link.add(to: .main, forMode: .common)
        pulsePhase = .running(RunningContext(link: link, target: target))
    }

    func stopPulse() {
        guard let context = runningContext else { return }
        context.link.invalidate()

        for waiter in context.settleWaiters {
            waiter.continuation.resume(returning: false)
        }

        pulsePhase = .idle
    }

    // MARK: - Settle Waiting

    /// Wait for the UI to settle — no pending layout, stable presentation
    /// fingerprint for `requiredQuietFrames` consecutive ticks.
    ///
    /// Each waiter tracks its own quiet-frame count from the moment of
    /// registration, so post-action animations are captured even if the
    /// pulse was already settled.
    ///
    /// The caller owns pulse lifetime. Runtime commands get their pulse from
    /// `InsideJobRuntimeLease`; standalone tests and tools must start it
    /// explicitly.
    ///
    /// Returns true if settled before timeout, false if timed out.
    func waitForSettle(timeout: TimeInterval = 1.0, requiredQuietFrames: Int = 2) async -> Bool {
        guard let context = runningContext else { return false }
        return await withCheckedContinuation { continuation in
            context.settleWaiters.append(SettleWaiter(
                quietFrames: 0,
                requiredQuietFrames: requiredQuietFrames,
                deadline: CFAbsoluteTimeGetCurrent() + timeout,
                continuation: continuation
            ))
        }
    }

    /// Wait for the interface to become all clear.
    ///
    /// Delegates to `waitForSettle`; the caller must already own a running
    /// pulse.
    /// Returns true if settled before timeout, false if timed out.
    ///
    /// **Settle signal boundary.** This is the layer-level settle path: it
    /// watches CALayer fingerprint, animations, and pending layout, and
    /// never reads the AX tree. Use it when the caller only needs "the UI
    /// has stopped moving" — post-jump SPI animations, broadcast pacing,
    /// wait-for-idle, wait-for-change polling. For post-action correctness
    /// (where AX-tree fingerprint stability is the load-bearing signal)
    /// use `SettleSession` instead; for per-frame swipe motion detection
    /// (where the viewport heistId set is the signal) use the swipe-settle
    /// loop in `Navigation+Scroll.swift`. The boundary is intentional —
    /// layer quiet and AX-tree quiet disagree on every spinner.
    func waitForAllClear(timeout: TimeInterval = 1.0) async -> Bool {
        await waitForSettle(timeout: timeout)
    }

    /// Yield to the main run loop for N display frames. Each iteration
    /// flushes pending Core Animation transactions and gives layout a
    /// chance to run — enough for lazy containers to materialise content
    /// without waiting for animations to finish.
    ///
    /// **Settle signal boundary.** Fixed-count yields are not a settle
    /// signal — they are empirically calibrated waits for known animation
    /// timings. Use this when the caller needs to advance a known number
    /// of layout passes (post-scroll CATransaction flush, intra-swipe
    /// frame stepping) without subscribing to the persistent pulse. For
    /// signal-driven waits, see `waitForAllClear` (layer) or `SettleSession`
    /// (AX tree).
    func yieldFrames(_ count: Int) async {
        for _ in 0..<count {
            CATransaction.flush()
            await Task.yield()
        }
    }

    /// Yield frames with real wall-clock time between each.
    /// Unlike `yieldFrames` (which uses `Task.yield()`), this uses
    /// `Task.sleep` to give CADisplayLink animations time to process.
    /// Required for accessibility SPI scroll methods that queue animated
    /// scrolls — `Task.yield()` alone doesn't advance the animation.
    ///
    /// Same fixed-count contract as `yieldFrames(_:)` — see that doc for
    /// the four-implementation settle-signal boundary.
    func yieldRealFrames(_ count: Int, intervalMs: UInt64 = 16) async {
        for _ in 0..<count {
            CATransaction.flush()
            guard await Task.cancellableSleep(for: .milliseconds(intervalMs)) else { break }
        }
    }

    // MARK: - Tick Handler

    func onTick() {
        guard let context = runningContext else { return }
        context.tickCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let prev = context.latestReading

        // Flush pending implicit transactions so SwiftUI's deferred
        // layout commits before we scan.
        CATransaction.flush()

        let scan = scanLayers()
        let fingerprint = scan.fingerprint

        let isQuiet = !scan.hasPendingLayout
            && (prev?.fingerprint.matches(fingerprint) ?? true)

        let tripwireSignal = tripwireSignal()
        let vcId = tripwireSignal.topmostVC

        let reading = PulseReading(
            tick: context.tickCount,
            timestamp: now,
            layoutPending: scan.hasPendingLayout,
            fingerprint: fingerprint,
            hasRelevantAnimations: scan.hasRelevantAnimations,
            topmostVC: vcId,
            tripwireSignal: tripwireSignal,
            windowCount: scan.windowCount,
            quietFrames: isQuiet ? (prev?.quietFrames ?? 0) + 1 : 0
        )
        context.latestReading = reading

        resolveSettleWaiters(context: context, now: now, isQuiet: isQuiet)
    }

    private func resolveSettleWaiters(context: RunningContext, now: CFAbsoluteTime, isQuiet: Bool) {
        for index in context.settleWaiters.indices {
            if isQuiet {
                context.settleWaiters[index].quietFrames += 1
            } else {
                context.settleWaiters[index].quietFrames = 0
            }
        }

        for index in context.settleWaiters.indices.reversed() {
            let waiter = context.settleWaiters[index]
            if waiter.quietFrames >= waiter.requiredQuietFrames {
                waiter.continuation.resume(returning: true)
                context.settleWaiters.remove(at: index)
            } else if now >= waiter.deadline {
                waiter.continuation.resume(returning: false)
                context.settleWaiters.remove(at: index)
            }
        }
    }

    /// Is the interface all clear? When the pulse is running, returns the
    /// latest reading's settle state (requires 2 consecutive quiet frames).
    /// Otherwise falls back to a synchronous pending-layout check. Animation
    /// keys are diagnostic; movement is represented by fingerprint changes.
    func allClear() -> Bool {
        switch pulsePhase {
        case .running(let context):
            return context.latestReading?.isSettled ?? false
        case .idle:
            let scan = scanLayers()
            return !scan.hasPendingLayout
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

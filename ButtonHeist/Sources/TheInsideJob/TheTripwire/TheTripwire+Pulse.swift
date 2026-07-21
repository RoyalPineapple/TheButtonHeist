#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
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
        var settleWaiters = WaiterStore<UInt64, SettleWaiter>()
        var heartbeatWaiters = WaiterStore<UInt64, HeartbeatWaiter>()

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
        let continuation: TimedOneShot<Bool>
    }

    enum HeartbeatDemand: Equatable, Sendable {
        case ambient
        case immediate
    }

    enum HeartbeatWaitOutcome: Equatable, Sendable {
        case observed
        case timedOut
        case cancelled
        case unavailable
    }

    struct HeartbeatWaiter: Sendable {
        let demand: HeartbeatDemand
        let continuation: TimedOneShot<HeartbeatWaitOutcome>
    }

    // MARK: - Pulse Lifecycle

    var isPulseRunning: Bool { runningContext != nil }

    func startPulse() {
        guard case .idle = pulsePhase else { return }
        let target = PulseTick(tripwire: self)
        let link = CADisplayLink(target: target, selector: #selector(PulseTick.handleTick))
        link.preferredFrameRateRange = Self.pulseFrameRateRange
        link.add(to: .main, forMode: .common)
        pulsePhase = .running(RunningContext(link: link, target: target))
    }

    func stopPulse() {
        guard let context = runningContext else { return }
        context.link.invalidate()

        let waiters = context.settleWaiters.removeAll()
        let heartbeatWaiters = context.heartbeatWaiters.removeAll()

        for waiter in waiters {
            waiter.continuation.resolve(returning: false)
        }
        heartbeatWaiters.forEach { $0.continuation.resolve(returning: .unavailable) }
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
    /// TheInsideJob runtime resources; standalone tests and tools must start it
    /// explicitly.
    ///
    /// Returns true if settled before timeout, false if timed out.
    func waitForSettle(timeout: TimeInterval = 1.0, requiredQuietFrames: Int = 2) async -> Bool {
        guard let context = runningContext else { return false }
        let waiterID = context.settleWaiters.reserveID()
        let oneShot = TimedOneShot<Bool>()

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if oneShot.register(continuation) {
                    context.settleWaiters.insert(SettleWaiter(
                        quietFrames: 0,
                        requiredQuietFrames: requiredQuietFrames,
                        deadline: CFAbsoluteTimeGetCurrent() + timeout,
                        continuation: oneShot
                    ), id: waiterID)
                } else {
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            oneShot.resolve(returning: false)
        }
        removeSettleWaiter(id: waiterID)
        return result
    }

    private func removeSettleWaiter(id: UInt64) {
        _ = runningContext?.settleWaiters.remove(id: id)
    }

    /// Waits for one future tick of Button Heist's single CADisplayLink heartbeat.
    /// Immediate demand temporarily raises the same link to the active screen's
    /// maximum refresh rate; ambient demand preserves the configured monitor rate.
    func waitForNextHeartbeat(
        timeout: Duration,
        demand: HeartbeatDemand
    ) async -> HeartbeatWaitOutcome {
        guard timeout > .zero else { return .timedOut }
        guard let context = runningContext else { return .unavailable }
        let waiterID = context.heartbeatWaiters.reserveID()
        let oneShot = TimedOneShot<HeartbeatWaitOutcome>()
        return await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { oneShot in
                guard runningContext === context else {
                    oneShot.resolve(returning: .unavailable)
                    return
                }
                context.heartbeatWaiters.insert(
                    HeartbeatWaiter(demand: demand, continuation: oneShot),
                    id: waiterID
                )
                updateDisplayLinkRate(context)
                oneShot.armTimeout(after: timeout) { [weak self] in
                    await self?.resolveHeartbeatWaiter(
                        id: waiterID,
                        returning: .timedOut
                    )
                }
            },
            onFinished: { [weak self] in
                self?.removeHeartbeatWaiter(id: waiterID, from: context)
            }
        )
    }

    /// Wait for the interface to become all clear.
    ///
    /// Delegates to `waitForSettle`; the caller must already own a running
    /// pulse.
    /// Returns true if settled before timeout, false if timed out.
    ///
    /// **Settle signal boundary.** This is the layer-level settle path: it
    /// watches CALayer geometry fingerprint and pending layout, and
    /// never reads the AX tree. Use it when the caller only needs "the UI
    /// has stopped changing frame geometry" — post-jump SPI animations,
    /// broadcast pacing, wait-for-idle, wait-for-change polling.
    /// For post-action correctness
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
            topmostVC: vcId,
            tripwireSignal: tripwireSignal,
            windowCount: scan.windowCount,
            quietFrames: isQuiet ? (prev?.quietFrames ?? 0) + 1 : 0
        )
        context.latestReading = reading

        resolveSettleWaiters(context: context, now: now, isQuiet: isQuiet)
        observeHeartbeat(context)
    }

    private func observeHeartbeat(_ context: RunningContext) {
        let waiters = context.heartbeatWaiters.removeAll()
        guard !waiters.isEmpty else { return }
        updateDisplayLinkRate(context)
        waiters.forEach { $0.continuation.resolve(returning: .observed) }
    }

    private func resolveHeartbeatWaiter(
        id: UInt64,
        returning outcome: HeartbeatWaitOutcome
    ) {
        guard let context = runningContext else { return }
        guard let waiter = context.heartbeatWaiters.remove(id: id) else { return }
        updateDisplayLinkRate(context)
        waiter.continuation.resolve(returning: outcome)
    }

    private func removeHeartbeatWaiter(id: UInt64, from context: RunningContext) {
        guard context.heartbeatWaiters.remove(id: id) != nil else { return }
        updateDisplayLinkRate(context)
    }

    private func updateDisplayLinkRate(_ context: RunningContext) {
        let hasImmediateDemand = context.heartbeatWaiters.contains {
            $0.demand == .immediate
        }
        context.link.preferredFrameRateRange = hasImmediateDemand
            ? Self.activeDisplayFrameRateRange(
                maximumFramesPerSecond: activeScreenMaximumFramesPerSecond()
            )
            : Self.pulseFrameRateRange
    }

    private func activeScreenMaximumFramesPerSecond() -> Int {
        captureTraversableWindows()
            .lazy
            .compactMap { $0.window.windowScene?.screen.maximumFramesPerSecond }
            .first ?? 60
    }

    private func resolveSettleWaiters(context: RunningContext, now: CFAbsoluteTime, isQuiet: Bool) {
        context.settleWaiters.updateAll { waiter in
            if isQuiet {
                waiter.quietFrames += 1
            } else {
                waiter.quietFrames = 0
            }
        }

        let completed = context.settleWaiters.removeAll {
            $0.quietFrames >= $0.requiredQuietFrames || now >= $0.deadline
        }
        for waiter in completed {
            waiter.continuation.resolve(returning: waiter.quietFrames >= waiter.requiredQuietFrames)
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

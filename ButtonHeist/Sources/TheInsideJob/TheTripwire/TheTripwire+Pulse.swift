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
        var tickWaiters = WaiterStore<UInt64, TickWaiter>()

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

    enum TickDemand: Equatable, Sendable {
        case ambient
        case immediate
    }

    enum TickWaitOutcome: Equatable, Sendable {
        case observed
        case timedOut
        case cancelled
        case unavailable
    }

    struct TickWaiter: Sendable {
        let demand: TickDemand
        let continuation: TimedOneShot<TickWaitOutcome>
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

        let tickWaiters = context.tickWaiters.removeAll()
        tickWaiters.forEach { $0.continuation.resolve(returning: .unavailable) }
        pulsePhase = .idle
    }

    // MARK: - Tick Waiting

    /// Waits for one future tick of Button Heist's single CADisplayLink tick.
    /// Immediate demand temporarily raises the same link to the active screen's
    /// maximum refresh rate; ambient demand preserves the configured monitor rate.
    func waitForNextTick(
        timeout: Duration,
        demand: TickDemand
    ) async -> TickWaitOutcome {
        guard timeout > .zero else { return .timedOut }
        guard let context = runningContext else { return .unavailable }
        let waiterID = context.tickWaiters.reserveID()
        let oneShot = TimedOneShot<TickWaitOutcome>()
        return await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { oneShot in
                guard runningContext === context else {
                    oneShot.resolve(returning: .unavailable)
                    return
                }
                context.tickWaiters.insert(
                    TickWaiter(demand: demand, continuation: oneShot),
                    id: waiterID
                )
                updateDisplayLinkRate(context)
                oneShot.armTimeout(after: timeout) { [weak self] in
                    await self?.resolveTickWaiter(
                        id: waiterID,
                        returning: .timedOut
                    )
                }
            },
            onFinished: { [weak self] in
                self?.removeTickWaiter(id: waiterID, from: context)
            }
        )
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
    /// signal-driven waits, see `waitForNextTick` (tick) or
    /// the observation stream (AX tree).
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

        // Flush pending implicit transactions so SwiftUI's deferred layout
        // commits before we sample.
        CATransaction.flush()

        let tripwireSignal = tripwireSignal()
        context.latestReading = PulseReading(
            tick: context.tickCount,
            timestamp: CFAbsoluteTimeGetCurrent(),
            topmostVC: tripwireSignal.topmostVC,
            tripwireSignal: tripwireSignal,
            windowCount: tripwireSignal.windowStack.windows.count
        )

        observeTick(context)
    }

    private func observeTick(_ context: RunningContext) {
        let waiters = context.tickWaiters.removeAll()
        guard !waiters.isEmpty else { return }
        updateDisplayLinkRate(context)
        waiters.forEach { $0.continuation.resolve(returning: .observed) }
    }

    private func resolveTickWaiter(
        id: UInt64,
        returning outcome: TickWaitOutcome
    ) {
        guard let context = runningContext else { return }
        guard let waiter = context.tickWaiters.remove(id: id) else { return }
        updateDisplayLinkRate(context)
        waiter.continuation.resolve(returning: outcome)
    }

    private func removeTickWaiter(id: UInt64, from context: RunningContext) {
        guard context.tickWaiters.remove(id: id) != nil else { return }
        updateDisplayLinkRate(context)
    }

    private func updateDisplayLinkRate(_ context: RunningContext) {
        let hasImmediateDemand = context.tickWaiters.contains {
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
}

#endif // DEBUG
#endif // canImport(UIKit)

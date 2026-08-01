#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {

    // MARK: - Pulse State

    /// Mutable context that exists only while the pulse is running.
    /// Reference type so tick mutations don't require enum reconstruction.
    @MainActor
    final class RunningContext {
        private let displayLink: CADisplayLink
        private let target: PulseTick
        private let pulseStartTime: CFTimeInterval
        var latestReading: PulseReading?
        var tickCount: UInt64 = 0
        var observationDemand: TickDemand?
        var receiveObservationPulse: (@MainActor (PulseReading) -> Void)?

        var displayFrameRateRange: CAFrameRateRange? {
            displayLink.preferredFrameRateRange
        }

        init(tripwire: TheTripwire) {
            target = PulseTick(tripwire: tripwire)
            displayLink = CADisplayLink(
                target: target,
                selector: #selector(PulseTick.handleTick)
            )
            pulseStartTime = CACurrentMediaTime()
            displayLink.preferredFrameRateRange = TheTripwire.pulseFrameRateRange
            displayLink.add(to: .main, forMode: .common)
            displayLink.isPaused = true
        }

        func stop() {
            displayLink.invalidate()
        }

        func updateDisplayLink(
            demand: TickDemand?,
            activeMaximumFramesPerSecond: Int
        ) {
            let hasImmediateDemand = demand == .immediate
            displayLink.preferredFrameRateRange = hasImmediateDemand
                ? TheTripwire.activeDisplayFrameRateRange(
                    maximumFramesPerSecond: activeMaximumFramesPerSecond
                )
                : TheTripwire.pulseFrameRateRange
            displayLink.isPaused = demand == nil
        }

        func elapsed(at timestamp: CFTimeInterval) -> Duration {
            .seconds(max(0, timestamp - pulseStartTime))
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

    // MARK: - Pulse Lifecycle

    var isPulseRunning: Bool { runningContext != nil }

    func startPulse() {
        guard case .idle = pulsePhase else { return }
        pulsePhase = .running(RunningContext(tripwire: self))
    }

    func stopPulse() {
        guard let context = runningContext else { return }
        context.stop()
        context.receiveObservationPulse = nil
        context.observationDemand = nil

        pulsePhase = .idle
    }

    // MARK: - Pulse Delivery

    /// Installs the semantic observation stream as the single durable pulse
    /// consumer. Demand controls whether the display link runs; the callback
    /// never performs work inline with the display-link invocation.
    func observePulses(
        _ receive: @escaping @MainActor (PulseReading) -> Void
    ) {
        guard let context = runningContext else { return }
        precondition(
            context.receiveObservationPulse == nil,
            "Only one semantic observation pulse consumer may be active"
        )
        context.receiveObservationPulse = receive
        updateDisplayLinkRate(context)
    }

    func stopObservingPulses() {
        guard let context = runningContext else { return }
        context.receiveObservationPulse = nil
        context.observationDemand = nil
        updateDisplayLinkRate(context)
    }

    func setObservationPulseDemand(_ demand: TickDemand?) {
        guard let context = runningContext else { return }
        context.observationDemand = demand
        updateDisplayLinkRate(context)
    }

    // MARK: - Tick Handler

    /// Samples live UIKit and display-link time before handing one complete
    /// value to the semantic observation stream.
    func captureDisplayLinkPulse(from displayLink: CADisplayLink) {
        guard let context = runningContext else { return }
        context.tickCount += 1

        // Flush pending implicit transactions so SwiftUI's deferred layout
        // commits before we sample.
        CATransaction.flush()

        let tripwireSignal = tripwireSignal()
        let reading = PulseReading(
            tick: context.tickCount,
            elapsed: context.elapsed(at: displayLink.timestamp),
            tripwireSignal: tripwireSignal
        )
        context.latestReading = reading

        context.receiveObservationPulse?(reading)
    }

    private func updateDisplayLinkRate(_ context: RunningContext) {
        context.updateDisplayLink(
            demand: context.observationDemand,
            activeMaximumFramesPerSecond: activeScreenMaximumFramesPerSecond()
        )
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

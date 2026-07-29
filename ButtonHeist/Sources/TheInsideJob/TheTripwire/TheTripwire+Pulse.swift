#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheTripwire {

    // MARK: - Pulse State

    /// Mutable context that exists only while the pulse is running.
    /// Reference type so tick mutations don't require enum reconstruction.
    @MainActor
    final class RunningContext {
        private enum Driver {
            case displayLink(CADisplayLink, target: PulseTick)
            case injected
        }

        private let driver: Driver
        var latestReading: PulseReading?
        var tickCount: UInt64 = 0
        var observationDemand: TickDemand?
        var receiveObservationPulse: (@MainActor (PulseReading) -> Void)?

        var usesDisplayLink: Bool {
            guard case .displayLink = driver else { return false }
            return true
        }

        var displayFrameRateRange: CAFrameRateRange? {
            guard case .displayLink(let link, _) = driver else { return nil }
            return link.preferredFrameRateRange
        }

        init(source: PulseSource, tripwire: TheTripwire) {
            switch source {
            case .displayLink:
                let target = PulseTick(tripwire: tripwire)
                let link = CADisplayLink(
                    target: target,
                    selector: #selector(PulseTick.handleTick)
                )
                link.preferredFrameRateRange = TheTripwire.pulseFrameRateRange
                link.add(to: .main, forMode: .common)
                link.isPaused = true
                driver = .displayLink(link, target: target)
            case .injected:
                driver = .injected
            }
        }

        func stop() {
            guard case .displayLink(let link, _) = driver else { return }
            link.invalidate()
        }

        func updateDisplayLink(
            demand: TickDemand?,
            activeMaximumFramesPerSecond: Int
        ) {
            guard case .displayLink(let link, _) = driver else { return }
            let hasImmediateDemand = demand == .immediate
            link.preferredFrameRateRange = hasImmediateDemand
                ? TheTripwire.activeDisplayFrameRateRange(
                    maximumFramesPerSecond: activeMaximumFramesPerSecond
                )
                : TheTripwire.pulseFrameRateRange
            link.isPaused = demand == nil
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
        pulsePhase = .running(RunningContext(source: pulseSource, tripwire: self))
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

    func onTick() {
        guard let context = runningContext else { return }
        context.tickCount += 1

        // Flush pending implicit transactions so SwiftUI's deferred layout
        // commits before we sample.
        CATransaction.flush()

        let tripwireSignal = tripwireSignal()
        let reading = PulseReading(
            tick: context.tickCount,
            timestamp: CFAbsoluteTimeGetCurrent(),
            topmostVC: tripwireSignal.topmostVC,
            tripwireSignal: tripwireSignal,
            windowCount: tripwireSignal.windowStack.windows.count
        )
        context.latestReading = reading

        context.receiveObservationPulse?(reading)
    }

    private func updateDisplayLinkRate(_ context: RunningContext) {
        guard context.usesDisplayLink else { return }
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

#if canImport(UIKit)
#if DEBUG
import Foundation

@MainActor
final class InsideJobRuntimeLease {
    enum ReleasePolicy {
        case suspend
        case stop
    }

    let transport: ServerTransport
    let actualPort: UInt16
    let tlsFingerprint: String
    let bonjourServiceName: String?
    private var isActive = false
    private var releaseTask: Task<Void, Never>?

    init(
        transport: ServerTransport,
        actualPort: UInt16,
        tlsFingerprint: String,
        bonjourServiceName: String?
    ) {
        self.transport = transport
        self.actualPort = actualPort
        self.tlsFingerprint = tlsFingerprint
        self.bonjourServiceName = bonjourServiceName
    }

    func activate(on job: TheInsideJob, resumePolling: Bool) {
        guard !isActive, releaseTask == nil else { return }
        isActive = true

        job.getaway.identity.tlsActive = true
        job.serverPhase = .running(lease: self)
        job.engageIdleTimerProtection()

        job.startAccessibilityObservation()
        job.startLifecycleObservation()

        job.tripwire.onTransition = { [weak job] transition in
            job?.handlePulseTransition(transition)
        }
        job.tripwire.startPulse()
        job.brains.startKeyboardObservation()

        if resumePolling {
            job.pollingRuntime.resumeIfPaused(makeTask: job.makePollingTask(interval:))
        }
    }

    func release(from job: TheInsideJob, policy: ReleasePolicy) -> Task<Void, Never>? {
        guard isActive else {
            return releaseTask
        }

        isActive = false
        let stopTask = transport.stop()
        releaseTask = stopTask

        switch policy {
        case .suspend:
            job.pollingRuntime.pauseIfActive()
            job.restoreIdleTimerProtection(clearBaseline: false)
        case .stop:
            job.stopPolling()
            job.stopLifecycleObservation()
            job.restoreIdleTimerProtection(clearBaseline: true)
        }

        job.tripwire.stopPulse()
        job.tripwire.onTransition = nil
        job.brains.stopKeyboardObservation()
        job.stopAccessibilityObservation()

        return stopTask
    }
}

@MainActor
final class InsideJobPollingRuntime {
    enum Phase {
        case disabled
        case active(task: Task<Void, Never>, interval: TimeInterval)
        case paused(interval: TimeInterval)
    }

    var phase: Phase = .disabled

    var isEnabled: Bool {
        switch phase {
        case .active, .paused: return true
        case .disabled: return false
        }
    }

    func timeoutSeconds(default defaultValue: TimeInterval) -> TimeInterval {
        switch phase {
        case .active(_, let interval), .paused(let interval): return interval
        case .disabled: return defaultValue
        }
    }

    func start(interval requestedInterval: TimeInterval, makeTask: (TimeInterval) -> Task<Void, Never>) {
        if case .active(let existingTask, _) = phase {
            existingTask.cancel()
        }
        let interval = max(0.5, requestedInterval)
        phase = .active(task: makeTask(interval), interval: interval)
    }

    func stop() {
        if case .active(let task, _) = phase {
            task.cancel()
        }
        phase = .disabled
    }

    func pauseIfActive() {
        guard case .active(let task, let interval) = phase else { return }
        task.cancel()
        phase = .paused(interval: interval)
    }

    func resumeIfPaused(makeTask: (TimeInterval) -> Task<Void, Never>) {
        guard case .paused(let interval) = phase else { return }
        phase = .active(task: makeTask(interval), interval: interval)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

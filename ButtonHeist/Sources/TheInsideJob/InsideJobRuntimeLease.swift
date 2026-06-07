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
    let bonjourServiceName: String?
    private var isActive = false
    private var releaseTask: Task<Void, Never>?

    init(
        transport: ServerTransport,
        actualPort: UInt16,
        bonjourServiceName: String?
    ) {
        self.transport = transport
        self.actualPort = actualPort
        self.bonjourServiceName = bonjourServiceName
    }

    func activate(on job: TheInsideJob) {
        guard !isActive, releaseTask == nil else { return }
        isActive = true

        job.getaway.identity.tlsActive = true
        job.serverPhase = .running(lease: self)
        job.engageIdleTimerProtection()

        job.startLifecycleObservation()

        job.tripwire.startPulse()
        job.brains.startSemanticObservation()
        job.brains.safecracker.startKeyboardObservation()
    }

    func release(from job: TheInsideJob, policy: ReleasePolicy) -> Task<Void, Never>? {
        guard isActive else {
            return releaseTask
        }

        isActive = false
        let stopTask = transport.stop()
        releaseTask = stopTask

        job.releaseRuntimeOwnedResources(policy: policy)

        return stopTask
    }
}

@MainActor
extension TheInsideJob {
    func releaseRuntimeOwnedResources(policy: InsideJobRuntimeLease.ReleasePolicy) {
        switch policy {
        case .suspend:
            restoreIdleTimerProtection(clearBaseline: false)
        case .stop:
            stopLifecycleObservation()
            restoreIdleTimerProtection(clearBaseline: true)
        }

        brains.stopSemanticObservation()
        tripwire.stopPulse()
        brains.safecracker.stopKeyboardObservation()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

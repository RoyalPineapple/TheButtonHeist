#if canImport(UIKit)
#if DEBUG
import UIKit

@MainActor
extension TheInsideJob {
    func activateRuntime(_ resources: InsideJobRuntimeResources) {
        getaway.identity.tlsActive = true

        installLifecycleObservationIfNeeded()
        engageIdleTimerProtection(baseline: resources.idleTimerBaseline)

        tripwire.startPulse()
        brains.startSemanticObservation()
        brains.safecracker.startKeyboardObservation()

        serverPhase = .running(resources)
    }

    func releaseRuntimeOwnedResources(policy: RuntimeReleasePolicy, idleTimerBaseline: Bool) {
        switch policy {
        case .suspend:
            restoreIdleTimerProtection(to: idleTimerBaseline)
        case .stop:
            stopLifecycleObservationIfNeeded()
            restoreIdleTimerProtection(to: idleTimerBaseline)
        }

        brains.stopSemanticObservation()
        tripwire.stopPulse()
        brains.safecracker.stopKeyboardObservation()
    }

    func engageIdleTimerProtection(baseline: Bool) {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func restoreIdleTimerProtection(to baseline: Bool) {
        UIApplication.shared.isIdleTimerDisabled = baseline
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

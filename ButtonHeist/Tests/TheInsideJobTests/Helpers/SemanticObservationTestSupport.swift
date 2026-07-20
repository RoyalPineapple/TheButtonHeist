#if canImport(UIKit)
@testable import TheInsideJob

extension SemanticObservationStream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        commitSettledVisibleObservation(
            .admittedForTesting(observation, tripwireSignal: currentTripwireSignal()),
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    @discardableResult
    func commitVisibleObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        commitSettledVisibleObservation(
            .admittedForTesting(
                observation,
                tripwireSignal: currentTripwireSignal(),
                lineageEvidence: .viewportMovement
            ),
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        commitSettledDiscoveryObservation(
            .admittedForTesting(observation, tripwireSignal: currentTripwireSignal()),
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        commitSettledDiscoveryObservation(
            .admittedForTesting(
                observation,
                tripwireSignal: currentTripwireSignal(),
                lineageEvidence: .viewportMovement
            ),
            notificationBatch: notificationBatch
        )
    }
}

extension TheVault {
    func installObservationForTesting(_ observation: InterfaceObservation) {
        semanticObservationStream.commitVisibleObservationForTesting(observation)
    }
}

@MainActor
final class VisibleObservationSourceFixture {
    private enum Source {
        case liveCapture
        case observation(InterfaceObservation?)
    }

    private var source: Source = .liveCapture

    var observation: InterfaceObservation? {
        get {
            guard case .observation(let observation) = source else { return nil }
            return observation
        }
        set {
            source = .observation(newValue)
        }
    }

    func capture(from vault: TheVault) -> InterfaceObservation? {
        switch source {
        case .liveCapture:
            return TheVault.captureVisibleObservation(from: vault)
        case .observation(let observation):
            return observation
        }
    }

    func useLiveCapture() {
        source = .liveCapture
    }
}
#endif

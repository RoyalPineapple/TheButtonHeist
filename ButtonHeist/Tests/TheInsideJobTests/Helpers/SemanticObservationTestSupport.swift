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
            .uncheckedForTesting(observation, tripwireSignal: currentTripwireSignal()),
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
            .uncheckedForTesting(
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
            .uncheckedForTesting(observation, tripwireSignal: currentTripwireSignal()),
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        commitSettledDiscoveryObservation(
            .uncheckedForTesting(
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
        nextVisibleRefreshObservationForTesting = observation
        semanticObservationStream.commitVisibleObservationForTesting(observation)
    }

    func clearInstalledVisibleRefreshObservationForTesting() {
        nextVisibleRefreshObservationForTesting = nil
    }
}
#endif

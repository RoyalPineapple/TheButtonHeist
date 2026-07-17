#if canImport(UIKit)
@testable import TheInsideJob

extension InterfaceObservationProof {
    static func forTesting(_ observation: InterfaceObservation) -> Self {
        .uncheckedForTesting(observation)
    }

    static func forTestingAfterViewportMovement(_ observation: InterfaceObservation) -> Self {
        .uncheckedForTesting(observation, lineageEvidence: .viewportMovement)
    }
}

extension SemanticObservationStream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        commitSettledVisibleObservation(
            .forTesting(observation),
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
            .forTestingAfterViewportMovement(observation),
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        commitSettledDiscoveryObservation(.forTesting(observation), notificationBatch: notificationBatch)
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        commitSettledDiscoveryObservation(
            .forTestingAfterViewportMovement(observation),
            notificationBatch: notificationBatch
        )
    }
}

extension TheStash {
    func installObservationForTesting(_ observation: InterfaceObservation) {
        nextVisibleRefreshObservationForTesting = observation
        semanticObservationStream.commitVisibleObservationForTesting(observation)
    }

    func clearInstalledVisibleRefreshObservationForTesting() {
        nextVisibleRefreshObservationForTesting = nil
    }
}
#endif

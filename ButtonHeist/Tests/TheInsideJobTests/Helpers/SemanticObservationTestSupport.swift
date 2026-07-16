#if canImport(UIKit)
@testable import TheInsideJob

extension InterfaceObservationProof {
    static func forTesting(_ screen: InterfaceObservation) -> Self {
        .uncheckedForTesting(screen)
    }

    static func forTestingAfterViewportMovement(_ screen: InterfaceObservation) -> Self {
        .uncheckedForTesting(screen, lineageEvidence: .viewportMovement)
    }
}

extension SemanticObservationStream {
    @discardableResult
    func commitVisibleObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledVisibleObservation(
            .forTesting(screen),
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    @discardableResult
    func commitVisibleObservationAfterViewportMovementForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledVisibleObservation(
            .forTestingAfterViewportMovement(screen),
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    @discardableResult
    func commitDiscoveryObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledDiscoveryObservation(.forTesting(screen), notificationBatch: notificationBatch)
    }

    @discardableResult
    func commitDiscoveryObservationAfterViewportMovementForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledDiscoveryObservation(
            .forTestingAfterViewportMovement(screen),
            notificationBatch: notificationBatch
        )
    }
}

extension TheStash {
    func installScreenForTesting(_ screen: InterfaceObservation) {
        nextVisibleRefreshScreenForTesting = screen
        semanticObservationStream.commitVisibleObservationForTesting(screen)
    }

    func clearInstalledVisibleRefreshScreenForTesting() {
        nextVisibleRefreshScreenForTesting = nil
    }
}
#endif

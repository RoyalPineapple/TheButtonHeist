#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

@MainActor
final class InteractionCoordinator {
    private static let defaultTimeoutSeconds =
        SemanticObservationTiming.defaultTimeout / .seconds(1)

    private let vault: TheVault

    init(vault: TheVault) {
        self.vault = vault
    }

    func refreshedVisibleObservation(
        timeout: Double? = InteractionCoordinator.defaultTimeoutSeconds
    ) async -> VisibleObservationOutcome {
        await vault.semanticObservationStream.refreshedVisibleObservation(timeout: timeout)
    }

    func admittedVisibleObservation(
        timeout: Double? = InteractionCoordinator.defaultTimeoutSeconds
    ) async -> TheVault.State.Current? {
        await vault.semanticObservationStream.admittedVisibleObservation(timeout: timeout)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

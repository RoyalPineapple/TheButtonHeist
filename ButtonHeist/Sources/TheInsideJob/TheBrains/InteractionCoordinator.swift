#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
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
    ) async -> TheVault.State.Current? {
        await vault.semanticObservationStream.refreshedVisibleObservation(timeout: timeout)
    }

    func admittedVisibleObservation(
        timeout: Double? = InteractionCoordinator.defaultTimeoutSeconds
    ) async -> TheVault.State.Current? {
        await vault.semanticObservationStream.admittedVisibleObservation(timeout: timeout)
    }

    func settledCurrent(
        scope: SemanticObservationScope,
        after historyIndex: Int?,
        timeout: Double?
    ) async -> TheVault.State.Current? {
        if historyIndex == nil, timeout == 0 {
            return await vault.semanticObservationStream.admittedObservation(
                scope: scope,
                after: nil
            )
        }
        return await vault.semanticObservationStream.nextObservation(
            scope: scope,
            after: historyIndex,
            timeout: timeout ?? Self.defaultTimeoutSeconds
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

@MainActor
final class InteractionCoordinator {
    private static let defaultVisibleStateTimeout = Double(SettleSession.defaultTimeoutMs) / 1_000

    private let vault: TheVault

    init(vault: TheVault) {
        self.vault = vault
    }

    func refreshedVisibleObservation(
        timeout: Double? = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> Observation.Store.AdmittedObservation? {
        await vault.semanticObservationStream.refreshedVisibleObservation(timeout: timeout)
    }

    func admittedVisibleObservation(
        timeout: Double? = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> Observation.Store.AdmittedObservation? {
        await vault.semanticObservationStream.admittedVisibleObservation(timeout: timeout)
    }

    func settledEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> Observation.SnapshotEvent? {
        if sequence == nil, timeout == 0 {
            return await vault.semanticObservationStream.admittedObservation(
                scope: scope,
                after: nil
            )?.event
        }
        return await vault.semanticObservationStream.settledEvent(
            scope: scope,
            after: sequence,
            timeout: timeout ?? SemanticObservationTiming.defaultTimeout
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

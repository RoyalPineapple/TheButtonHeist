#if canImport(UIKit)
#if DEBUG
import Foundation

enum SemanticObservationSettleCadence {
    static let activePassiveSettleTimeoutMs = 1_000
    static let activeQuietWindowMs = 60

    @MainActor
    static func settleVisibleObservationForCurrentDemand(
        demandState: SemanticObservationDemandState,
        vault: TheVault,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        switch demandState {
        case .active:
            return await settleVisibleObservationAtActiveCadence(
                vault: vault,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs
            )
        case .idle:
            return await settleVisibleObservationAtIdleCadence(
                vault: vault,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs
            )
        }
    }

    @MainActor
    static func settleVisibleObservationAtIdleCadence(
        vault: TheVault,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        let settleSession = SettleSession.live(
            vault: vault,
            tripwire: tripwire,
            timeoutMs: timeoutMs
        )
        return await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineTripwireSignal
        )
    }

    @MainActor
    static func settleVisibleObservationAtActiveCadence(
        vault: TheVault,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        let settleSession = SettleSession.live(
            vault: vault,
            tripwire: tripwire,
            timeoutMs: timeoutMs,
            policy: .quietWindow(milliseconds: activeQuietWindowMs)
        )
        return await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineTripwireSignal
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

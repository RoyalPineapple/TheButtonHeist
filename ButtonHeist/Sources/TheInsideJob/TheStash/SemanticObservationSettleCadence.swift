#if canImport(UIKit)
#if DEBUG
import Foundation

enum SemanticObservationSettleCadence {
    static let activePassiveSettleTimeoutMs = 1_000

    @MainActor
    static func settleVisibleObservationForCurrentDemand(
        demandState: SemanticObservationDemandState,
        stash: TheStash,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        switch demandState {
        case .active:
            return await settleVisibleObservationAtActiveCadence(
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs
            )
        case .idle:
            return await settleVisibleObservationAtIdleCadence(
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs
            )
        }
    }

    @MainActor
    static func settleVisibleObservationAtIdleCadence(
        stash: TheStash,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        let settleSession = SettleSession.live(
            stash: stash,
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
        stash: TheStash,
        tripwire: TheTripwire,
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int
    ) async -> SettleSession.Outcome {
        let settleSession = SemanticQuietSettleSession.live(
            stash: stash,
            tripwire: tripwire,
            quietWindowMs: SemanticQuietSettleSession.defaultQuietWindowMs,
            timeoutMs: timeoutMs
        )
        return await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineTripwireSignal
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
@testable import TheInsideJob

@MainActor
extension PostActionObservation {
    /// Test-only projection helper. Production callers must supply a settled
    /// observation or explicit screen evidence through the interaction gateway.
    func captureSemanticState() -> BeforeState {
        let latestEvent = stash.latestSettledSemanticObservationEvent
        return captureSemanticState(
            from: stash.settledSemanticScreen,
            tripwireSignal: latestEvent?.observation.tripwireSignal ?? .empty,
            settledObservationSequence: latestEvent?.sequence
        )
    }
}
#endif

#if canImport(UIKit)
@testable import TheInsideJob

@MainActor
extension PostActionObservation {
    /// Test-only projection helper. Production callers must supply a settled
    /// observation or explicit screen evidence through the interaction gateway.
    func captureSemanticState() -> BeforeState {
        captureSemanticState(
            from: stash.settledSemanticScreen,
            tripwireSignal: tripwire.tripwireSignal(),
            settledObservationSequence: stash.latestSettledSemanticObservationEvent?.sequence
        )
    }
}
#endif

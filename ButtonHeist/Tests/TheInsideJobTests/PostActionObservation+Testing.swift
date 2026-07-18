#if canImport(UIKit)
@testable import TheInsideJob

@MainActor
extension PostActionObservation {
    /// Test-only projection helper. Production callers must supply a settled
    /// observation or explicit screen evidence through the interaction gateway.
    func captureSemanticState() -> ObservationBaseline {
        let latestEvent = vault.semanticObservationStream.latestEvent
        return captureSemanticState(
            from: InterfaceObservation.makeForTests(
                tree: vault.interfaceTree,
                liveCapture: LiveCapture.makeForTests(snapshot: vault.interfaceTree.viewportCapture)
            ),
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: latestEvent?.sequence
        )
    }
}
#endif

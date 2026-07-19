#if canImport(UIKit)
@testable import TheInsideJob

@MainActor
extension ActionEvidenceProjector {
    /// Test-only projection helper. Production callers must supply a settled
    /// observation or explicit screen evidence through `InteractionCoordinator`.
    func projectBaseline() -> Baseline {
        let latestCommittedEvent = vault.semanticObservationStream.latestCommittedEvent
        return projectBaseline(
            from: InterfaceObservation.makeForTests(
                tree: vault.interfaceTree,
                liveCapture: LiveCapture.makeForTests(snapshot: vault.interfaceTree.viewportCapture)
            ),
            tripwireSignal: vault.tripwire.tripwireSignal(),
            settledObservationSequence: latestCommittedEvent?.sequence
        )
    }
}
#endif

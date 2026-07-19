#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import TheScore

// MARK: - Interface State

extension TheVault {

    func resetInterfaceForLifecycle() {
        latestObservation = .empty
        latestFailedSettleDiagnosticEvidence = nil
        nextVisibleRefreshObservationForTesting = nil
        semanticObservationStream.clearCurrentInterface()
    }

    /// Clear stale interface state at a top-level heist boundary while leaving a
    /// queued synthetic visible refresh intact for in-process runtime tests.
    func resetInterfaceForHeistBootstrap() {
        let queuedVisibleRefresh = nextVisibleRefreshObservationForTesting
        resetInterfaceForLifecycle()
        nextVisibleRefreshObservationForTesting = queuedVisibleRefresh
    }

    func invalidateSettledObservationFromTripwire() {
        nextVisibleRefreshObservationForTesting = nil
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    /// Refresh the latest live viewport evidence. The returned value remains the raw
    /// capture-local observation for geometry and exploration consumers.
    @discardableResult
    func refreshLiveCapture() -> InterfaceObservation? {
        guard let observation = nextVisibleRefreshObservationForTesting
            ?? capture().map(Self.buildObservation(from:)) else { return nil }
        observeInterface(observation)
        return observation
    }

    func recordCommittedObservation(
        _ observation: InterfaceObservation,
        sourceObservation: InterfaceObservation
    ) {
        if let queuedVisibleRefresh = nextVisibleRefreshObservationForTesting,
           queuedVisibleRefresh.tree.interfaceHash != sourceObservation.tree.interfaceHash {
            nextVisibleRefreshObservationForTesting = nil
        }
        observeInterface(observation)
        latestFailedSettleDiagnosticEvidence = nil
    }

    func recordFailedSettleDiagnosticEvidence(_ observation: InterfaceObservation?) {
        latestFailedSettleDiagnosticEvidence = observation
        semanticObservationStream.invalidateLatestSettledObservation()
    }

    func observeInterface(_ observation: InterfaceObservation) {
        latestObservation = observation
    }

    /// Starting value for page-by-page exploration. The tree's value-only
    /// viewport capture is the evidence that belongs to this committed state;
    /// a fresh parser read replaces it before exploration performs live work.
    func interfaceMemoryBaseline() -> InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: interfaceTree)
        } catch {
            preconditionFailure("Exploration baseline failed validation: \(error)")
        }
    }

    /// Starting value for public interface discovery after a visible settle.
    ///
    /// Public reads should describe the current screen. Discovery-only memory
    /// from a prior screen can share generated container names with the current
    /// screen, so command-owned interface exploration starts from visible
    /// current-screen state and grows from there.
    func visibleExplorationBaseline(
        from viewportObservation: InterfaceObservation
    ) -> InterfaceObservation {
        viewportObservation.viewportOnly
    }

    func firstResponderInterfaceElement() -> InterfaceTree.Element? {
        guard let heistId = firstResponderHeistId else { return nil }
        return treeElement(heistId: heistId, in: .interface)
    }

    func semanticInterface(
        for observation: InterfaceObservation,
        timestamp: Date = Date()
    ) -> Interface {
        WireConversion.toSemanticInterface(from: observation.tree, timestamp: timestamp)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

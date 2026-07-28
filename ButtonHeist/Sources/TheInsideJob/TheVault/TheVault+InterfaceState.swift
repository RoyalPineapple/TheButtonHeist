#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser
import TheScore

// MARK: - Interface State

extension TheVault {

    func resetInterfaceForLifecycle() async {
        latestObservation = .empty
        latestFailedSettleDiagnosticEvidence = nil
        await semanticObservationStream.discardCurrentObservation()
    }

    /// The tripwire saw the screen go.
    ///
    /// The world said so, so what the vault holds describes a screen that is no
    /// longer there.
    func invalidateSettledObservationFromTripwire() async {
        await semanticObservationStream.discardCurrentObservation()
    }

    /// Refresh the latest live viewport evidence. The returned value remains the raw
    /// capture-local observation for geometry and exploration consumers.
    @discardableResult
    func refreshLiveCapture() -> InterfaceObservation? {
        guard let observation = captureVisibleObservation() else { return nil }
        observeInterface(observation)
        return observation
    }

    func recordCommittedObservation(
        _ observation: InterfaceObservation,
        sourceObservation _: InterfaceObservation
    ) {
        observeInterface(observation)
        latestFailedSettleDiagnosticEvidence = nil
    }

    /// Records what the tree looked like when a settle timed out.
    ///
    /// Diagnostic evidence sits beside settled truth rather than replacing it: a
    /// settle that failed says the run stopped waiting, not that the last thing
    /// read stopped being the last thing read. A target still resolves against
    /// the settled tree, which is why this holds the timed-out reading somewhere
    /// a report can quote and nowhere a resolution can see.
    func recordFailedSettleDiagnosticEvidence(_ observation: InterfaceObservation?) async {
        latestFailedSettleDiagnosticEvidence = observation
    }

    func observeInterface(_ observation: InterfaceObservation) {
        latestObservation = observation
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

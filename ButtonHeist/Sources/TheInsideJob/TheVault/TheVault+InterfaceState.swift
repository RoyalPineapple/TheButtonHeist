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

    func recordFailedSettleDiagnosticEvidence(_ observation: InterfaceObservation?) async {
        latestFailedSettleDiagnosticEvidence = observation
        await semanticObservationStream.discardCurrentObservation()
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

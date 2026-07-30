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
        semanticObservationStream.discardCurrentObservation()
    }

    func recordCommittedObservation(_ observation: InterfaceObservation) {
        observeInterface(observation)
    }

    func observeInterface(_ observation: InterfaceObservation) {
        latestObservation = observation
    }

    func firstResponderInterfaceElement() -> InterfaceTree.Element? {
        guard let heistId = firstResponderHeistId else { return nil }
        return treeElement(heistId: heistId, in: .interface)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

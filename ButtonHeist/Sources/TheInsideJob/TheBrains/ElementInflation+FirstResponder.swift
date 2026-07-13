#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        guard let firstResponderHeistId = stash.firstResponderHeistId,
              let treeElement = stash.interfaceElement(heistId: firstResponderHeistId),
              let target = stash.minimumUniqueTarget(for: treeElement) else { return nil }
        switch await inflate(
            for: target,
            method: method
        ) {
        case .inflated(let inflatedTarget):
            return Self.firstResponderIdentityFailure(
                expected: firstResponderHeistId,
                current: stash.firstResponderHeistId,
                inflated: inflatedTarget.treeElement.heistId
            )
        case .failed(let failure):
            return failure
        }
    }

    internal static func firstResponderIdentityFailure(
        expected: HeistId,
        current: HeistId?,
        inflated: HeistId
    ) -> ElementInflationFailure? {
        guard current == expected, inflated == expected else {
            return .staleRefresh(
                "first responder no longer matches captured HeistId \(expected) after inflation",
                failureKind: .targetUnavailable
            )
        }
        return nil
    }
}

#endif // canImport(UIKit) && DEBUG

#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        guard let treeElement = stash.firstResponderInterfaceElement(),
              let target = stash.minimumUniqueTarget(for: treeElement) else { return nil }
        switch await inflate(
            for: target,
            method: method,
            deallocatedBoundary: "first responder inflation"
        ) {
        case .inflated:
            return nil
        case .failed(let failure):
            return failure
        }
    }
}

#endif // canImport(UIKit) && DEBUG

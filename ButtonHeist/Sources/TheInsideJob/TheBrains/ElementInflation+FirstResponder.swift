#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        guard let screenElement = stash.firstResponderScreenElement(),
              let target = stash.minimumUniqueTarget(for: screenElement) else { return nil }
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

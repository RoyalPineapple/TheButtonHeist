#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        guard let screenElement = stash.firstResponderScreenElement(),
              let target = firstResponderTarget(for: screenElement) else { return nil }
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

    private func firstResponderTarget(for screenElement: TheStash.ScreenElement) -> ElementTarget? {
        stash.minimumUniqueTarget(for: screenElement)
    }
}

#endif // canImport(UIKit) && DEBUG

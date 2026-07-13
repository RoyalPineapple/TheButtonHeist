#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal func inflateFirstResponder(method: ActionMethod) async -> ElementInflationFailure? {
        await inflateFirstResponder(method: method) { target, method in
            await self.inflate(for: target, method: method)
        }
    }

    internal func inflateFirstResponder(
        method: ActionMethod,
        inflateTarget: @MainActor (AccessibilityTarget, ActionMethod) async -> ElementInflationResult
    ) async -> ElementInflationFailure? {
        guard let firstResponderHeistId = stash.firstResponderHeistId,
              let treeElement = stash.interfaceElement(heistId: firstResponderHeistId),
              let target = stash.minimumUniqueTarget(for: treeElement) else { return nil }
        switch await inflateTarget(target, method) {
        case .inflated(let inflatedTarget):
            guard stash.firstResponderHeistId == firstResponderHeistId,
                  inflatedTarget.treeElement.heistId == firstResponderHeistId else {
                return .staleRefresh(
                    "first responder no longer matches captured HeistId \(firstResponderHeistId) after inflation",
                    failureKind: .targetUnavailable
                )
            }
            return nil
        case .failed(let failure):
            return failure
        }
    }
}

#endif // canImport(UIKit) && DEBUG

#if canImport(UIKit) && DEBUG
import UIKit

import TheScore
import ThePlans

extension ElementInflation {

    internal enum FirstResponderInflation {
        case unavailable
        case inflated(InflatedElementTarget)
        case failed(ElementInflationFailure)
    }

    internal func inflateFirstResponder(method: ActionMethod) async -> FirstResponderInflation {
        await inflateFirstResponder(method: method) { target, method in
            await self.inflate(for: target, method: method)
        }
    }

    internal func inflateFirstResponder(
        method: ActionMethod,
        inflateTarget: @MainActor (AccessibilityTarget, ActionMethod) async -> ElementInflationResult
    ) async -> FirstResponderInflation {
        guard let firstResponderHeistId = stash.firstResponderHeistId,
              let treeElement = stash.interfaceElement(heistId: firstResponderHeistId),
              let target = stash.minimumUniqueTarget(for: treeElement) else { return .unavailable }
        switch await inflateTarget(target, method) {
        case .inflated(let inflatedTarget):
            guard stash.firstResponderHeistId == firstResponderHeistId,
                  inflatedTarget.treeElement.heistId == firstResponderHeistId else {
                return .failed(.staleRefresh(
                    "first responder no longer matches captured HeistId \(firstResponderHeistId) after inflation",
                    failureKind: .targetUnavailable
                ))
            }
            return .inflated(inflatedTarget)
        case .failed(let failure):
            return .failed(failure)
        }
    }
}

#endif // canImport(UIKit) && DEBUG

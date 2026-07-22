#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    func availableScreenActions() -> [ScreenAction] {
        accessibilityActions.availableScreenActions(
            startingAt: screenActionStartingObject(),
            fallback: tripwire.topmostViewController()
        )
    }

    func executeDismiss(
    ) async -> TheSafecracker.ActionDispatchResult {
        screenActionResult(
            accessibilityActions.dismiss(
                startingAt: screenActionStartingObject(),
                fallback: tripwire.topmostViewController()
            ),
            payload: .dismiss,
            missingHandlerMessage: "no escape handler in responder chain"
        )
    }

    func executeMagicTap(
    ) async -> TheSafecracker.ActionDispatchResult {
        screenActionResult(
            accessibilityActions.magicTap(
                startingAt: screenActionStartingObject(),
                fallback: tripwire.topmostViewController()
            ),
            payload: .magicTap,
            missingHandlerMessage: "no magic tap handler in responder chain"
        )
    }

    private func screenActionStartingObject() -> NSObject? {
        guard let treeElement = vault.firstResponderInterfaceElement() else { return nil }
        return vault.liveObject(for: treeElement)
    }

    private func screenActionResult(
        _ outcome: AccessibilityActionDispatcher.ScreenActionOutcome,
        payload: ActionResult.Payload,
        missingHandlerMessage: String
    ) -> TheSafecracker.ActionDispatchResult {
        switch outcome {
        case .succeeded(let handler):
            return .success(payload: payload, screenActionHandler: handler)
        case .noHandler:
            return .failure(payload, message: missingHandlerMessage)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

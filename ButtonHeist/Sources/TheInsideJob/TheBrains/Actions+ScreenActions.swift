#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension Actions {

    // MARK: - InterfaceObservation Actions

    func availableScreenActions() -> [ScreenAction] {
        accessibilityActions.availableScreenActions(
            startingAt: screenActionStartingObject(),
            fallback: tripwire.topmostViewController()
        )
    }

    func executeDismiss() async -> TheSafecracker.ActionDispatchOutcome {
        screenActionResult(
            accessibilityActions.dismiss(
                startingAt: screenActionStartingObject(),
                fallback: tripwire.topmostViewController()
            ),
            method: .dismiss,
            missingHandlerMessage: "no escape handler in responder chain"
        )
    }

    func executeMagicTap() async -> TheSafecracker.ActionDispatchOutcome {
        screenActionResult(
            accessibilityActions.magicTap(
                startingAt: screenActionStartingObject(),
                fallback: tripwire.topmostViewController()
            ),
            method: .magicTap,
            missingHandlerMessage: "no magic tap handler in responder chain"
        )
    }

    private func screenActionStartingObject() -> NSObject? {
        guard let treeElement = stash.firstResponderInterfaceElement() else { return nil }
        return stash.liveObject(for: treeElement)
    }

    private func screenActionResult(
        _ outcome: AccessibilityActionDispatcher.ScreenActionOutcome,
        method: ActionMethod,
        missingHandlerMessage: String
    ) -> TheSafecracker.ActionDispatchOutcome {
        switch outcome {
        case .succeeded(let handler):
            return .success(method: method, message: "Handler: \(handler)")
        case .noHandler:
            return .failure(method, message: missingHandlerMessage)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

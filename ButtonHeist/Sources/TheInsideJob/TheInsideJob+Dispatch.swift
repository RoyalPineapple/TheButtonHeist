#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

extension TheInsideJob {

    /// Route interaction messages through the standard
    /// refresh-snapshot-execute-delta pipeline.
    func dispatchInteraction(_ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void) async {
        switch message {
        case .activate, .increment, .decrement, .performCustomAction,
             .editAction, .setPasteboard, .getPasteboard, .resignFirstResponder:
            await dispatchAccessibilityAction(message, requestId: requestId, respond: respond)

        case .touchTap, .touchLongPress, .touchSwipe, .touchDrag,
             .touchPinch, .touchRotate, .touchTwoFingerTap,
             .touchDrawPath, .touchDrawBezier:
            await dispatchTouchGesture(message, requestId: requestId, respond: respond)

        case .typeText(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeTypeText(target) }
        case .scroll(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeScroll(target) }
        case .scrollToVisible(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeScrollToVisible(target) }
        case .elementSearch(let target):
            await performElementSearch(target: target, command: message, requestId: requestId, respond: respond)
        case .scrollToEdge(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeScrollToEdge(target) }
        case .waitFor(let target):
            await performWaitFor(target: target, command: message, requestId: requestId, respond: respond)
        case .explore:
            await performExplore(command: message, requestId: requestId, respond: respond)

        default:
            insideJobLogger.error("Unhandled message type in dispatchInteraction")
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .activate,
                message: "Unhandled command",
                errorKind: .unsupported,
                screenName: bagman.lastScreenName,
                screenId: bagman.lastScreenId
            )), requestId: requestId, respond: respond)
        }
    }

    // MARK: - Accessibility Actions

    private func dispatchAccessibilityAction(
        _ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void
    ) async {
        switch message {
        case .activate(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeActivate(target) }
        case .increment(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeIncrement(target) }
        case .decrement(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeDecrement(target) }
        case .performCustomAction(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeCustomAction(target) }
        case .editAction(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeEditAction(target) }
        case .setPasteboard(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeSetPasteboard(target) }
        case .getPasteboard:
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.bagman.executeGetPasteboard() }
        case .resignFirstResponder:
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeResignFirstResponder() }
        default:
            break
        }
    }

    // MARK: - Touch Gestures

    private func dispatchTouchGesture(
        _ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void
    ) async {
        switch message {
        case .touchTap(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeTap(target) }
        case .touchLongPress(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeLongPress(target) }
        case .touchSwipe(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeSwipe(target) }
        case .touchDrag(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeDrag(target) }
        case .touchPinch(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executePinch(target) }
        case .touchRotate(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeDrawPath(target) }
        case .touchDrawBezier(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeDrawBezier(target) }
        default:
            break
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

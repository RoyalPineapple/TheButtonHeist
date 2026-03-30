#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

// MARK: - Interaction Dispatch Helpers

extension TheInsideJob {

    /// Route interaction messages to TheSafecracker through the standard
    /// refresh-snapshot-execute-delta pipeline.
    func dispatchInteraction(_ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void) async {
        if await dispatchAccessibilityInteraction(message, requestId: requestId, respond: respond) { return }
        if await dispatchTouchInteraction(message, requestId: requestId, respond: respond) { return }
        if await dispatchTextAndScrollInteraction(message, requestId: requestId, respond: respond) { return }

        insideJobLogger.error("Unhandled message type in dispatchInteraction")
        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .activate,
            message: "Unhandled command",
            errorKind: .unsupported,
            screenName: bagman.lastScreenName
        )), requestId: requestId, respond: respond)
    }

    // MARK: - Accessibility Interactions

    /// Handles activate, increment, decrement, custom action, edit action, and resign first responder.
    /// Returns true if the message was handled.
    private func dispatchAccessibilityInteraction(
        _ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void
    ) async -> Bool {
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
            return false
        }
        return true
    }

    // MARK: - Touch Interactions

    /// Handles tap, long press, swipe, drag, pinch, rotate, two-finger tap, draw path, and draw bezier.
    /// Returns true if the message was handled.
    private func dispatchTouchInteraction(
        _ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void
    ) async -> Bool {
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
            guard target.points.count <= 10_000 else {
                let err = ActionResult(success: false, method: .syntheticDrawPath, message: "Too many points (max 10,000)",
                                       errorKind: .validationError, screenName: bagman.lastScreenName)
                sendMessage(.actionResult(err), requestId: requestId, respond: respond)
                return true
            }
            await performInteraction(command: message, requestId: requestId, respond: respond) {
                await self.bagman.executeDrawPath(target)
            }
        case .touchDrawBezier(let target):
            guard target.segments.count <= 1_000 else {
                let err = ActionResult(success: false, method: .syntheticDrawPath, message: "Too many segments (max 1,000)",
                                       errorKind: .validationError, screenName: bagman.lastScreenName)
                sendMessage(.actionResult(err), requestId: requestId, respond: respond)
                return true
            }
            await performInteraction(command: message, requestId: requestId, respond: respond) {
                await self.bagman.executeDrawBezier(target)
            }
        default:
            return false
        }
        return true
    }

    // MARK: - Text & Scroll Interactions

    /// Handles typeText, scroll, scrollToVisible, and scrollToEdge.
    /// Returns true if the message was handled.
    private func dispatchTextAndScrollInteraction(
        _ message: ClientMessage, requestId: String?, respond: @escaping (Data) -> Void
    ) async -> Bool {
        switch message {
        case .typeText(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeTypeText(target) }
        case .scroll(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeScroll(target) }
        case .scrollToVisible(let target):
            await performScrollToVisibleSearch(target: target, command: message, requestId: requestId, respond: respond)
        case .scrollToEdge(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.bagman.executeScrollToEdge(target) }
        case .waitFor(let target):
            await performWaitFor(target: target, command: message, requestId: requestId, respond: respond)
        case .explore:
            await performExplore(command: message, requestId: requestId, respond: respond)
        default:
            return false
        }
        return true
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

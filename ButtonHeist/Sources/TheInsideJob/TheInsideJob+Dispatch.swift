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
            message: "Unhandled command"
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
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeActivate(target) }
        case .increment(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeIncrement(target) }
        case .decrement(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeDecrement(target) }
        case .performCustomAction(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeCustomAction(target) }
        case .editAction(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeEditAction(target) }
        case .setPasteboard(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeSetPasteboard(target) }
        case .getPasteboard:
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeGetPasteboard() }
        case .resignFirstResponder:
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeResignFirstResponder() }
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
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeTap(target) }
        case .touchLongPress(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeLongPress(target) }
        case .touchSwipe(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeSwipe(target) }
        case .touchDrag(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeDrag(target) }
        case .touchPinch(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executePinch(target) }
        case .touchRotate(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeRotate(target) }
        case .touchTwoFingerTap(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeTwoFingerTap(target) }
        case .touchDrawPath(let target):
            guard target.points.count <= 10_000 else {
                let err = ActionResult(success: false, method: .syntheticDrawPath, message: "Too many points (max 10,000)")
                sendMessage(.actionResult(err), requestId: requestId, respond: respond)
                return true
            }
            await performInteraction(command: message, requestId: requestId, respond: respond) {
                await self.theSafecracker.executeDrawPath(target)
            }
        case .touchDrawBezier(let target):
            guard target.segments.count <= 1_000 else {
                let err = ActionResult(success: false, method: .syntheticDrawPath, message: "Too many segments (max 1,000)")
                sendMessage(.actionResult(err), requestId: requestId, respond: respond)
                return true
            }
            await performInteraction(command: message, requestId: requestId, respond: respond) {
                await self.theSafecracker.executeDrawBezier(target)
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
            await performInteraction(command: message, requestId: requestId, respond: respond) { await self.theSafecracker.executeTypeText(target) }
        case .scroll(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeScroll(target) }
        case .scrollToVisible(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeScrollToVisible(target) }
        case .scrollToEdge(let target):
            await performInteraction(command: message, requestId: requestId, respond: respond) { self.theSafecracker.executeScrollToEdge(target) }
        default:
            return false
        }
        return true
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

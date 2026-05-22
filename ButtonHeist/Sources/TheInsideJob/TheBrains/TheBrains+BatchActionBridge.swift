#if canImport(UIKit)
#if DEBUG
import TheScore

/// Bridges typed batch action primitives onto the existing InsideJob command
/// surface. This is an adapter boundary only: batch execution still runs
/// through the same command behavior as single actions.
enum BatchActionClientMessageBridge {
    static func operationName(for operation: TheScore.BatchOperation) -> String {
        switch operation {
        case .action(let action):
            return actionName(for: action)
        case .checkpoint(let checkpoint):
            return checkpoint.name.map { "checkpoint:\($0)" } ?? "checkpoint"
        }
    }

    static func fulfillsOwnExpectation(_ operation: TheScore.BatchOperation) -> Bool {
        switch operation {
        case .action(let action):
            return fulfillsOwnExpectation(action)
        case .checkpoint:
            return false
        }
    }

    static func actionName(for action: TheScore.Action) -> String {
        switch action {
        case .waitForIdle:
            return "wait_for_idle"
        case .waitForElement:
            return "wait_for"
        case .waitForChange:
            return "wait_for_change"
        default:
            return clientMessage(for: action)?.canonicalName ?? action.description
        }
    }

    static func fulfillsOwnExpectation(_ action: TheScore.Action) -> Bool {
        switch action {
        case .waitForElement, .waitForChange:
            return true
        default:
            return false
        }
    }

    static func clientMessage(for action: TheScore.Action) -> ClientMessage? {
        switch action {
        case .activate(let target):
            return .activate(target.executableTarget)
        case .increment(let target):
            return .increment(target.executableTarget)
        case .decrement(let target):
            return .decrement(target.executableTarget)
        case .performCustomAction(let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: target.target.executableTarget,
                actionName: target.actionName
            ))
        case .rotor(let target):
            return .rotor(RotorTarget(
                elementTarget: target.target.executableTarget,
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: target.direction,
                currentHeistId: target.currentSourceHeistId,
                currentTextRange: target.currentTextRange
            ))
        case .touchTap, .touchLongPress, .touchSwipe, .touchDrag,
             .touchPinch, .touchRotate, .touchTwoFingerTap,
             .touchDrawPath, .touchDrawBezier:
            return touchMessage(for: action)
        case .typeText, .editAction, .setPasteboard:
            return textEditingMessage(for: action)
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return scrollMessage(for: action)
        case .waitForIdle, .waitForElement, .waitForChange, .checkpoint:
            return nil
        case .explore:
            return .explore
        case .resignFirstResponder:
            return .resignFirstResponder
        }
    }

    private static func touchMessage(for action: TheScore.Action) -> ClientMessage? {
        switch action {
        case .touchTap(let target):
            return .touchTap(TouchTapTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY
            ))
        case .touchLongPress(let target):
            return .touchLongPress(LongPressTarget(
                elementTarget: target.target?.executableTarget,
                pointX: target.pointX,
                pointY: target.pointY,
                duration: target.duration
            ))
        case .touchSwipe(let target):
            return .touchSwipe(SwipeTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                direction: target.direction,
                duration: target.duration,
                start: target.start,
                end: target.end
            ))
        case .touchDrag(let target):
            return .touchDrag(DragTarget(
                elementTarget: target.target?.executableTarget,
                startX: target.startX,
                startY: target.startY,
                endX: target.endX,
                endY: target.endY,
                duration: target.duration
            ))
        case .touchPinch(let target):
            return .touchPinch(PinchTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                scale: target.scale,
                spread: target.spread,
                duration: target.duration
            ))
        case .touchRotate(let target):
            return .touchRotate(RotateTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                angle: target.angle,
                radius: target.radius,
                duration: target.duration
            ))
        case .touchTwoFingerTap(let target):
            return .touchTwoFingerTap(TwoFingerTapTarget(
                elementTarget: target.target?.executableTarget,
                centerX: target.centerX,
                centerY: target.centerY,
                spread: target.spread
            ))
        case .touchDrawPath(let target):
            return .touchDrawPath(target)
        case .touchDrawBezier(let target):
            return .touchDrawBezier(target)
        default:
            return nil
        }
    }

    private static func textEditingMessage(for action: TheScore.Action) -> ClientMessage? {
        switch action {
        case .typeText(let target):
            return .typeText(TypeTextTarget(
                text: target.text,
                elementTarget: target.target?.executableTarget
            ))
        case .editAction(let target):
            return .editAction(target)
        case .setPasteboard(let target):
            return .setPasteboard(target)
        default:
            return nil
        }
    }

    private static func scrollMessage(for action: TheScore.Action) -> ClientMessage? {
        switch action {
        case .scroll(let target):
            return .scroll(ScrollTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: target.target?.executableTarget
            ))
        case .elementSearch(let target):
            return .elementSearch(ElementSearchTarget(
                elementTarget: target.target?.executableTarget,
                direction: target.direction
            ))
        case .scrollToEdge(let target):
            return .scrollToEdge(ScrollToEdgeTarget(
                elementTarget: target.target?.executableTarget,
                edge: target.edge
            ))
        default:
            return nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

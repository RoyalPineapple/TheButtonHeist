import Foundation

public extension HeistActionCommand {
    var durableHeistActionFailure: String? {
        switch self {
        case .rotor(let selection, _, _):
            if case .named = selection { return nil }
            return "rotor selection \(selection) is not a durable heist action"
        case .mechanicalSwipe(let target):
            if target.duration != nil {
                return "swipe duration \(String(describing: target.duration)) is not a durable heist action"
            }
            switch target.selection {
            case .unitElement, .elementDirection, .point(.coordinate, .coordinate), .point(.coordinate, .direction):
                return nil
            case .point(.element, _), .point(.elementUnitPoint, _):
                return "swipe selection \(target.selection) is not a durable heist action"
            }
        case .mechanicalDrag(let target):
            if target.duration != nil {
                return "drag duration \(String(describing: target.duration)) is not a durable heist action"
            }
            return nil
        case .viewportScroll:
            return "scroll is a viewport debug command, not a durable heist action"
        case .viewportScrollToVisible:
            return "scroll_to_visible is a viewport debug command, not a durable heist action"
        case .viewportScrollToEdge:
            return "scroll_to_edge is a viewport debug command, not a durable heist action"
        case .activate, .increment, .decrement, .customAction, .typeText, .mechanicalTap, .mechanicalLongPress,
             .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            return nil
        }
    }

    var reportTarget: ElementTarget? {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            return target.reportTarget
        case .customAction(_, let target), .rotor(_, let target, _):
            return target.reportTarget
        case .typeText(_, let target, _):
            return target?.reportTarget
        case .mechanicalTap(let target):
            return target.selection.reportTarget
        case .mechanicalLongPress(let target):
            return target.selection.reportTarget
        case .mechanicalSwipe(let target):
            switch target.selection {
            case .unitElement(let target, _, _), .elementDirection(let target, _):
                return target
            case .point(let start, _):
                return start.reportTarget
            }
        case .mechanicalDrag(let target):
            return target.start.reportTarget
        case .viewportScroll(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .viewportScrollToEdge(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            return nil
        }
    }
}

private extension GesturePointSelection {
    var reportTarget: ElementTarget? {
        switch self {
        case .element(let target), .elementUnitPoint(let target, _):
            return target
        case .coordinate:
            return nil
        }
    }
}

private extension ElementTargetExpr {
    var reportTarget: ElementTarget? {
        try? resolve(in: .empty)
    }
}

import Foundation

public extension HeistActionCommand {
    var durableHeistActionFailure: String? {
        switch self {
        case .rotor(let selection, _, _):
            if case .named = selection { return nil }
            return "rotor selection \(selection) is not a durable heist action"
        case .mechanicalLongPress(let target):
            if case .element = target.selection, target.duration != .longPressDefault {
                return "long_press element duration \(target.duration) is not a durable heist action"
            }
            return nil
        case .mechanicalSwipe(let target):
            if target.duration != nil {
                return "swipe duration \(String(describing: target.duration)) is not a durable heist action"
            }
            switch target.selection {
            case .unitElement, .elementDirection, .point(.coordinate, .coordinate), .point(.coordinate, .direction):
                return nil
            case .point(.element, _):
                return "swipe selection \(target.selection) is not a durable heist action"
            }
        case .mechanicalDrag(let target):
            if target.duration != nil {
                return "drag duration \(String(describing: target.duration)) is not a durable heist action"
            }
            return nil
        case .viewportScroll(let target):
            if case .container = target.selection {
                return "scroll containerName is not a durable heist action"
            }
            return nil
        case .viewportScrollToEdge(let target):
            if case .container = target.selection {
                return "scroll_to_edge containerName is not a durable heist action"
            }
            return nil
        case .activate, .increment, .decrement, .customAction, .typeText, .mechanicalTap,
             .viewportScrollToVisible, .editAction, .setPasteboard, .dismissKeyboard:
            return nil
        }
    }

    var reportTarget: ElementTarget? {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            return target.reportTarget
        case .customAction(_, let target), .rotor(_, let target, _):
            return target.reportTarget
        case .typeText(_, let target):
            return target?.reportTarget
        case .mechanicalTap(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .mechanicalLongPress(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .mechanicalSwipe(let target):
            switch target.selection {
            case .unitElement(let target, _, _), .elementDirection(let target, _):
                return target
            case .point(let start, _):
                if case .element(let target) = start { return target }
                return nil
            }
        case .mechanicalDrag(let target):
            if case .element(let target) = target.start { return target }
            return nil
        case .viewportScroll(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .viewportScrollToEdge(let target):
            if case .element(let target) = target.selection { return target }
            return nil
        case .editAction, .setPasteboard, .dismissKeyboard:
            return nil
        }
    }
}

private extension ElementTargetExpr {
    var reportTarget: ElementTarget? {
        try? resolve(in: .empty)
    }
}

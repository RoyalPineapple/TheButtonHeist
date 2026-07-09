import Foundation

package struct HeistActionCommandTargetOccurrence: Sendable, Equatable {
    package enum Role: Sendable, Equatable {
        case semantic
        case gesture
        case scroll
    }

    package enum Path: Sendable, Equatable {
        case payloadTarget
        case payloadElement
        case payloadStartElement

        package func render(commandPath: String) -> String {
            switch self {
            case .payloadTarget:
                return "\(commandPath).payload.target"
            case .payloadElement:
                return "\(commandPath).payload.element"
            case .payloadStartElement:
                return "\(commandPath).payload.start.element"
            }
        }
    }

    package enum Target: Sendable, Equatable {
        case expression(ElementTargetExpr)
        case element(ElementTarget)

        package var reportTarget: ElementTarget? {
            switch self {
            case .expression(let target):
                return try? target.resolve(in: .empty)
            case .element(let target):
                return target
            }
        }
    }

    package let role: Role
    package let path: Path
    package let target: Target

    package init(role: Role, path: Path, target: Target) {
        self.role = role
        self.path = path
        self.target = target
    }

    package var reportTarget: ElementTarget? {
        target.reportTarget
    }
}

extension HeistActionCommand {
    package var targetOccurrences: [HeistActionCommandTargetOccurrence] {
        switch self {
        case .activate(let target), .increment(let target), .decrement(let target):
            return [.semantic(target)]
        case .customAction(_, let target), .rotor(_, let target, _):
            return [.semantic(target)]
        case .typeText(_, let target, _):
            return target.map { [.semantic($0)] } ?? []
        case .mechanicalTap(let target):
            return target.selection.targetOccurrences(role: .gesture, path: .payloadElement)
        case .mechanicalLongPress(let target):
            return target.selection.targetOccurrences(role: .gesture, path: .payloadElement)
        case .mechanicalSwipe(let target):
            return target.selection.targetOccurrences
        case .mechanicalDrag(let target):
            return target.selection.targetOccurrences
        case .viewportScroll(let target):
            return target.selection.targetOccurrences
        case .viewportScrollToVisible(let target):
            return [.scroll(target)]
        case .viewportScrollToEdge(let target):
            return target.selection.targetOccurrences
        case .dismiss, .magicTap, .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            return []
        }
    }
}

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
             .dismiss, .magicTap, .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            return nil
        }
    }

    var reportTarget: ElementTarget? {
        targetOccurrences.lazy.compactMap { $0.reportTarget }.first
    }
}

private extension HeistActionCommandTargetOccurrence {
    static func semantic(_ target: ElementTargetExpr) -> Self {
        Self(role: .semantic, path: .payloadTarget, target: .expression(target))
    }

    static func scroll(_ target: ElementTargetExpr) -> Self {
        Self(role: .scroll, path: .payloadTarget, target: .expression(target))
    }

    static func element(_ target: ElementTarget, role: Role, path: Path) -> Self {
        Self(role: role, path: path, target: .element(target))
    }
}

private extension GesturePointSelection {
    func targetOccurrences(
        role: HeistActionCommandTargetOccurrence.Role,
        path: HeistActionCommandTargetOccurrence.Path
    ) -> [HeistActionCommandTargetOccurrence] {
        switch self {
        case .element(let target), .elementUnitPoint(let target, _):
            return [.element(target, role: role, path: path)]
        case .coordinate:
            return []
        }
    }
}

private extension SwipeGestureSelection {
    var targetOccurrences: [HeistActionCommandTargetOccurrence] {
        switch self {
        case .unitElement(let target, _, _), .elementDirection(let target, _):
            return [.element(target, role: .gesture, path: .payloadElement)]
        case .point(let start, _):
            return start.targetOccurrences(role: .gesture, path: .payloadStartElement)
        }
    }
}

private extension DragGestureSelection {
    var targetOccurrences: [HeistActionCommandTargetOccurrence] {
        switch self {
        case .elementToPoint(let target, _, _):
            return [.element(target, role: .gesture, path: .payloadElement)]
        case .pointToPoint:
            return []
        }
    }
}

private extension ScrollContainerSelection {
    var targetOccurrences: [HeistActionCommandTargetOccurrence] {
        switch self {
        case .element(let target):
            return [.element(target, role: .scroll, path: .payloadTarget)]
        case .visibleContainer, .container:
            return []
        }
    }
}

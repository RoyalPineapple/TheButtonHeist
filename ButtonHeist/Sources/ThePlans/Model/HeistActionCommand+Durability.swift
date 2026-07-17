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

        package func appending(to commandPath: HeistPlanPath) -> HeistPlanPath {
            switch self {
            case .payloadTarget:
                return commandPath.child(.payload).child(.target)
            case .payloadElement:
                return commandPath.child(.payload).child(.element)
            case .payloadStartElement:
                return commandPath.child(.payload).child(.start).child(.element)
            }
        }
    }

    package let role: Role
    package let path: Path
    package let target: AccessibilityTarget

    package init(role: Role, path: Path, target: AccessibilityTarget) {
        self.role = role
        self.path = path
        self.target = target
    }

    package var reportTarget: AccessibilityTarget? {
        guard (try? target.resolve(in: .empty)) != nil else { return nil }
        return target
    }
}

extension HeistActionCommand {
    package var targetOccurrences: [HeistActionCommandTargetOccurrence] {
        switch core {
        case .activate(let target), .increment(let target), .decrement(let target):
            return [.semantic(target)]
        case .customAction(_, let target), .rotor(_, let target, _):
            return [.semantic(target)]
        case .typeText(let payload):
            return payload.target.map { [.semantic($0)] } ?? []
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
        switch core {
        case .rotor(let selection, _, _):
            if case .named = selection { return nil }
            return "rotor selection \(selection) is not a durable heist action"
        case .mechanicalSwipe(let target):
            if target.duration != nil {
                return "swipe duration \(String(describing: target.duration)) is not a durable heist action"
            }
            return nil
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

    var reportTarget: AccessibilityTarget? {
        targetOccurrences.lazy.compactMap { $0.reportTarget }.first
    }
}

private extension HeistActionCommandTargetOccurrence {
    static func semantic(_ target: AccessibilityTarget) -> Self {
        Self(role: .semantic, path: .payloadTarget, target: target)
    }

    static func scroll(_ target: AccessibilityTarget) -> Self {
        Self(role: .scroll, path: .payloadTarget, target: target)
    }

    static func element(_ target: AccessibilityTarget, role: Role, path: Path) -> Self {
        Self(role: role, path: path, target: target)
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
        case .pointToPoint, .pointDirection:
            return []
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

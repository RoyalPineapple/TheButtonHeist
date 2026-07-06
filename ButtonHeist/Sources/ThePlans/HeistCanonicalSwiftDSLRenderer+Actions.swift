import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(
        action: ActionStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var text = try line(render(command: action.command, environment: environment), indent)
        if let expectation = action.expectationPolicy.expectedStep {
            let predicate = try render(predicate: expectation.predicate, environment: environment)
            text += "\n" + line(".expect(\(predicate)\(renderActionExpectationTimeout(expectation.timeout)))", indent + 1)
        }
        if let waiver = action.expectationPolicy.waiver?.reason {
            text += "\n" + line(".withoutExpectation(\(quote(waiver)))", indent + 1)
        }
        return text
    }

    private func renderActionExpectationTimeout(_ timeout: Double) -> String {
        abs(timeout - defaultActionExpectationTimeout) < 0.000_001
            ? ""
            : ", timeout: .seconds(\(decimal(timeout)))"
    }

    func render(
        command: HeistActionCommand,
        environment: RenderEnvironment
    ) throws -> String {
        if let failure = command.durableHeistActionFailure {
            throw HeistCanonicalSwiftDSLError.unsupportedAction(failure)
        }
        switch command {
        case .activate(let target):
            return "Activate(\(try render(target: target, environment: environment)))"
        case .increment(let target):
            return "Increment(\(try render(target: target, environment: environment)))"
        case .decrement(let target):
            return "Decrement(\(try render(target: target, environment: environment)))"
        case .customAction(let name, let target):
            return "CustomAction(\(quote(name)), on: \(try render(target: target, environment: environment)))"
        case .rotor(let selection, let target, let direction):
            guard case .named(let name) = selection else {
                throw HeistCanonicalSwiftDSLError.unsupportedAction(command.durableHeistActionFailure ?? "rotor selection \(selection)")
            }
            return "Rotor(\(quote(name)), on: \(try render(target: target, environment: environment)), direction: .\(direction.rawValue))"
        case .typeText(let text, let target, let replacingExisting):
            if replacingExisting,
               case .literal("") = text,
               let target {
                return "ClearText(\(try render(target: target, environment: environment)))"
            }
            let suffix = replacingExisting ? ", replacingExisting: true" : ""
            if let target {
                return "TypeText(\(try render(string: text, environment: environment)), into: \(try render(target: target, environment: environment))\(suffix))"
            }
            return "TypeText(\(try render(string: text, environment: environment))\(suffix))"
        case .mechanicalTap(let target):
            return try render(mechanicalTap: target)
        case .mechanicalLongPress(let target):
            return try render(mechanicalLongPress: target)
        case .mechanicalSwipe(let target):
            return try render(mechanicalSwipe: target)
        case .mechanicalDrag(let target):
            return try render(mechanicalDrag: target)
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            throw HeistCanonicalSwiftDSLError.unsupportedAction(
                command.durableHeistActionFailure ?? "viewport debug command is not a durable heist action"
            )
        case .editAction(let target):
            return "Edit(.\(target.action.rawValue))"
        case .setPasteboard(let target):
            return "SetPasteboard(\(quote(target.text)))"
        case .takeScreenshot:
            return "TakeScreenshot()"
        case .dismiss:
            return "ScreenActions.Dismiss()"
        case .magicTap:
            return "ScreenActions.MagicTap()"
        case .dismissKeyboard:
            return "DismissKeyboard()"
        }
    }

    func render(mechanicalTap target: TapTarget) throws -> String {
        switch target.selection {
        case .element(let target):
            return "Mechanical.Tap(\(render(target: target)))"
        case .elementUnitPoint(let target, let point):
            return "Mechanical.Tap(\(render(target: target)), at: \(render(unitPoint: point)))"
        case .coordinate(let point):
            return "Mechanical.Tap(\(render(point: point)))"
        }
    }

    func render(mechanicalLongPress target: LongPressTarget) throws -> String {
        switch target.selection {
        case .element(let elementTarget):
            if target.duration == .longPressDefault {
                return "Mechanical.LongPress(\(render(target: elementTarget)))"
            }
            return "Mechanical.LongPress(\(render(target: elementTarget)), duration: \(render(duration: target.duration)))"
        case .elementUnitPoint(let elementTarget, let point):
            if target.duration == .longPressDefault {
                return "Mechanical.LongPress(\(render(target: elementTarget)), at: \(render(unitPoint: point)))"
            }
            return "Mechanical.LongPress(\(render(target: elementTarget)), at: \(render(unitPoint: point)), duration: \(render(duration: target.duration)))"
        case .coordinate(let point):
            if target.duration == .longPressDefault {
                return "Mechanical.LongPress(\(render(point: point)))"
            }
            return "Mechanical.LongPress(\(render(point: point)), duration: \(render(duration: target.duration)))"
        }
    }

    func render(mechanicalSwipe target: SwipeTarget) throws -> String {
        switch target.selection {
        case .unitElement(let target, let start, let end):
            return "Mechanical.Swipe(\(render(target: target)), from: \(render(unitPoint: start)), to: \(render(unitPoint: end)))"
        case .elementDirection(let target, let direction):
            return "Mechanical.Swipe(\(render(target: target)), .\(direction.rawValue))"
        case .point(.coordinate(let start), .coordinate(let end)):
            return "Mechanical.Swipe(from: \(render(point: start)), to: \(render(point: end)))"
        case .point(.coordinate(let start), .direction(let direction)):
            return "Mechanical.Swipe(from: \(render(point: start)), .\(direction.rawValue))"
        case .point(.element, _), .point(.elementUnitPoint, _):
            throw HeistCanonicalSwiftDSLError.unsupportedAction("swipe selection is not a durable heist action")
        }
    }

    func render(mechanicalDrag target: DragTarget) throws -> String {
        switch target.selection {
        case .elementToPoint(let target, let start, let end):
            if let start {
                return "Mechanical.Drag(\(render(target: target)), from: \(render(unitPoint: start)), to: \(render(point: end)))"
            }
            return "Mechanical.Drag(\(render(target: target)), to: \(render(point: end)))"
        case .pointToPoint(let start, let end):
            return "Mechanical.Drag(from: \(render(point: start)), to: \(render(point: end)))"
        }
    }
}

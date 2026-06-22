import Foundation

extension HeistCanonicalSwiftDSLRenderer {
    func render(
        action: ActionStep,
        indent: Int,
        environment: RenderEnvironment
    ) throws -> String {
        var text = try line(render(command: action.command, environment: environment), indent)
        if let expectation = action.expectation {
            let predicate = try render(predicate: expectation.predicate, environment: environment)
            text += "\n" + line(".expect(\(predicate)\(renderTimeout(expectation.timeout)))", indent + 1)
        }
        if let waiver = action.expectationWaiver {
            text += "\n" + line(".withoutExpectation(\(quote(waiver)))", indent + 1)
        }
        return text
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
        case .typeText(let text, let target):
            if let target {
                return "TypeText(\(try render(string: text, environment: environment)), into: \(try render(target: target, environment: environment)))"
            }
            return "TypeText(\(try render(string: text, environment: environment)))"
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
        case .dismissKeyboard:
            return "DismissKeyboard()"
        }
    }

    func render(mechanicalTap target: TapTarget) throws -> String {
        switch target.selection {
        case .element(let target):
            return "Mechanical.Tap(\(render(target: target)))"
        case .coordinate(let point):
            return "Mechanical.Tap(x: \(decimal(point.x)), y: \(decimal(point.y)))"
        }
    }

    func render(mechanicalLongPress target: LongPressTarget) throws -> String {
        switch target.selection {
        case .element(let elementTarget):
            return "Mechanical.LongPress(\(render(target: elementTarget)))"
        case .coordinate(let point):
            if target.duration == .longPressDefault {
                return "Mechanical.LongPress(x: \(decimal(point.x)), y: \(decimal(point.y)))"
            }
            return "Mechanical.LongPress(x: \(decimal(point.x)), y: \(decimal(point.y)), duration: \(render(duration: target.duration)))"
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
        case .point(.element, _):
            throw HeistCanonicalSwiftDSLError.unsupportedAction("swipe selection is not a durable heist action")
        }
    }

    func render(mechanicalDrag target: DragTarget) throws -> String {
        switch target.selection {
        case .elementToPoint(let target, let end):
            return "Mechanical.Drag(\(render(target: target)), to: \(render(point: end)))"
        case .pointToPoint(let start, let end):
            return "Mechanical.Drag(from: \(render(point: start)), to: \(render(point: end)))"
        }
    }
}

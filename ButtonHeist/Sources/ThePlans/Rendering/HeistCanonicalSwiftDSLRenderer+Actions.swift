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

    private func renderActionExpectationTimeout(_ timeout: WaitTimeout) -> String {
        timeout == defaultActionExpectationTimeout
            ? ""
            : ", timeout: .seconds(\(decimal(timeout.seconds)))"
    }

    func render(
        command: HeistActionCommand,
        environment: RenderEnvironment
    ) throws -> String {
        if let failure = command.durableHeistActionFailure {
            throw HeistCanonicalSwiftDSLError.unsupportedAction(failure)
        }
        switch command.core {
        case .activate(let target):
            return "Activate(\(try render(target: target, environment: environment)))"
        case .increment(let target):
            return "Increment(\(try render(target: target, environment: environment)))"
        case .decrement(let target):
            return "Decrement(\(try render(target: target, environment: environment)))"
        case .customAction(let name, let target):
            return "CustomAction(\(quote(name.rawValue)), on: \(try render(target: target, environment: environment)))"
        case .rotor(let selection, let target, let direction):
            guard case .named(let name) = selection else {
                throw HeistCanonicalSwiftDSLError.unsupportedAction(command.durableHeistActionFailure ?? "rotor selection \(selection)")
            }
            return "Rotor(\(quote(name.rawValue)), on: \(try render(target: target, environment: environment)), direction: .\(direction.rawValue))"
        case .typeText(let payload):
            return try render(typeText: payload, environment: environment)
        case .mechanicalTap(let target):
            return try render(mechanicalTap: target, environment: environment)
        case .mechanicalLongPress(let target):
            return try render(mechanicalLongPress: target, environment: environment)
        case .mechanicalSwipe(let target):
            return try render(mechanicalSwipe: target, environment: environment)
        case .mechanicalDrag(let target):
            return try render(mechanicalDrag: target, environment: environment)
        case .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
            throw HeistCanonicalSwiftDSLError.unsupportedAction(
                command.durableHeistActionFailure ?? "viewport debug command is not a durable heist action"
            )
        case .editAction(let target):
            return "Edit(.\(target.action.rawValue))"
        case .setPasteboard(let target):
            return "SetPasteboard(\(quote(target.text.rawText)))"
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

    private func render(
        typeText payload: TypeTextTarget,
        environment: RenderEnvironment
    ) throws -> String {
        let source: String
        let modeSuffix: String
        switch payload.source {
        case .text(let text):
            if text.mode == .replace, text.rawText.isEmpty, let target = payload.target {
                return "ClearText(\(try render(target: target, environment: environment)))"
            }
            source = text.mode == .replace
                ? ".replacing(\(quote(text.rawText)))"
                : quote(text.rawText)
            modeSuffix = ""
        case .reference(let reference, let mode):
            source = try render(string: .ref(reference), environment: environment)
            modeSuffix = mode == .replace ? ", mode: .replace" : ""
        }
        let target = try payload.target.map {
            ", into: \(try render(target: $0, environment: environment))"
        } ?? ""
        return "TypeText(\(source)\(target)\(modeSuffix))"
    }

    func render(mechanicalTap target: TapTarget, environment: RenderEnvironment) throws -> String {
        switch target.selection {
        case .element(let target):
            return "Mechanical.Tap(\(try render(target: target, environment: environment)))"
        case .elementUnitPoint(let target, let point):
            return "Mechanical.Tap(\(try render(target: target, environment: environment)), at: \(render(unitPoint: point)))"
        case .coordinate(let point):
            return "Mechanical.Tap(\(render(point: point)))"
        }
    }

    func render(
        mechanicalLongPress request: LongPressTarget,
        environment: RenderEnvironment
    ) throws -> String {
        switch request.selection {
        case .element(let target):
            if request.duration == .longPressDefault {
                return "Mechanical.LongPress(\(try render(target: target, environment: environment)))"
            }
            return "Mechanical.LongPress(\(try render(target: target, environment: environment)), duration: \(render(duration: request.duration)))"
        case .elementUnitPoint(let target, let point):
            if request.duration == .longPressDefault {
                return "Mechanical.LongPress(\(try render(target: target, environment: environment)), at: \(render(unitPoint: point)))"
            }
            let target = try render(target: target, environment: environment)
            let point = render(unitPoint: point)
            return "Mechanical.LongPress(\(target), at: \(point), duration: \(render(duration: request.duration)))"
        case .coordinate(let point):
            if request.duration == .longPressDefault {
                return "Mechanical.LongPress(\(render(point: point)))"
            }
            return "Mechanical.LongPress(\(render(point: point)), duration: \(render(duration: request.duration)))"
        }
    }

    func render(mechanicalSwipe target: SwipeTarget, environment: RenderEnvironment) throws -> String {
        switch target.selection {
        case .unitElement(let target, let start, let end):
            return "Mechanical.Swipe(\(try render(target: target, environment: environment)), from: \(render(unitPoint: start)), to: \(render(unitPoint: end)))"
        case .elementDirection(let target, let direction):
            return "Mechanical.Swipe(\(try render(target: target, environment: environment)), .\(direction.rawValue))"
        case .point(.coordinate(let start), .coordinate(let end)):
            return "Mechanical.Swipe(from: \(render(point: start)), to: \(render(point: end)))"
        case .point(.coordinate(let start), .direction(let direction)):
            return "Mechanical.Swipe(from: \(render(point: start)), .\(direction.rawValue))"
        case .point(.element, _), .point(.elementUnitPoint, _):
            throw HeistCanonicalSwiftDSLError.unsupportedAction("swipe selection is not a durable heist action")
        }
    }

    func render(mechanicalDrag target: DragTarget, environment: RenderEnvironment) throws -> String {
        switch target.selection {
        case .elementToPoint(let target, let start, let end):
            if let start {
                return "Mechanical.Drag(\(try render(target: target, environment: environment)), from: \(render(unitPoint: start)), to: \(render(point: end)))"
            }
            return "Mechanical.Drag(\(try render(target: target, environment: environment)), to: \(render(point: end)))"
        case .pointToPoint(let start, let end):
            return "Mechanical.Drag(from: \(render(point: start)), to: \(render(point: end)))"
        }
    }
}

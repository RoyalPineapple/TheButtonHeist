import ThePlans

/// Internal lowering between ThePlans action commands and TheInsideJob's
/// dispatch implementation.
///
/// Public mutation requests cross the device wire as `ClientMessage.heistPlan`.
/// Once a plan is inside the runtime, action steps resolve to
/// `RuntimeActionMessage` for primitive dispatch.
@_spi(ButtonHeistInternals) public extension HeistActionCommand {
    init(runtimeActionMessage: RuntimeActionMessage) throws {
        switch runtimeActionMessage {
        case .activate(let target):
            self = .activate(.target(target))
        case .increment(let target):
            self = .increment(.target(target))
        case .decrement(let target):
            self = .decrement(.target(target))
        case .performCustomAction(let target):
            self = .customAction(name: target.actionName, target: .target(target.elementTarget))
        case .rotor(let target):
            self = .rotor(selection: target.selection, target: .target(target.elementTarget), direction: target.direction)
        case .typeText(let target):
            self = .typeText(
                text: .literal(target.text),
                target: target.elementTarget.map(ElementTargetExpr.target),
                replacingExisting: target.replacingExisting
            )
        case .oneFingerTap(let target):
            self = .mechanicalTap(target)
        case .longPress(let target):
            self = .mechanicalLongPress(target)
        case .swipe(let target):
            self = .mechanicalSwipe(target)
        case .drag(let target):
            self = .mechanicalDrag(target)
        case .scroll(let target):
            self = .viewportScroll(target)
        case .scrollToVisible(let target):
            self = .viewportScrollToVisible(.target(target.elementTarget))
        case .scrollToEdge(let target):
            self = .viewportScrollToEdge(target)
        case .editAction(let target):
            self = .editAction(target)
        case .setPasteboard(let target):
            self = .setPasteboard(target)
        case .takeScreenshot:
            self = .takeScreenshot
        case .resignFirstResponder:
            self = .dismissKeyboard
        case .wait:
            throw HeistExpressionError.unsupportedHeistActionCommand(runtimeActionMessage.runtimeType.rawValue)
        }
    }

    var runtimeActionType: RuntimeActionType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .customAction: return .performCustomAction
        case .rotor: return .rotor
        case .typeText: return .typeText
        case .mechanicalTap: return .oneFingerTap
        case .mechanicalLongPress: return .longPress
        case .mechanicalSwipe: return .swipe
        case .mechanicalDrag: return .drag
        case .viewportScroll: return .scroll
        case .viewportScrollToVisible: return .scrollToVisible
        case .viewportScrollToEdge: return .scrollToEdge
        case .editAction: return .editAction
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
        case .dismissKeyboard: return .resignFirstResponder
        }
    }

    func resolveForRuntimeDispatch(in environment: HeistExecutionEnvironment) throws -> RuntimeActionMessage {
        switch self {
        case .activate(let target):
            return .activate(try target.resolve(in: environment))
        case .increment(let target):
            return .increment(try target.resolve(in: environment))
        case .decrement(let target):
            return .decrement(try target.resolve(in: environment))
        case .customAction(let name, let target):
            return .performCustomAction(CustomActionTarget(
                elementTarget: try target.resolve(in: environment),
                actionName: name
            ))
        case .rotor(let selection, let target, let direction):
            return .rotor(RotorTarget(
                elementTarget: try target.resolve(in: environment),
                selection: selection,
                direction: direction
            ))
        case .typeText(let text, let target, let replacingExisting):
            let resolvedText = try text.resolve(in: environment)
            return .typeText(try TypeTextTarget(
                validatingText: resolvedText,
                elementTarget: try target?.resolve(in: environment),
                replacingExisting: replacingExisting
            ))
        case .mechanicalTap(let target):
            return .oneFingerTap(target)
        case .mechanicalLongPress(let target):
            return .longPress(target)
        case .mechanicalSwipe(let target):
            return .swipe(target)
        case .mechanicalDrag(let target):
            return .drag(target)
        case .viewportScroll(let target):
            return .scroll(target)
        case .viewportScrollToVisible(let target):
            return .scrollToVisible(ScrollToVisibleTarget(elementTarget: try target.resolve(in: environment)))
        case .viewportScrollToEdge(let target):
            return .scrollToEdge(target)
        case .editAction(let target):
            return .editAction(target)
        case .setPasteboard(let target):
            return .setPasteboard(target)
        case .takeScreenshot:
            return .takeScreenshot
        case .dismissKeyboard:
            return .resignFirstResponder
        }
    }

    func resolve(in environment: HeistExecutionEnvironment) throws -> RuntimeActionMessage {
        try resolveForRuntimeDispatch(in: environment)
    }
}

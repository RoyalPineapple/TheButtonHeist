import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validateCommandExpressions(
        _ command: HeistActionCommand,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch command {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .customAction(let name, let target):
            addString(name, path: "\(path).payload.actionName", role: "custom action name")
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .rotor(let selection, let target, _):
            if case .named(let name) = selection {
                addString(name, path: "\(path).payload.rotor", role: "rotor name")
            }
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .typeText(let text, let target, let replacingExisting):
            validateString(text, path: "\(path).payload.text", scope: scope)
            if case .literal("") = text, !replacingExisting {
                fail(
                    path: "\(path).payload.text",
                    contract: "type_text text must be non-empty unless replacingExisting is true",
                    observed: "empty string",
                    correction: "Use TypeText with non-empty text, or pass replacingExisting: true to clear the field."
                )
            }
            if let target {
                validateTarget(target, path: "\(path).payload.target", scope: scope)
            }
        case .mechanicalTap(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
        case .mechanicalLongPress(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
            validateGestureDuration(target.duration, path: "\(path).payload.duration")
        case .mechanicalSwipe(let target):
            validateSwipe(target, path: "\(path).payload", scope: scope)
            if let duration = target.duration {
                validateGestureDuration(duration, path: "\(path).payload.duration")
            }
        case .mechanicalDrag(let target):
            validateDrag(target, path: "\(path).payload", scope: scope)
            if let duration = target.duration {
                validateGestureDuration(duration, path: "\(path).payload.duration")
            }
        case .viewportScroll(let target):
            validateScroll(target.selection, path: "\(path).payload", scope: scope)
        case .viewportScrollToEdge(let target):
            validateScroll(target.selection, path: "\(path).payload", scope: scope)
        case .setPasteboard(let target):
            addString(target.text, path: "\(path).payload.text", role: "pasteboard text")
            if target.text.isEmpty {
                fail(
                    path: "\(path).payload.text",
                    contract: "set_pasteboard text must be non-empty",
                    observed: "empty string",
                    correction: "Use non-empty text for SetPasteboard."
                )
            }
        case .editAction, .takeScreenshot, .dismissKeyboard:
            break
        }
    }

    mutating func validateGesturePointSelection(
        _ selection: GesturePointSelection,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch selection {
        case .element(let target), .elementUnitPoint(let target, _):
            validateElementTarget(target, path: "\(path).element")
        case .coordinate:
            break
        }
    }

    mutating func validateGestureDuration(
        _ duration: GestureDuration,
        path: String
    ) {
        guard let expected = GestureDuration.validationFailure(for: duration.seconds) else {
            return
        }
        fail(
            path: path,
            contract: "gesture duration must be \(expected)",
            observed: "\(duration.seconds)",
            correction: "Use a finite duration greater than 0 and no more than \(GestureDuration.maximumSeconds) seconds."
        )
    }

    mutating func validateSwipe(
        _ target: SwipeTarget,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch target.selection {
        case .unitElement(let target, _, _), .elementDirection(let target, _):
            validateElementTarget(target, path: "\(path).element")
        case .point(let start, _):
            validateGesturePointSelection(start, path: "\(path).start", scope: scope)
        }
    }

    mutating func validateDrag(
        _ target: DragTarget,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch target.selection {
        case .elementToPoint(let target, _, _):
            validateElementTarget(target, path: "\(path).element")
        case .pointToPoint:
            break
        }
    }

    mutating func validateScroll(
        _ selection: ScrollContainerSelection,
        path: String,
        scope: HeistReferenceScope
    ) {
        if case .element(let target) = selection {
            validateElementTarget(target, path: "\(path).target")
        }
    }
}

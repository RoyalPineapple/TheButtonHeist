import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validateCommandExpressions(
        _ command: HeistActionCommand,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch command {
        case .activate, .increment, .decrement, .viewportScrollToVisible:
            validateActionTargets(in: command, path: path, scope: scope)
        case .customAction(let name, _):
            addString(name, path: "\(path).payload.actionName", role: "custom action name")
            if name.isEmpty {
                fail(
                    path: "\(path).payload.actionName",
                    contract: "custom action name must not be empty",
                    observed: "empty string",
                    correction: "Use the non-empty custom action name exposed by the target element."
                )
            }
            validateActionTargets(in: command, path: path, scope: scope)
        case .rotor(let selection, _, _):
            if case .named(let name) = selection {
                addString(name, path: "\(path).payload.rotor", role: "rotor name")
            }
            validateActionTargets(in: command, path: path, scope: scope)
        case .typeText(let text, _, let replacingExisting):
            validateString(text, path: "\(path).payload.text", scope: scope)
            if case .literal("") = text, !replacingExisting {
                fail(
                    path: "\(path).payload.text",
                    contract: "type_text text must be non-empty unless replacingExisting is true",
                    observed: "empty string",
                    correction: "Use TypeText with non-empty text, or pass replacingExisting: true to clear the field."
                )
            }
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalTap:
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalLongPress(let target):
            validateActionTargets(in: command, path: path, scope: scope)
            validateGestureDuration(target.duration, path: "\(path).payload.duration")
        case .mechanicalSwipe(let target):
            validateActionTargets(in: command, path: path, scope: scope)
            if let duration = target.duration {
                validateGestureDuration(duration, path: "\(path).payload.duration")
            }
        case .mechanicalDrag(let target):
            validateActionTargets(in: command, path: path, scope: scope)
            if let duration = target.duration {
                validateGestureDuration(duration, path: "\(path).payload.duration")
            }
        case .viewportScroll, .viewportScrollToEdge:
            validateActionTargets(in: command, path: path, scope: scope)
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

    mutating func validateActionTargets(
        in command: HeistActionCommand,
        path: String,
        scope: HeistReferenceScope
    ) {
        for occurrence in command.targetOccurrences {
            let targetPath = occurrence.path.render(commandPath: path)
            switch occurrence.target {
            case .expression(let target):
                validateTarget(target, path: targetPath, scope: scope)
            case .element(let target):
                validateElementTarget(target, path: targetPath)
            }
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
}

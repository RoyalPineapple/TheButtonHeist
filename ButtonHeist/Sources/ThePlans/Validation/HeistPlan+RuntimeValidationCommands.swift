import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validateCommandExpressions(
        _ command: HeistActionCommand,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch command.core {
        case .activate, .increment, .decrement, .viewportScrollToVisible:
            validateActionTargets(in: command, path: path, scope: scope)
        case .customAction(let name, _):
            addString(name.rawValue, path: path.child(.payload).child(.actionName), role: "custom action name")
            validateActionTargets(in: command, path: path, scope: scope)
        case .rotor(let selection, _, _):
            if case .named(let name) = selection {
                addString(name.rawValue, path: path.child(.payload).child(.rotor), role: "rotor name")
            }
            validateActionTargets(in: command, path: path, scope: scope)
        case .typeText(let payload):
            switch payload.source {
            case .text(let text):
                addString(text.rawText, path: path.child(.payload).child(.text), role: "text input text")
            case .reference(let reference, _):
                validateStringReference(reference, path: path.child(.payload).child(.textRef), scope: scope)
            }
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalTap:
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalLongPress:
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalSwipe:
            validateActionTargets(in: command, path: path, scope: scope)
        case .mechanicalDrag:
            validateActionTargets(in: command, path: path, scope: scope)
        case .viewportScroll, .viewportScrollToEdge:
            validateActionTargets(in: command, path: path, scope: scope)
        case .setPasteboard(let target):
            addString(target.text.rawText, path: path.child(.payload).child(.text), role: "pasteboard text")
        case .dismiss, .magicTap, .editAction, .takeScreenshot, .dismissKeyboard:
            break
        }
    }

    mutating func validateActionTargets(
        in command: HeistActionCommand,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        for occurrence in command.targetOccurrences {
            let targetPath = occurrence.path.appending(to: path)
            validateTarget(occurrence.target, path: targetPath, scope: scope)
            validateActionElementTarget(occurrence.target, path: targetPath)
        }
    }

    mutating func validateActionElementTarget(_ target: AccessibilityTarget, path: HeistPlanPath) {
        switch target {
        case .container:
            fail(
                path: path,
                contract: "action target must select an accessibility element",
                observed: "container-only target",
                correction: "Use a predicate target for element actions; use a container-aware scroll command for containers."
            )
        case .within(_, let target):
            validateActionElementTarget(target, path: path.child(.target))
        case .predicate, .ref:
            break
        }
    }

}

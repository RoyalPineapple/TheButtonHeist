import Foundation

extension HeistPlanRuntimeValidator {
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
        case .typeText(let text, let target):
            validateString(text, path: "\(path).payload.text", scope: scope)
            if let target {
                validateTarget(target, path: "\(path).payload.target", scope: scope)
            }
        case .mechanicalTap(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
        case .mechanicalLongPress(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
        case .mechanicalSwipe(let target):
            validateSwipe(target, path: "\(path).payload", scope: scope)
        case .mechanicalDrag(let target):
            validateDrag(target, path: "\(path).payload", scope: scope)
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
        case .editAction, .dismissKeyboard:
            break
        }
    }

    mutating func validateGesturePointSelection(
        _ selection: GesturePointSelection,
        path: String,
        scope: HeistReferenceScope
    ) {
        if case .element(let target) = selection {
            validateElementTarget(target, path: "\(path).element")
        }
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
        case .elementToPoint(let target, _):
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

    mutating func validateTarget(
        _ target: ElementTargetExpr,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch target {
        case .target(let target):
            validateElementTarget(target, path: path)
        case .predicate(let predicate, _):
            validateElementPredicate(predicate, path: path, scope: scope)
        case .ref(let reference):
            validateReference(reference, path: path, role: "target_ref")
            if !scope.targetRefs.contains(reference) {
                fail(
                    path: path,
                    contract: "target_ref must resolve in the current heist scope",
                    observed: "\"\(reference)\"",
                    correction: "Use target_ref only inside the for_each_element body that defines it."
                )
            }
        }
    }

    mutating func validateString(
        _ string: StringExpr,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch string {
        case .literal(let literal):
            addString(literal, path: path, role: "string literal")
        case .ref(let reference):
            validateReference(reference, path: path, role: "text_ref")
            if !scope.stringRefs.contains(reference) {
                fail(
                    path: path,
                    contract: "text_ref must resolve in the current heist scope",
                    observed: "\"\(reference)\"",
                    correction: "Use text_ref only inside the for_each_string body that defines it."
                )
            }
        }
    }

    mutating func validateElementTarget(_ target: ElementTarget, path: String) {
        switch target {
        case .predicate(let predicate, _):
            validateElementPredicate(predicate, path: path)
        }
    }

    mutating func validateElementPredicate(
        _ predicate: ElementPredicate,
        path: String
    ) {
        addString(predicate.label, path: "\(path).label", role: "element label")
        addString(predicate.identifier, path: "\(path).identifier", role: "element identifier")
        addString(predicate.value, path: "\(path).value", role: "element value")
    }

    mutating func validateElementPredicate(
        _ predicate: ElementPredicateTemplate,
        path: String,
        scope: HeistReferenceScope
    ) {
        if let label = predicate.label {
            validateString(label, path: "\(path).label", scope: scope)
        }
        if let identifier = predicate.identifier {
            validateString(identifier, path: "\(path).identifier", scope: scope)
        }
        if let value = predicate.value {
            validateString(value, path: "\(path).value", scope: scope)
        }
    }

    mutating func validateParameter(_ parameter: String, path: String, role: String) {
        addParameterString(parameter, path: path, role: role)
        guard HeistParameterName.isValid(parameter) else {
            fail(
                path: path,
                contract: "\(role) must be a Swift-style identifier",
                observed: "\"\(escaped(parameter))\"",
                correction: "Use letters, digits, and underscores, starting with a letter or underscore; avoid Swift keywords."
            )
            return
        }
    }

    mutating func validateReference(_ reference: String, path: String, role: String) {
        addParameterString(reference, path: path, role: role)
        if !HeistParameterName.isValid(reference) {
            fail(
                path: path,
                contract: "\(role) must be a Swift-style identifier",
                observed: "\"\(escaped(reference))\"",
                correction: "Use a ref matching the loop parameter exactly."
            )
        }
    }

    mutating func addParameterString(_ value: String, path: String, role: String) {
        let bytes = value.utf8.count
        if bytes > limits.maxParameterBytes {
            fail(
                path: path,
                contract: "max parameter/ref length",
                observed: "\(bytes) bytes for \(role)",
                correction: "Use \(limits.maxParameterBytes) bytes or fewer."
            )
        }
        addString(value, path: path, role: role)
    }

    mutating func addString(_ value: String?, path: String, role: String) {
        guard let value else { return }
        let bytes = value.utf8.count
        if bytes > limits.maxStringBytes {
            fail(
                path: path,
                contract: "max string length",
                observed: "\(bytes) bytes for \(role)",
                correction: "Use \(limits.maxStringBytes) bytes or fewer for any single string."
            )
        }
        totalStringBytes += bytes
        if totalStringBytes > limits.maxTotalStringBytes, !reportedTotalStringLimit {
            reportedTotalStringLimit = true
            fail(
                path: path,
                contract: "max total string bytes",
                observed: "\(totalStringBytes) bytes",
                correction: "Use \(limits.maxTotalStringBytes) total UTF-8 string bytes or fewer."
            )
        }
    }

}

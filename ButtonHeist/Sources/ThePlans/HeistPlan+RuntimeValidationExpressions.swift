import Foundation

extension HeistPlanRuntimeSafetyValidator {
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

    mutating func validateString(
        _ match: StringMatch<StringExpr>,
        path: String,
        scope: HeistReferenceScope
    ) {
        validateString(match.value, path: path, scope: scope)
        if match.hasInvalidEmptyBroadLiteral {
            fail(
                path: path,
                contract: "\(match.mode.rawValue) string match value must not be empty",
                observed: "empty \(match.mode.rawValue) match",
                correction: "Use a non-empty string, or an exact match when the empty string is intentional."
            )
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
        validateString(predicate.label, path: "\(path).label", role: "element label")
        validateString(predicate.identifier, path: "\(path).identifier", role: "element identifier")
        validateString(predicate.value, path: "\(path).value", role: "element value")
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

    mutating func validateString(_ match: StringMatch<String>?, path: String, role: String) {
        guard let match else { return }
        addString(match.value, path: path, role: role)
        if match.hasInvalidEmptyBroadLiteral {
            fail(
                path: path,
                contract: "\(match.mode.rawValue) string match value must not be empty",
                observed: "empty \(match.mode.rawValue) match",
                correction: "Use a non-empty string, or an exact match when the empty string is intentional."
            )
        }
    }
}

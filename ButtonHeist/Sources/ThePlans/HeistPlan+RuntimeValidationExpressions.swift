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
        for (index, check) in predicate.checks.enumerated() {
            let checkPath = "\(path).checks[\(index)]"
            switch check {
            case .label(let match):
                validateString(match, path: "\(checkPath).label", role: "element label")
            case .identifier(let match):
                validateString(match, path: "\(checkPath).identifier", role: "element identifier")
            case .value(let match):
                validateString(match, path: "\(checkPath).value", role: "element value")
            case .hint(let match):
                validateString(match, path: "\(checkPath).hint", role: "element hint")
            case .traits:
                break
            case .actions:
                break
            case .customContent(let match):
                validateString(match.label, path: "\(checkPath).customContent.label", role: "custom content label")
                validateString(match.value, path: "\(checkPath).customContent.value", role: "custom content value")
            case .rotors(let matches):
                validateStrings(matches, path: "\(checkPath).rotors", role: "element rotor")
            case .exclude(let check):
                validateElementPredicate(ElementPredicate([check]), path: "\(checkPath).exclude")
            }
        }
    }

    mutating func validateElementPredicate(
        _ predicate: ElementPredicateTemplate,
        path: String,
        scope: HeistReferenceScope
    ) {
        for (index, check) in predicate.checks.enumerated() {
            let checkPath = "\(path).checks[\(index)]"
            switch check {
            case .label(let match):
                validateString(match, path: "\(checkPath).label", scope: scope)
            case .identifier(let match):
                validateString(match, path: "\(checkPath).identifier", scope: scope)
            case .value(let match):
                validateString(match, path: "\(checkPath).value", scope: scope)
            case .hint(let match):
                validateString(match, path: "\(checkPath).hint", scope: scope)
            case .traits:
                break
            case .actions:
                break
            case .customContent(let match):
                if let label = match.label {
                    validateString(label, path: "\(checkPath).customContent.label", scope: scope)
                }
                if let value = match.value {
                    validateString(value, path: "\(checkPath).customContent.value", scope: scope)
                }
            case .rotors(let matches):
                validateStrings(matches, path: "\(checkPath).rotors", scope: scope)
            case .exclude(let check):
                validateElementPredicate(ElementPredicateTemplate([check]), path: "\(checkPath).exclude", scope: scope)
            }
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

    mutating func validateParameter(_ parameter: HeistReferenceName, path: String, role: String) {
        validateParameter(parameter.rawValue, path: path, role: role)
    }

    mutating func validateReference(_ reference: HeistReferenceName, path: String, role: String) {
        let value = reference.rawValue
        addParameterString(value, path: path, role: role)
        if !HeistParameterName.isValid(value) {
            fail(
                path: path,
                contract: "\(role) must be a Swift-style identifier",
                observed: "\"\(escaped(value))\"",
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

    mutating func validateStrings(_ matches: [StringMatch<String>], path: String, role: String) {
        for (index, match) in matches.enumerated() {
            validateString(match, path: "\(path)[\(index)]", role: role)
        }
    }

    mutating func validateStrings(
        _ matches: [StringMatch<StringExpr>],
        path: String,
        scope: HeistReferenceScope
    ) {
        for (index, match) in matches.enumerated() {
            validateString(match, path: "\(path)[\(index)]", scope: scope)
        }
    }
}

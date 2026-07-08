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
        case .predicate(let predicate, let ordinal):
            validateOrdinal(ordinal, path: "\(path).ordinal")
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
        case .within(let container, let target):
            validateContainerPredicate(container, path: "\(path).container", scope: scope)
            validateTarget(target, path: "\(path).target", scope: scope)
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
        if let value = match.valueIfPresent {
            validateString(value, path: path, scope: scope)
        }
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
        case .predicate(let predicate, let ordinal):
            validateOrdinal(ordinal, path: "\(path).ordinal")
            validateElementPredicate(predicate, path: path)
        case .within(let container, let target):
            validateContainerPredicate(container, path: "\(path).container")
            validateElementTarget(target, path: "\(path).target")
        }
    }

    mutating func validateContainerPredicate(
        _ predicate: ContainerPredicate,
        path: String
    ) {
        for (index, check) in predicate.checks.enumerated() {
            validateContainerPredicateCheck(check, path: "\(path).checks[\(index)]")
        }
    }

    mutating func validateContainerPredicate(
        _ predicate: ContainerPredicateExpr,
        path: String,
        scope: HeistReferenceScope
    ) {
        for (index, check) in predicate.checks.enumerated() {
            validateContainerPredicateCheck(check, path: "\(path).checks[\(index)]", scope: scope)
        }
    }

    mutating func validateContainerPredicateCheck(
        _ check: ContainerPredicateCheck<String>,
        path: String
    ) {
        switch check {
        case .type, .modalBoundary:
            return
        case .semantic(let predicate):
            validateSemanticContainerPredicate(predicate, path: "\(path).semantic")
        case .rowCount(let rowCount):
            validateNonNegative(rowCount, path: "\(path).rowCount", role: "container rowCount")
        case .columnCount(let columnCount):
            validateNonNegative(columnCount, path: "\(path).columnCount", role: "container columnCount")
        }
    }

    mutating func validateContainerPredicateCheck(
        _ check: ContainerPredicateCheck<StringExpr>,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch check {
        case .type, .modalBoundary:
            return
        case .semantic(let predicate):
            validateSemanticContainerPredicate(predicate, path: "\(path).semantic", scope: scope)
        case .rowCount(let rowCount):
            validateNonNegative(rowCount, path: "\(path).rowCount", role: "container rowCount")
        case .columnCount(let columnCount):
            validateNonNegative(columnCount, path: "\(path).columnCount", role: "container columnCount")
        }
    }

    mutating func validateSemanticContainerPredicate(
        _ predicate: SemanticContainerPredicate<String>,
        path: String
    ) {
        switch predicate {
        case .label(let match):
            validateString(match, path: "\(path).label", role: "container label")
        case .value(let match):
            validateString(match, path: "\(path).value", role: "container value")
        case .identifier(let match):
            validateString(match, path: "\(path).identifier", role: "container identifier")
        }
    }

    mutating func validateSemanticContainerPredicate(
        _ predicate: SemanticContainerPredicate<StringExpr>,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch predicate {
        case .label(let match):
            validateString(match, path: "\(path).label", scope: scope)
        case .value(let match):
            validateString(match, path: "\(path).value", scope: scope)
        case .identifier(let match):
            validateString(match, path: "\(path).identifier", scope: scope)
        }
    }

    mutating func validateNonNegative(_ value: Int, path: String, role: String) {
        guard value < 0 else { return }
        fail(
            path: path,
            contract: "\(role) must be non-negative",
            observed: "\(value)",
            correction: "Use a value of 0 or greater."
        )
    }

    mutating func validateRequiredContainerPredicate(_ predicate: ContainerPredicate, path: String) {
        if !predicate.hasPredicates {
            fail(
                path: path,
                contract: "container predicate must include at least one field",
                observed: "empty container predicate",
                correction: "Use a semantic, type, table, or modal-boundary container check."
            )
        }
    }

    mutating func validateOrdinal(_ ordinal: Int?, path: String) {
        guard let ordinal, ordinal < 0 else { return }
        fail(
            path: path,
            contract: "ordinal must be non-negative",
            observed: "\(ordinal)",
            correction: "Use an ordinal of 0 or greater."
        )
    }

    mutating func validateElementPredicate(
        _ predicate: ElementPredicate,
        path: String
    ) {
        if let description = predicate.invalidEmptyPayloadDescription {
            fail(
                path: path,
                contract: "element predicate must not be empty",
                observed: description,
                correction: "Use a non-empty label, identifier, value, hint, traits, actions, customContent, rotors, or exclude check."
            )
        }
        for (index, check) in predicate.checks.enumerated() {
            let checkPath = "\(path).checks[\(index)]"
            validateElementPredicateCheck(check, path: checkPath)
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
        if let description = predicate.invalidEmptyPayloadDescription {
            fail(
                path: path,
                contract: "element predicate must not be empty",
                observed: description,
                correction: "Use a non-empty label, identifier, value, hint, traits, actions, customContent, rotors, or exclude check."
            )
        }
        for (index, check) in predicate.checks.enumerated() {
            let checkPath = "\(path).checks[\(index)]"
            validateElementPredicateCheck(check, path: checkPath)
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

    mutating func validateElementPredicateCheck<Text>(
        _ check: ElementPredicateCheck<Text>,
        path: String
    ) {
        guard let description = check.invalidEmptyPayloadDescription else { return }
        fail(
            path: path,
            contract: "element predicate check payload must not be empty",
            observed: description,
            correction: "Use non-empty matcher values and non-empty trait/action/rotor collections."
        )
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
        addString(match.valueIfPresent, path: path, role: role)
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

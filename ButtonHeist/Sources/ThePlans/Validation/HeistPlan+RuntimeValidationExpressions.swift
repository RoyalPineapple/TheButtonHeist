import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validateTarget(
        _ target: AccessibilityTarget,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch target {
        case .predicate(let predicate, let ordinal):
            validateOrdinal(ordinal, path: path.child(.ordinal))
            validateElementPredicate(predicate, path: path, scope: scope)
        case .container(let predicate, let ordinal):
            validateOrdinal(ordinal, path: path.child(.ordinal))
            validateContainerPredicate(predicate, path: path.child(.container), scope: scope)
        case .ref(let reference):
            validateReference(reference, path: path, role: "target ref")
            if !scope.targetRefs.contains(reference) {
                fail(
                    path: path,
                    contract: "target ref must resolve in the current heist scope",
                    observed: "\"\(reference)\"",
                    correction: "Use ref only inside the for_each_element body that defines it."
                )
            }
        case .within(let container, let target):
            validateContainerPredicate(container, path: path.child(.container), scope: scope)
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    mutating func validateString(
        _ string: AuthoredString,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch string {
        case .literal(let literal):
            addString(literal, path: path, role: "string literal")
        case .ref(let reference):
            validateStringReference(reference, path: path, scope: scope)
        }
    }

    mutating func validateStringReference(
        _ reference: HeistReferenceName,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
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

    mutating func validateString(
        _ match: StringMatchCore<AuthoredString>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let value = match.payload {
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

    mutating func validateContainerPredicate(
        _ predicate: ContainerPredicate,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        for (index, check) in predicate.core.checks.enumerated() {
            validateContainerPredicateCheck(
                check,
                path: path.child(.checks).index(index),
                scope: scope
            )
        }
    }

    private mutating func validateContainerPredicateCheck(
        _ check: ContainerPredicateCheckCore<AuthoredString>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch check {
        case .type, .rowCount, .columnCount, .modalBoundary, .scrollable:
            return
        case .identifier(let match):
            validateString(match, path: path.child(.identifier), scope: scope)
        case .actions(let actions):
            validateContainerActions(actions.values, path: path.child(.actions))
        case .semantic(let predicate):
            validateSemanticContainerPredicate(predicate, path: path.child(.semantic), scope: scope)
        }
    }

    private mutating func validateSemanticContainerPredicate(
        _ predicate: SemanticContainerPredicateCore<AuthoredString>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch predicate {
        case .label(let match):
            validateString(match, path: path.child(.label), scope: scope)
        case .value(let match):
            validateString(match, path: path.child(.value), scope: scope)
        }
    }

    private mutating func validateContainerActions(_ actions: Set<ElementAction>, path: HeistPlanPath) {
        guard !actions.isEmpty else {
            fail(
                path: path,
                contract: "container actions check must not be empty",
                observed: "[]",
                correction: "Use at least one action."
            )
            return
        }
    }

    mutating func validateOrdinal(_ ordinal: Int?, path: HeistPlanPath) {
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
        path: HeistPlanPath,
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
        for (index, check) in predicate.core.checks.enumerated() {
            validateElementPredicateCheck(
                check,
                path: path.child(.checks).index(index),
                scope: scope
            )
        }
    }

    private mutating func validateElementPredicateCheck(
        _ check: ElementPredicateCheckCore<AuthoredString>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let description = check.invalidEmptyPayloadDescription {
            fail(
                path: path,
                contract: "element predicate check payload must not be empty",
                observed: description,
                correction: "Use non-empty matcher values and non-empty trait/action/rotor collections."
            )
        }

        switch check {
        case .label(let match):
            validateString(match, path: path.child(.label), scope: scope)
        case .identifier(let match):
            validateString(match, path: path.child(.identifier), scope: scope)
        case .value(let match):
            validateString(match, path: path.child(.value), scope: scope)
        case .hint(let match):
            validateString(match, path: path.child(.hint), scope: scope)
        case .traits, .actions:
            break
        case .customContent(let match):
            if let label = match.label {
                validateString(label, path: path.child(.customContent).child(.label), scope: scope)
            }
            if let value = match.value {
                validateString(value, path: path.child(.customContent).child(.value), scope: scope)
            }
        case .rotors(let matches):
            validateStrings(matches, path: path.child(.rotors), scope: scope)
        case .exclude(let excluded):
            validateElementPredicateCheck(excluded, path: path.child(.exclude), scope: scope)
        }
    }

    mutating func validateReference(_ reference: HeistReferenceName, path: HeistPlanPath, role: String) {
        addParameterString(reference.rawValue, path: path, role: role)
    }

    mutating func addParameterString(_ value: String, path: HeistPlanPath, role: String) {
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

    mutating func addString(_ value: String?, path: HeistPlanPath, role: String) {
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

    private mutating func validateStrings(
        _ matches: [StringMatchCore<AuthoredString>],
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        for (index, match) in matches.enumerated() {
            validateString(match, path: path.index(index), scope: scope)
        }
    }
}

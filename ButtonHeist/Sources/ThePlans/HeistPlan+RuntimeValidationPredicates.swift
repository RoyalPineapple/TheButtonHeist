import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validatePredicate(
        _ predicate: AccessibilityPredicateExpr,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        switch predicate {
        case .predicate(let predicate):
            validatePredicate(predicate, path: path, depth: depth)
        case .state(let state):
            validateStatePredicate(state, path: path, depth: depth, scope: scope)
        case .changePredicate(let change):
            validateChangePredicate(change, path: path, depth: depth, scope: scope)
        case .noChangePredicate:
            break
        }
    }

    mutating func validatePredicate(
        _ predicate: AccessibilityPredicate,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch predicate {
        case .state(let state):
            validateStatePredicate(state, path: path, depth: depth)
        case .changePredicate(let change):
            validateChangePredicate(change, path: path, depth: depth)
        case .noChangePredicate:
            break
        }
    }

    mutating func validateStatePredicate(
        _ state: AccessibilityPredicate.State,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch state.contract {
        case .element(_, let predicate):
            validateElementPredicate(predicate, path: "\(path).element")
        case .target(_, let target):
            validateElementTarget(target, path: "\(path).target")
        case .all(let states):
            validateAllChildCount(states.count, path: "\(path).states")
            for (index, child) in states.enumerated() {
                validateStatePredicate(child, path: "\(path).states[\(index)]", depth: depth + 1)
            }
        }
    }

    mutating func validateStatePredicate(
        _ state: StatePredicateExpr,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch state.predicateContract {
        case .element(_, let predicate):
            validateElementPredicate(predicate, path: "\(path).element", scope: scope)
        case .target(_, let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        case .all(let states):
            validateAllChildCount(states.count, path: "\(path).states")
            for (index, child) in states.enumerated() {
                validateStatePredicate(child, path: "\(path).states[\(index)]", depth: depth + 1, scope: scope)
            }
        }
    }

    mutating func validateChangePredicate(
        _ change: AccessibilityPredicate.Change,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch change.contract {
        case .any:
            break
        case .screen(let states):
            validateAllChildCount(states.count, path: "\(path).screen")
            for (index, state) in states.enumerated() {
                validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1)
            }
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).elements")
            for (index, assertion) in assertions.enumerated() {
                validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]")
            }
        case .all(let changes):
            validateAllChildCount(changes.count, path: "\(path).scopes")
            for (index, child) in changes.enumerated() {
                validateChangeScope(child, path: "\(path).scopes[\(index)]", depth: depth + 1)
            }
        }
    }

    mutating func validateChangeScope(
        _ change: AccessibilityPredicate.ChangeScope,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch change.contract {
        case .screen(let states):
            validateAllChildCount(states.count, path: "\(path).screen")
            for (index, state) in states.enumerated() {
                validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1)
            }
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).elements")
            for (index, assertion) in assertions.enumerated() {
                validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]")
            }
        case .all(let changes):
            validateAllChildCount(changes.count, path: "\(path).scopes")
            for (index, child) in changes.enumerated() {
                validateChangeScope(child, path: "\(path).scopes[\(index)]", depth: depth + 1)
            }
        }
    }

    mutating func validateChangePredicate(
        _ change: ChangePredicateExpr,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch change.predicateContract {
        case .any:
            break
        case .screen(let states):
            validateAllChildCount(states.count, path: "\(path).screen")
            for (index, state) in states.enumerated() {
                validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1, scope: scope)
            }
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).elements")
            for (index, assertion) in assertions.enumerated() {
                validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]", scope: scope)
            }
        case .all(let changes):
            validateAllChildCount(changes.count, path: "\(path).scopes")
            for (index, child) in changes.enumerated() {
                validateChangeScope(child, path: "\(path).scopes[\(index)]", depth: depth + 1, scope: scope)
            }
        }
    }

    mutating func validateChangeScope(
        _ change: ChangeScopePredicateExpr,
        path: String,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch change.predicateContract {
        case .screen(let states):
            validateAllChildCount(states.count, path: "\(path).screen")
            for (index, state) in states.enumerated() {
                validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1, scope: scope)
            }
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).elements")
            for (index, assertion) in assertions.enumerated() {
                validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]", scope: scope)
            }
        case .all(let changes):
            validateAllChildCount(changes.count, path: "\(path).scopes")
            for (index, child) in changes.enumerated() {
                validateChangeScope(child, path: "\(path).scopes[\(index)]", depth: depth + 1, scope: scope)
            }
        }
    }

    mutating func validateElementDeltaPredicate(
        _ predicate: ElementDeltaPredicate,
        path: String
    ) {
        switch predicate {
        case .appearedElement(let element), .disappearedElement(let element):
            validateElementPredicate(element, path: "\(path).element")
        case .updatedElement(let update):
            if let element = update.element {
                validateElementPredicate(element, path: "\(path).element")
            }
            validatePropertyChange(update.change, path: "\(path).change")
        }
    }

    mutating func validateElementDeltaPredicate(
        _ predicate: ElementDeltaPredicateExpr,
        path: String,
        scope: HeistReferenceScope
    ) {
        switch predicate {
        case .appearedElement(let element), .disappearedElement(let element):
            validateElementPredicate(element, path: "\(path).element", scope: scope)
        case .updatedElement(let update):
            if let element = update.element {
                validateElementPredicate(element, path: "\(path).element", scope: scope)
            }
            validatePropertyChange(update.change, path: "\(path).change", scope: scope)
        }
    }

    mutating func validatePropertyChange(
        _ change: AnyPropertyChange?,
        path: String
    ) {
        guard let change else { return }
        switch change {
        case .value(let change):
            validateStringPropertyChange(change, path: path)
        case .traits:
            break
        case .hint(let change):
            validateStringPropertyChange(change, path: path)
        case .actions, .frame, .activationPoint:
            break
        case .customContent(let change):
            validateNestedStringPropertyChange(change, path: path)
        case .rotors(let change):
            validateNestedStringPropertyChange(change, path: path)
        }
    }

    mutating func validateStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChange<P>,
        path: String
    ) where P.Checker == StringMatch<String> {
        validateString(change.before, path: "\(path).before", role: "element update before value")
        validateString(change.after, path: "\(path).after", role: "element update after value")
    }

    mutating func validatePropertyChange(
        _ change: AnyPropertyChangeExpr?,
        path: String,
        scope: HeistReferenceScope
    ) {
        guard let change else { return }
        switch change {
        case .value(let change):
            validateStringPropertyChange(change, path: path, scope: scope)
        case .traits:
            break
        case .hint(let change):
            validateStringPropertyChange(change, path: path, scope: scope)
        case .actions, .frame, .activationPoint:
            break
        case .customContent(let change):
            validateNestedStringPropertyChange(change, path: path, scope: scope)
        case .rotors(let change):
            validateNestedStringPropertyChange(change, path: path, scope: scope)
        }
    }

    mutating func validateStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChangeExpr<P>,
        path: String,
        scope: HeistReferenceScope
    ) where P.ExprChecker == StringMatch<StringExpr> {
        if let before = change.before {
            validateString(before, path: "\(path).before", scope: scope)
        }
        if let after = change.after {
            validateString(after, path: "\(path).after", scope: scope)
        }
    }

    private mutating func validateNestedStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChange<P>,
        path: String
    ) where P.Checker: NestedStringMatchContainer, P.Checker.Payload == String {
        if let before = change.before {
            validateNestedStrings(before, path: "\(path).before")
        }
        if let after = change.after {
            validateNestedStrings(after, path: "\(path).after")
        }
    }

    private mutating func validateNestedStrings<Container: NestedStringMatchContainer>(
        _ container: Container,
        path: String
    ) where Container.Payload == String {
        for nested in container.nestedStringMatches {
            validateString(nested.match, path: "\(path).\(nested.path)", role: nested.role)
        }
    }

    private mutating func validateNestedStringPropertyChange<P: ElementPropertyKind>(
        _ change: ElementPropertyChangeExpr<P>,
        path: String,
        scope: HeistReferenceScope
    ) where P.ExprChecker: NestedStringMatchContainer, P.ExprChecker.Payload == StringExpr {
        if let before = change.before {
            validateNestedStrings(before, path: "\(path).before", scope: scope)
        }
        if let after = change.after {
            validateNestedStrings(after, path: "\(path).after", scope: scope)
        }
    }

    private mutating func validateNestedStrings<Container: NestedStringMatchContainer>(
        _ container: Container,
        path: String,
        scope: HeistReferenceScope
    ) where Container.Payload == StringExpr {
        for nested in container.nestedStringMatches {
            validateString(nested.match, path: "\(path).\(nested.path)", scope: scope)
        }
    }

    mutating func checkPredicateDepth(_ depth: Int, path: String) {
        if depth > limits.maxPredicateDepth {
            fail(
                path: path,
                contract: "max predicate depth",
                observed: "depth \(depth)",
                correction: "Use predicates nested \(limits.maxPredicateDepth) levels or fewer."
            )
        }
    }

    mutating func validateAllChildCount(_ count: Int, path: String) {
        if count > limits.maxAllPredicateChildren {
            fail(
                path: path,
                contract: "max .all child count",
                observed: "\(count) children",
                correction: "Use \(limits.maxAllPredicateChildren) child predicates or fewer."
            )
        }
    }

}

private enum StatePredicateExprContract {
    case element(AccessibilityPredicateContract.PresenceRequirement, ElementPredicateTemplate)
    case target(AccessibilityPredicateContract.PresenceRequirement, ElementTargetExpr)
    case all(NonEmptyArray<StatePredicateExpr>)
}

private enum ChangePredicateExprContract {
    case any
    case screen([StatePredicateExpr])
    case elements([ElementDeltaPredicateExpr])
    case all(NonEmptyArray<ChangeScopePredicateExpr>)
}

private enum ChangeScopePredicateExprContract {
    case screen([StatePredicateExpr])
    case elements([ElementDeltaPredicateExpr])
    case all(NonEmptyArray<ChangeScopePredicateExpr>)
}

private extension StatePredicateExpr {
    var predicateContract: StatePredicateExprContract {
        switch self {
        case .exists(let predicate):
            return .element(.present, predicate)
        case .missing(let predicate):
            return .element(.absent, predicate)
        case .existsTarget(let target):
            return .target(.present, target)
        case .missingTarget(let target):
            return .target(.absent, target)
        case .all(let states):
            return .all(states)
        }
    }
}

private struct NestedStringMatch<Payload: StringMatchPayload & Codable> {
    let path: String
    let role: String
    let match: StringMatch<Payload>
}

private protocol NestedStringMatchContainer {
    associatedtype Payload: StringMatchPayload & Codable

    var nestedStringMatches: [NestedStringMatch<Payload>] { get }
}

extension CustomContentMatch: NestedStringMatchContainer {
    fileprivate var nestedStringMatches: [NestedStringMatch<Value>] {
        [
            label.map { NestedStringMatch(path: "label", role: "custom content label", match: $0) },
            value.map { NestedStringMatch(path: "value", role: "custom content value", match: $0) },
        ].compactMap { $0 }
    }
}

extension RotorSetMatch: NestedStringMatchContainer {
    fileprivate var nestedStringMatches: [NestedStringMatch<Value>] {
        include.enumerated().map { index, match in
            NestedStringMatch(path: "include[\(index)]", role: "rotor include", match: match)
        } + exclude.enumerated().map { index, match in
            NestedStringMatch(path: "exclude[\(index)]", role: "rotor exclude", match: match)
        }
    }
}

private extension ChangePredicateExpr {
    var predicateContract: ChangePredicateExprContract {
        switch self {
        case .any:
            return .any
        case .screenScope(let states):
            return .screen(states)
        case .elementsScope(let assertions):
            return .elements(assertions)
        case .allScopes(let changes):
            return .all(changes)
        }
    }
}

private extension ChangeScopePredicateExpr {
    var predicateContract: ChangeScopePredicateExprContract {
        switch self {
        case .screen(let states):
            return .screen(states)
        case .elements(let assertions):
            return .elements(assertions)
        case .all(let changes):
            return .all(changes)
        }
    }
}

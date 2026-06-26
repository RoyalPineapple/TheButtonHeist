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
            switch change {
            case .any:
                break
            case .screenScope(let states):
                validateAllChildCount(states.count, path: "\(path).screen")
                for (index, state) in states.enumerated() {
                    validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1)
                }
            case .elementsScope(let assertions):
                validateAllChildCount(assertions.count, path: "\(path).elements")
                for (index, assertion) in assertions.enumerated() {
                    validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]")
                }
            case .allScopes(let changes):
                validateAllChildCount(changes.count, path: "\(path).scopes")
                for (index, child) in changes.enumerated() {
                    validatePredicate(.changePredicate(child), path: "\(path).scopes[\(index)]", depth: depth + 1)
                }
            }
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
        switch state {
        case .exists(let predicate), .missing(let predicate):
            validateElementPredicate(predicate, path: "\(path).element")
        case .existsTarget(let target), .missingTarget(let target):
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
        switch state {
        case .exists(let predicate), .missing(let predicate):
            validateElementPredicate(predicate, path: "\(path).element", scope: scope)
        case .existsTarget(let target), .missingTarget(let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        case .all(let states):
            validateAllChildCount(states.count, path: "\(path).states")
            for (index, child) in states.enumerated() {
                validateStatePredicate(child, path: "\(path).states[\(index)]", depth: depth + 1, scope: scope)
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
        switch change {
        case .any:
            break
        case .screenScope(let states):
            validateAllChildCount(states.count, path: "\(path).screen")
            for (index, state) in states.enumerated() {
                validateStatePredicate(state, path: "\(path).screen[\(index)]", depth: depth + 1, scope: scope)
            }
        case .elementsScope(let assertions):
            validateAllChildCount(assertions.count, path: "\(path).elements")
            for (index, assertion) in assertions.enumerated() {
                validateElementDeltaPredicate(assertion, path: "\(path).elements[\(index)]", scope: scope)
            }
        case .allScopes(let changes):
            validateAllChildCount(changes.count, path: "\(path).scopes")
            for (index, child) in changes.enumerated() {
                validateChangePredicate(child, path: "\(path).scopes[\(index)]", depth: depth + 1, scope: scope)
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
            if let before = update.before {
                validateElementPredicate(before, path: "\(path).before")
            }
            if let after = update.after {
                validateElementPredicate(after, path: "\(path).after")
            }
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
            if let before = update.before {
                validateElementPredicate(before, path: "\(path).before", scope: scope)
            }
            if let after = update.after {
                validateElementPredicate(after, path: "\(path).after", scope: scope)
            }
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

import Foundation

extension HeistPlanRuntimeValidator {
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
        case .changed(let change):
            validateChangePredicate(change, path: path, depth: depth, scope: scope)
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
        case .changed(let change):
            switch change {
            case .screen(let state):
                if let state {
                    validateStatePredicate(state, path: "\(path).where", depth: depth + 1)
                }
            case .appeared(let predicate), .disappeared(let predicate):
                validateElementPredicate(predicate, path: "\(path).element")
            case .updated(let update):
                if let element = update.element {
                    validateElementPredicate(element, path: "\(path).element")
                }
                addString(update.from, path: "\(path).from", role: "change predicate from value")
                addString(update.to, path: "\(path).to", role: "change predicate to value")
            case .elements:
                break
            }
        }
    }

    mutating func validateStatePredicate(
        _ state: AccessibilityPredicate.State,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch state {
        case .present(let predicate), .absent(let predicate):
            validateElementPredicate(predicate, path: "\(path).element")
        case .presentTarget(let target), .absentTarget(let target):
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
        case .present(let predicate), .absent(let predicate):
            validateElementPredicate(predicate, path: "\(path).element", scope: scope)
        case .presentTarget(let target), .absentTarget(let target):
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
        case .screen(let state):
            if let state {
                validateStatePredicate(state, path: "\(path).where", depth: depth + 1, scope: scope)
            }
        case .appeared(let predicate), .disappeared(let predicate):
            validateElementPredicate(predicate, path: "\(path).element", scope: scope)
        case .updated(let update):
            if let element = update.element {
                validateElementPredicate(element, path: "\(path).element", scope: scope)
            }
            if let from = update.from {
                validateString(from, path: "\(path).from", scope: scope)
            }
            if let to = update.to {
                validateString(to, path: "\(path).to", scope: scope)
            }
        case .elements:
            break
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

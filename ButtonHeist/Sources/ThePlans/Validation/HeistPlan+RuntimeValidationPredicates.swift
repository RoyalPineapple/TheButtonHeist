import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validatePredicate(
        _ predicate: AccessibilityPredicate,
        path: HeistPlanPath,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch predicate.core {
        case .presence(let presence):
            validatePresence(presence, path: path, scope: scope)
        case .announcement(let announcement):
            if let match = announcement.match {
                validateString(match, path: path.child(.match), scope: scope)
            }
        case .changed(let declaration):
            validateChange(declaration, path: path.child(.changed), depth: depth + 1, scope: scope)
        case .noChange:
            break
        }
    }

    mutating func validatePredicate(
        _ predicate: ChangeDeclaration.ScreenAssertion,
        path: HeistPlanPath,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch predicate {
        case .exists(let target), .missing(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    private mutating func validatePresence(
        _ presence: AccessibilityPredicate.Presence,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch presence {
        case .exists(let target), .missing(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    private mutating func validateChange(
        _ declaration: ChangeDeclaration,
        path: HeistPlanPath,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch declaration {
        case .screen(let assertions):
            validateAllChildCount(assertions.count, path: path.child(.assertions))
        case .elements(let assertions):
            validateAllChildCount(assertions.count, path: path.child(.assertions))
        }
        switch declaration {
        case .screen(let assertions):
            for (index, assertion) in assertions.enumerated() {
                validateScreenAssertion(
                    assertion,
                    path: path.child(.assertions).index(index),
                    depth: depth + 1,
                    scope: scope
                )
            }
        case .elements(let assertions):
            for (index, assertion) in assertions.enumerated() {
                validateElementAssertion(
                    assertion,
                    path: path.child(.assertions).index(index),
                    depth: depth + 1,
                    scope: scope
                )
            }
        }
    }

    private mutating func validateScreenAssertion(
        _ assertion: ChangeDeclaration.ScreenAssertion,
        path: HeistPlanPath,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch assertion {
        case .exists(let target), .missing(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    private mutating func validateElementAssertion(
        _ assertion: ChangeDeclaration.ElementAssertion,
        path: HeistPlanPath,
        depth: Int,
        scope: HeistReferenceScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch assertion {
        case .exists(let target), .missing(let target), .appeared(let target), .disappeared(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        case .updated(let target, let change):
            validateTarget(target, path: path.child(.target), scope: scope)
            validatePropertyChange(change, path: path.child(.change), scope: scope)
        }
    }

    private mutating func validatePropertyChange(
        _ change: ElementPropertyChange,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch change.value {
        case .value(let change), .hint(let change):
            validateStringPropertyChange(change, path: path, scope: scope)
        case .traits, .actions, .frame, .activationPoint:
            break
        case .customContent(let change):
            validateCustomContentPropertyChange(change, path: path, scope: scope)
        case .rotors(let change):
            validateRotorPropertyChange(change, path: path, scope: scope)
        }
    }

    private mutating func validateStringPropertyChange(
        _ change: PropertyChangeCore<StringMatch>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let before = change.before {
            validateString(before, path: path.child(.before), scope: scope)
        }
        if let after = change.after {
            validateString(after, path: path.child(.after), scope: scope)
        }
    }

    private mutating func validateCustomContentPropertyChange(
        _ change: PropertyChangeCore<CustomContentMatch>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let before = change.before {
            validateCustomContent(before, path: path.child(.before), scope: scope)
        }
        if let after = change.after {
            validateCustomContent(after, path: path.child(.after), scope: scope)
        }
    }

    private mutating func validateCustomContent(
        _ match: CustomContentMatch,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let label = match.label {
            validateString(label, path: path.child(.label), scope: scope)
        }
        if let value = match.value {
            validateString(value, path: path.child(.value), scope: scope)
        }
    }

    private mutating func validateRotorPropertyChange(
        _ change: PropertyChangeCore<RotorSetMatch>,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        if let before = change.before {
            validateRotorSet(before, path: path.child(.before), scope: scope)
        }
        if let after = change.after {
            validateRotorSet(after, path: path.child(.after), scope: scope)
        }
    }

    private mutating func validateRotorSet(
        _ match: RotorSetMatch,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        for (index, include) in match.include.enumerated() {
            validateString(include, path: path.child(.include).index(index), scope: scope)
        }
        for (index, exclude) in match.exclude.enumerated() {
            validateString(exclude, path: path.child(.exclude).index(index), scope: scope)
        }
    }

    mutating func checkPredicateDepth(_ depth: Int, path: HeistPlanPath) {
        if depth > limits.maxPredicateDepth {
            fail(
                path: path,
                contract: "max predicate depth",
                observed: "depth \(depth)",
                correction: "Use predicates nested \(limits.maxPredicateDepth) levels or fewer."
            )
        }
    }

    mutating func validateAllChildCount(_ count: Int, path: HeistPlanPath) {
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

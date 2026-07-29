import Foundation

extension HeistPlanRuntimeSafetyValidator {
    mutating func validatePredicate(
        _ predicate: AccessibilityPredicate,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch predicate.core {
        case .presence(let presence):
            validatePredicate(presence, path: path, scope: scope)
        case .notification(let notification):
            if let text = notification.text {
                validateString(text, path: path.child(.text), scope: scope)
            }
            if let element = notification.element {
                validateElementPredicate(
                    element,
                    path: path.child(.element),
                    scope: scope
                )
            }
        case .screenChanged(let screen):
            // A screen predicate names no elements: there is no child list to
            // bound and no target to resolve, only the name it arrived at.
            if let match = screen.match {
                validateString(match, path: path.child(.match), scope: scope)
            }
        case .elementsChanged(let assertions):
            let assertionsPath = path.child(.assertions)
            validateAllChildCount(assertions.count, path: assertionsPath)
            for (index, assertion) in assertions.enumerated() {
                validateElementAssertion(
                    assertion,
                    path: assertionsPath.index(index),
                    scope: scope
                )
            }
        }
    }

    mutating func validatePredicate(
        _ predicate: PresenceCondition,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch predicate {
        case .exists(let target), .missing(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        }
    }

    private mutating func validateElementAssertion(
        _ assertion: ElementAssertion,
        path: HeistPlanPath,
        scope: HeistReferenceScope
    ) {
        switch assertion {
        case .exists(let target), .missing(let target), .appeared(let target), .disappeared(let target):
            validateTarget(target, path: path.child(.target), scope: scope)
        case .updated(let target, let change):
            validateTarget(target.accessibilityTarget, path: path.child(.target), scope: scope)
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
        case .traits, .actions:
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

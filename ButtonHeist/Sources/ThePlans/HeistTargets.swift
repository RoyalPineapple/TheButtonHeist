public extension ElementTarget {
    static func label(_ label: String) -> ElementTarget {
        .predicate(.label(label))
    }

    static func label(_ label: StringMatch<String>) -> ElementTarget {
        .predicate(.label(label))
    }

    static func identifier(_ identifier: String) -> ElementTarget {
        .predicate(.identifier(identifier))
    }

    static func identifier(_ identifier: StringMatch<String>) -> ElementTarget {
        .predicate(.identifier(identifier))
    }

    static func value(_ value: String) -> ElementTarget {
        .predicate(.value(value))
    }

    static func value(_ value: StringMatch<String>) -> ElementTarget {
        .predicate(.value(value))
    }

    static func traits(_ traits: [HeistTrait]) -> ElementTarget {
        .predicate(.traits(traits))
    }

    static func excludeTraits(_ traits: [HeistTrait]) -> ElementTarget {
        .predicate(.excludeTraits(traits))
    }

    static func element(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementTarget {
        .predicate(.element(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        ))
    }

    static func element(
        _ checks: ElementPredicateCheck<String>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementTarget {
        .predicate(ElementPredicate(checks, traits: traits, excludeTraits: excludeTraits))
    }

    static func target(_ predicate: ElementPredicate, ordinal: Int) -> ElementTarget {
        .predicate(predicate, ordinal: ordinal)
    }
}

public extension ElementPredicateTemplate {
    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: label)
    }

    static func label(_ label: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: StringMatch(label))
    }

    static func label(_ label: String) -> ElementPredicateTemplate {
        .label(.literal(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: identifier)
    }

    static func identifier(_ identifier: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: StringMatch(identifier))
    }

    static func identifier(_ identifier: String) -> ElementPredicateTemplate {
        .identifier(.literal(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: value)
    }

    static func value(_ value: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: StringMatch(value))
    }

    static func value(_ value: String) -> ElementPredicateTemplate {
        .value(.literal(value))
    }

    static func traits(_ traits: [HeistTrait]) -> ElementPredicateTemplate {
        ElementPredicateTemplate(traits: traits)
    }

    static func excludeTraits(_ traits: [HeistTrait]) -> ElementPredicateTemplate {
        ElementPredicateTemplate(excludeTraits: traits)
    }

    static func element(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementPredicateTemplate {
        ElementPredicateTemplate(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementPredicateTemplate {
        ElementPredicateTemplate(checks, traits: traits, excludeTraits: excludeTraits)
    }
}

public extension ElementTargetExpr {
    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> ElementTargetExpr {
        .predicate(.label(label))
    }

    static func label(_ label: StringExpr) -> ElementTargetExpr {
        .predicate(.label(StringMatch(label)))
    }

    @_disfavoredOverload
    static func label(_ label: String) -> ElementTargetExpr {
        .predicate(.label(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> ElementTargetExpr {
        .predicate(.identifier(identifier))
    }

    static func identifier(_ identifier: StringExpr) -> ElementTargetExpr {
        .predicate(.identifier(StringMatch(identifier)))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: String) -> ElementTargetExpr {
        .predicate(.identifier(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> ElementTargetExpr {
        .predicate(.value(value))
    }

    static func value(_ value: StringExpr) -> ElementTargetExpr {
        .predicate(.value(StringMatch(value)))
    }

    @_disfavoredOverload
    static func value(_ value: String) -> ElementTargetExpr {
        .predicate(.value(value))
    }

    static func traits(_ traits: [HeistTrait]) -> ElementTargetExpr {
        .predicate(.traits(traits))
    }

    static func excludeTraits(_ traits: [HeistTrait]) -> ElementTargetExpr {
        .predicate(.excludeTraits(traits))
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementTargetExpr {
        .predicate(ElementPredicateTemplate(checks, traits: traits, excludeTraits: excludeTraits))
    }

    static func target(_ predicate: ElementPredicateTemplate, ordinal: Int) -> ElementTargetExpr {
        .predicate(predicate, ordinal: ordinal)
    }
}

public extension AccessibilityPredicate {
    static func change(_ changes: AccessibilityPredicate.Change...) -> AccessibilityPredicate {
        switch changes.count {
        case 0:
            return .changePredicate(.any)
        case 1:
            return .changePredicate(changes[0])
        default:
            return .changePredicate(.allScopes(changes))
        }
    }

    static var noChange: AccessibilityPredicate {
        .noChangePredicate
    }

    static func exists(_ predicate: ElementPredicate) -> AccessibilityPredicate {
        .state(.exists(predicate))
    }

    @_disfavoredOverload
    static func exists(_ target: ElementTarget) -> AccessibilityPredicate {
        .state(.existsTarget(target))
    }

    static func missing(_ predicate: ElementPredicate) -> AccessibilityPredicate {
        .state(.missing(predicate))
    }

    @_disfavoredOverload
    static func missing(_ target: ElementTarget) -> AccessibilityPredicate {
        .state(.missingTarget(target))
    }

    static func all(_ states: [AccessibilityPredicate.State]) -> AccessibilityPredicate {
        .state(.all(states))
    }
}

public extension AccessibilityPredicateExpr {
    static func exists(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .state(.exists(predicate))
    }

    @_disfavoredOverload
    static func exists(_ target: ElementTargetExpr) -> AccessibilityPredicateExpr {
        .state(.existsTarget(target))
    }

    static func missing(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .state(.missing(predicate))
    }

    @_disfavoredOverload
    static func missing(_ target: ElementTargetExpr) -> AccessibilityPredicateExpr {
        .state(.missingTarget(target))
    }

    static func change(_ changes: ChangePredicateExpr...) -> AccessibilityPredicateExpr {
        switch changes.count {
        case 0:
            return .changePredicate(.any)
        case 1:
            return .changePredicate(changes[0])
        default:
            return .changePredicate(.allScopes(changes))
        }
    }

    static var noChange: AccessibilityPredicateExpr {
        .noChangePredicate
    }

    static func all(_ states: [StatePredicateExpr]) -> AccessibilityPredicateExpr {
        .state(.all(states))
    }
}

public extension StatePredicateExpr {
    @_disfavoredOverload
    static func exists(_ target: ElementTargetExpr) -> StatePredicateExpr {
        .existsTarget(target)
    }

    @_disfavoredOverload
    static func missing(_ target: ElementTargetExpr) -> StatePredicateExpr {
        .missingTarget(target)
    }
}

public extension ChangePredicateExpr {
    static func screen() -> ChangePredicateExpr {
        .screenScope([])
    }

    static func screen(_ first: StatePredicateExpr, _ rest: StatePredicateExpr...) -> ChangePredicateExpr {
        .screenScope([first] + rest)
    }

    static func elements() -> ChangePredicateExpr {
        .elementsScope([])
    }

    static func elements(_ first: ElementDeltaPredicateExpr, _ rest: ElementDeltaPredicateExpr...) -> ChangePredicateExpr {
        .elementsScope([first] + rest)
    }

    static func all(_ changes: ChangePredicateExpr...) -> ChangePredicateExpr {
        .allScopes(changes)
    }
}

public extension AccessibilityPredicate.Change {
    static func screen() -> AccessibilityPredicate.Change {
        .screenScope([])
    }

    static func screen(_ first: AccessibilityPredicate.State, _ rest: AccessibilityPredicate.State...) -> AccessibilityPredicate.Change {
        .screenScope([first] + rest)
    }

    static func elements() -> AccessibilityPredicate.Change {
        .elementsScope([])
    }

    static func elements(_ first: ElementDeltaPredicate, _ rest: ElementDeltaPredicate...) -> AccessibilityPredicate.Change {
        .elementsScope([first] + rest)
    }

    static func all(_ changes: AccessibilityPredicate.Change...) -> AccessibilityPredicate.Change {
        .allScopes(changes)
    }
}

public extension ElementDeltaPredicateExpr {
    static func appeared(_ predicate: ElementPredicateTemplate) -> ElementDeltaPredicateExpr {
        .appearedElement(predicate)
    }

    static func disappeared(_ predicate: ElementPredicateTemplate) -> ElementDeltaPredicateExpr {
        .disappearedElement(predicate)
    }

    static func updated(
        before: ElementPredicateTemplate? = nil,
        after: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil
    ) -> ElementDeltaPredicateExpr {
        .updatedElement(ElementUpdatePredicateExpr(
            before: before,
            after: after,
            property: property
        ))
    }
}

public extension ElementDeltaPredicate {
    static func appeared(_ predicate: ElementPredicate) -> ElementDeltaPredicate {
        .appearedElement(predicate)
    }

    static func disappeared(_ predicate: ElementPredicate) -> ElementDeltaPredicate {
        .disappearedElement(predicate)
    }

    static func updated(
        before: ElementPredicate? = nil,
        after: ElementPredicate? = nil,
        property: ElementProperty? = nil
    ) -> ElementDeltaPredicate {
        .updatedElement(ElementUpdatePredicate(
            before: before,
            after: after,
            property: property
        ))
    }
}

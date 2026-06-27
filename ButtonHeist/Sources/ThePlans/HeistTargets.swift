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

    static func all(_ first: AccessibilityPredicate.State, _ rest: AccessibilityPredicate.State...) -> AccessibilityPredicate {
        .state(.all([first] + rest))
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

    static func all(_ first: StatePredicateExpr, _ rest: StatePredicateExpr...) -> AccessibilityPredicateExpr {
        .state(.all([first] + rest))
    }

    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> AccessibilityPredicateExpr {
        .exists(.label(label))
    }

    static func label(_ label: StringExpr) -> AccessibilityPredicateExpr {
        .exists(.label(label))
    }

    static func label(_ label: String) -> AccessibilityPredicateExpr {
        .exists(.label(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> AccessibilityPredicateExpr {
        .exists(.identifier(identifier))
    }

    static func identifier(_ identifier: StringExpr) -> AccessibilityPredicateExpr {
        .exists(.identifier(identifier))
    }

    static func identifier(_ identifier: String) -> AccessibilityPredicateExpr {
        .exists(.identifier(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> AccessibilityPredicateExpr {
        .exists(.value(value))
    }

    static func value(_ value: StringExpr) -> AccessibilityPredicateExpr {
        .exists(.value(value))
    }

    static func value(_ value: String) -> AccessibilityPredicateExpr {
        .exists(.value(value))
    }

    static func traits(_ traits: [HeistTrait]) -> AccessibilityPredicateExpr {
        .exists(.traits(traits))
    }

    static func excludeTraits(_ traits: [HeistTrait]) -> AccessibilityPredicateExpr {
        .exists(.excludeTraits(traits))
    }

    static func element(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> AccessibilityPredicateExpr {
        .exists(.element(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        ))
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> AccessibilityPredicateExpr {
        .exists(ElementPredicateTemplate(checks, traits: traits, excludeTraits: excludeTraits))
    }

    static func appeared(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .change(.appeared(predicate))
    }

    static func disappeared(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .change(.disappeared(predicate))
    }

    static func updated() -> AccessibilityPredicateExpr {
        .change(.updated())
    }

    static func updated(_ change: AnyPropertyChangeExpr) -> AccessibilityPredicateExpr {
        .change(.updated(change))
    }

    static func updated(element: ElementPredicateTemplate, _ change: AnyPropertyChangeExpr? = nil) -> AccessibilityPredicateExpr {
        .change(.updated(element: element, change))
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

    static func all(_ first: StatePredicateExpr, _ rest: StatePredicateExpr...) -> StatePredicateExpr {
        .all([first] + rest)
    }

    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> StatePredicateExpr {
        .exists(.label(label))
    }

    static func label(_ label: StringExpr) -> StatePredicateExpr {
        .exists(.label(label))
    }

    static func label(_ label: String) -> StatePredicateExpr {
        .exists(.label(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> StatePredicateExpr {
        .exists(.identifier(identifier))
    }

    static func identifier(_ identifier: StringExpr) -> StatePredicateExpr {
        .exists(.identifier(identifier))
    }

    static func identifier(_ identifier: String) -> StatePredicateExpr {
        .exists(.identifier(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> StatePredicateExpr {
        .exists(.value(value))
    }

    static func value(_ value: StringExpr) -> StatePredicateExpr {
        .exists(.value(value))
    }

    static func value(_ value: String) -> StatePredicateExpr {
        .exists(.value(value))
    }

    static func traits(_ traits: [HeistTrait]) -> StatePredicateExpr {
        .exists(.traits(traits))
    }

    static func excludeTraits(_ traits: [HeistTrait]) -> StatePredicateExpr {
        .exists(.excludeTraits(traits))
    }

    static func element(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> StatePredicateExpr {
        .exists(.element(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        ))
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> StatePredicateExpr {
        .exists(ElementPredicateTemplate(checks, traits: traits, excludeTraits: excludeTraits))
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

    static func appeared(_ predicate: ElementPredicateTemplate) -> ChangePredicateExpr {
        .elementsScope([.appearedElement(predicate)])
    }

    static func disappeared(_ predicate: ElementPredicateTemplate) -> ChangePredicateExpr {
        .elementsScope([.disappearedElement(predicate)])
    }

    static func updated() -> ChangePredicateExpr {
        .elementsScope([.updatedElement(ElementUpdatePredicateExpr())])
    }

    static func updated(_ change: AnyPropertyChangeExpr) -> ChangePredicateExpr {
        .elementsScope([.updatedElement(ElementUpdatePredicateExpr(change: change))])
    }

    static func updated(element: ElementPredicateTemplate, _ change: AnyPropertyChangeExpr? = nil) -> ChangePredicateExpr {
        .elementsScope([.updatedElement(ElementUpdatePredicateExpr(element: element, change: change))])
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

    static func appeared(_ predicate: ElementPredicate) -> AccessibilityPredicate.Change {
        .elementsScope([.appearedElement(predicate)])
    }

    static func disappeared(_ predicate: ElementPredicate) -> AccessibilityPredicate.Change {
        .elementsScope([.disappearedElement(predicate)])
    }

    static func updated() -> AccessibilityPredicate.Change {
        .elementsScope([.updatedElement(ElementUpdatePredicate())])
    }

    static func updated(_ change: AnyPropertyChange) -> AccessibilityPredicate.Change {
        .elementsScope([.updatedElement(ElementUpdatePredicate(change: change))])
    }

    static func updated(element: ElementPredicate, _ change: AnyPropertyChange? = nil) -> AccessibilityPredicate.Change {
        .elementsScope([.updatedElement(ElementUpdatePredicate(element: element, change: change))])
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

    static func updated() -> ElementDeltaPredicateExpr {
        .updatedElement(ElementUpdatePredicateExpr())
    }

    static func updated(_ change: AnyPropertyChangeExpr) -> ElementDeltaPredicateExpr {
        .updatedElement(ElementUpdatePredicateExpr(change: change))
    }

    static func updated(element: ElementPredicateTemplate, _ change: AnyPropertyChangeExpr? = nil) -> ElementDeltaPredicateExpr {
        .updatedElement(ElementUpdatePredicateExpr(element: element, change: change))
    }
}

public extension ElementDeltaPredicate {
    static func appeared(_ predicate: ElementPredicate) -> ElementDeltaPredicate {
        .appearedElement(predicate)
    }

    static func disappeared(_ predicate: ElementPredicate) -> ElementDeltaPredicate {
        .disappearedElement(predicate)
    }

    static func updated() -> ElementDeltaPredicate {
        .updatedElement(ElementUpdatePredicate())
    }

    static func updated(_ change: AnyPropertyChange) -> ElementDeltaPredicate {
        .updatedElement(ElementUpdatePredicate(change: change))
    }

    static func updated(element: ElementPredicate, _ change: AnyPropertyChange? = nil) -> ElementDeltaPredicate {
        .updatedElement(ElementUpdatePredicate(element: element, change: change))
    }
}

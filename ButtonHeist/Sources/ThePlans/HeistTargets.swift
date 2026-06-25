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

    static func element(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        labelMatches: [StringMatch<String>] = [],
        identifierMatches: [StringMatch<String>] = [],
        valueMatches: [StringMatch<String>] = [],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementTarget {
        .predicate(.element(
            label: label,
            identifier: identifier,
            value: value,
            labelMatches: labelMatches,
            identifierMatches: identifierMatches,
            valueMatches: valueMatches,
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

    static func element(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        labelMatches: [StringMatch<StringExpr>] = [],
        identifierMatches: [StringMatch<StringExpr>] = [],
        valueMatches: [StringMatch<StringExpr>] = [],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementPredicateTemplate {
        ElementPredicateTemplate(
            label: label,
            identifier: identifier,
            value: value,
            labelMatches: labelMatches,
            identifierMatches: identifierMatches,
            valueMatches: valueMatches,
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
    static func present(_ predicate: ElementPredicate) -> AccessibilityPredicate {
        .state(.present(predicate))
    }

    @_disfavoredOverload
    static func present(_ target: ElementTarget) -> AccessibilityPredicate {
        .state(.presentTarget(target))
    }

    static func absent(_ predicate: ElementPredicate) -> AccessibilityPredicate {
        .state(.absent(predicate))
    }

    @_disfavoredOverload
    static func absent(_ target: ElementTarget) -> AccessibilityPredicate {
        .state(.absentTarget(target))
    }

    static func all(_ states: [AccessibilityPredicate.State]) -> AccessibilityPredicate {
        .state(.all(states))
    }
}

public extension AccessibilityPredicateExpr {
    static func present(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .state(.present(predicate))
    }

    @_disfavoredOverload
    static func present(_ target: ElementTargetExpr) -> AccessibilityPredicateExpr {
        .state(.presentTarget(target))
    }

    static func absent(_ predicate: ElementPredicateTemplate) -> AccessibilityPredicateExpr {
        .state(.absent(predicate))
    }

    @_disfavoredOverload
    static func absent(_ target: ElementTargetExpr) -> AccessibilityPredicateExpr {
        .state(.absentTarget(target))
    }

    static func all(_ states: [StatePredicateExpr]) -> AccessibilityPredicateExpr {
        .state(.all(states))
    }
}

public extension StatePredicateExpr {
    @_disfavoredOverload
    static func present(_ target: ElementTargetExpr) -> StatePredicateExpr {
        .presentTarget(target)
    }

    @_disfavoredOverload
    static func absent(_ target: ElementTargetExpr) -> StatePredicateExpr {
        .absentTarget(target)
    }
}

public extension ChangePredicateExpr {
    static func updated(
        _ element: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil,
        from: StringMatch<StringExpr>? = nil,
        to: StringMatch<StringExpr>? = nil
    ) -> ChangePredicateExpr {
        .updated(ElementUpdatePredicateExpr(
            element: element,
            property: property,
            from: from,
            to: to
        ))
    }

    static func updated(
        _ element: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil,
        from: StringExpr,
        to: StringMatch<StringExpr>? = nil
    ) -> ChangePredicateExpr {
        .updated(element, property: property, from: StringMatch(from), to: to)
    }

    static func updated(
        _ element: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil,
        from: StringMatch<StringExpr>? = nil,
        to: StringExpr
    ) -> ChangePredicateExpr {
        .updated(element, property: property, from: from, to: StringMatch(to))
    }

    static func updated(
        _ element: ElementPredicateTemplate? = nil,
        property: ElementProperty? = nil,
        from: StringExpr,
        to: StringExpr
    ) -> ChangePredicateExpr {
        .updated(element, property: property, from: StringMatch(from), to: StringMatch(to))
    }
}

public extension AccessibilityPredicate.Change {
    static func updated(
        _ element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: StringMatch<String>? = nil,
        to: StringMatch<String>? = nil
    ) -> AccessibilityPredicate.Change {
        .updated(ElementUpdatePredicate(
            element: element,
            property: property,
            from: from,
            to: to
        ))
    }

    static func updated(
        _ element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: String,
        to: StringMatch<String>? = nil
    ) -> AccessibilityPredicate.Change {
        .updated(element, property: property, from: StringMatch(from), to: to)
    }

    static func updated(
        _ element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: StringMatch<String>? = nil,
        to: String
    ) -> AccessibilityPredicate.Change {
        .updated(element, property: property, from: from, to: StringMatch(to))
    }

    static func updated(
        _ element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: String,
        to: String
    ) -> AccessibilityPredicate.Change {
        .updated(element, property: property, from: StringMatch(from), to: StringMatch(to))
    }
}

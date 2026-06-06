public extension ElementTarget {
    static func label(_ label: String) -> ElementTarget {
        .predicate(.label(label))
    }

    static func identifier(_ identifier: String) -> ElementTarget {
        .predicate(.identifier(identifier))
    }

    static func value(_ value: String) -> ElementTarget {
        .predicate(.value(value))
    }

    static func element(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
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

    static func target(_ predicate: ElementPredicate, ordinal: Int) -> ElementTarget {
        .predicate(predicate, ordinal: ordinal)
    }
}

public extension ElementPredicateTemplate {
    static func label(_ label: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: label)
    }

    static func label(_ label: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .literal(label))
    }

    static func identifier(_ identifier: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: identifier)
    }

    static func value(_ value: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: value)
    }

    static func element(
        label: StringExpr? = nil,
        identifier: StringExpr? = nil,
        value: StringExpr? = nil,
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
}

public extension ElementTargetExpr {
    static func label(_ label: StringExpr) -> ElementTargetExpr {
        .predicate(.label(label))
    }

    static func identifier(_ identifier: StringExpr) -> ElementTargetExpr {
        .predicate(.identifier(identifier))
    }

    static func value(_ value: StringExpr) -> ElementTargetExpr {
        .predicate(.value(value))
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
        from: StringExpr? = nil,
        to: StringExpr? = nil
    ) -> ChangePredicateExpr {
        .updated(ElementUpdatePredicateExpr(
            element: element,
            property: property,
            from: from,
            to: to
        ))
    }
}

public extension AccessibilityPredicate.Change {
    static func updated(
        _ element: ElementPredicate? = nil,
        property: ElementProperty? = nil,
        from: String? = nil,
        to: String? = nil
    ) -> AccessibilityPredicate.Change {
        .updated(ElementUpdatePredicate(
            element: element,
            property: property,
            from: from,
            to: to
        ))
    }
}

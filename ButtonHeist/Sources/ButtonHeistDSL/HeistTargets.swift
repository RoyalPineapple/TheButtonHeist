import TheScore

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

public extension ElementPredicateExpr {
    static func label(_ label: StringExpr) -> ElementPredicateExpr {
        ElementPredicateExpr(label: label)
    }

    static func label(_ label: String) -> ElementPredicateExpr {
        ElementPredicateExpr(label: .literal(label))
    }

    static func identifier(_ identifier: StringExpr) -> ElementPredicateExpr {
        ElementPredicateExpr(identifier: identifier)
    }

    static func value(_ value: StringExpr) -> ElementPredicateExpr {
        ElementPredicateExpr(value: value)
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
    static func present(_ predicate: ElementPredicateExpr) -> AccessibilityPredicateExpr {
        .state(.present(predicate))
    }

    @_disfavoredOverload
    static func present(_ target: ElementTargetExpr) -> AccessibilityPredicateExpr {
        .state(.presentTarget(target))
    }

    static func absent(_ predicate: ElementPredicateExpr) -> AccessibilityPredicateExpr {
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

public extension ElementTarget {
    static func label(_ label: StringMatch<String>) -> ElementTarget {
        .predicate(.label(label))
    }

    static func label(contains label: String) -> ElementTarget {
        .predicate(.label(contains: label))
    }

    static func label(prefix label: String) -> ElementTarget {
        .predicate(.label(prefix: label))
    }

    static func label(suffix label: String) -> ElementTarget {
        .predicate(.label(suffix: label))
    }

    static func identifier(_ identifier: StringMatch<String>) -> ElementTarget {
        .predicate(.identifier(identifier))
    }

    static func identifier(contains identifier: String) -> ElementTarget {
        .predicate(.identifier(contains: identifier))
    }

    static func identifier(prefix identifier: String) -> ElementTarget {
        .predicate(.identifier(prefix: identifier))
    }

    static func identifier(suffix identifier: String) -> ElementTarget {
        .predicate(.identifier(suffix: identifier))
    }

    static func value(_ value: StringMatch<String>) -> ElementTarget {
        .predicate(.value(value))
    }

    static func value(contains value: String) -> ElementTarget {
        .predicate(.value(contains: value))
    }

    static func value(prefix value: String) -> ElementTarget {
        .predicate(.value(prefix: value))
    }

    static func value(suffix value: String) -> ElementTarget {
        .predicate(.value(suffix: value))
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

    static func target(_ predicate: ElementPredicate, ordinal: Int) -> ElementTarget {
        .predicate(predicate, ordinal: ordinal)
    }
}

public extension ElementPredicateTemplate {
    static func label(_ label: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .exact(label))
    }

    static func label(_ label: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .exact(.literal(label)))
    }

    static func label(contains label: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .contains(.literal(label)))
    }

    static func label(prefix label: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .prefix(.literal(label)))
    }

    static func label(suffix label: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(label: .suffix(.literal(label)))
    }

    static func identifier(_ identifier: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: .exact(identifier))
    }

    static func identifier(_ identifier: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: .exact(.literal(identifier)))
    }

    static func identifier(contains identifier: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: .contains(.literal(identifier)))
    }

    static func identifier(prefix identifier: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: .prefix(.literal(identifier)))
    }

    static func identifier(suffix identifier: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(identifier: .suffix(.literal(identifier)))
    }

    static func value(_ value: StringExpr) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: .exact(value))
    }

    static func value(_ value: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: .exact(.literal(value)))
    }

    static func value(contains value: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: .contains(.literal(value)))
    }

    static func value(prefix value: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: .prefix(.literal(value)))
    }

    static func value(suffix value: String) -> ElementPredicateTemplate {
        ElementPredicateTemplate(value: .suffix(.literal(value)))
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
}

public extension ElementTargetExpr {
    static func label(_ label: StringExpr) -> ElementTargetExpr {
        .predicate(.label(label))
    }

    static func label(_ label: String) -> ElementTargetExpr {
        .predicate(.label(label))
    }

    static func label(contains label: String) -> ElementTargetExpr {
        .predicate(.label(contains: label))
    }

    static func label(prefix label: String) -> ElementTargetExpr {
        .predicate(.label(prefix: label))
    }

    static func label(suffix label: String) -> ElementTargetExpr {
        .predicate(.label(suffix: label))
    }

    static func identifier(_ identifier: StringExpr) -> ElementTargetExpr {
        .predicate(.identifier(identifier))
    }

    static func identifier(_ identifier: String) -> ElementTargetExpr {
        .predicate(.identifier(identifier))
    }

    static func identifier(contains identifier: String) -> ElementTargetExpr {
        .predicate(.identifier(contains: identifier))
    }

    static func identifier(prefix identifier: String) -> ElementTargetExpr {
        .predicate(.identifier(prefix: identifier))
    }

    static func identifier(suffix identifier: String) -> ElementTargetExpr {
        .predicate(.identifier(suffix: identifier))
    }

    static func value(_ value: StringExpr) -> ElementTargetExpr {
        .predicate(.value(value))
    }

    static func value(_ value: String) -> ElementTargetExpr {
        .predicate(.value(value))
    }

    static func value(contains value: String) -> ElementTargetExpr {
        .predicate(.value(contains: value))
    }

    static func value(prefix value: String) -> ElementTargetExpr {
        .predicate(.value(prefix: value))
    }

    static func value(suffix value: String) -> ElementTargetExpr {
        .predicate(.value(suffix: value))
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

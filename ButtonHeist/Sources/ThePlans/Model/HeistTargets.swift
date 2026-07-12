public extension ElementPredicateTemplate {
    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> Self {
        Self(label: label)
    }

    static func label(_ label: StringExpr) -> Self {
        Self(label: StringMatch(label))
    }

    static func label(_ label: String) -> Self {
        .label(.literal(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> Self {
        Self(identifier: identifier)
    }

    static func identifier(_ identifier: StringExpr) -> Self {
        Self(identifier: StringMatch(identifier))
    }

    static func identifier(_ identifier: String) -> Self {
        .identifier(.literal(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> Self {
        Self(value: value)
    }

    static func value(_ value: StringExpr) -> Self {
        Self(value: StringMatch(value))
    }

    static func value(_ value: String) -> Self {
        .value(.literal(value))
    }

    @_disfavoredOverload
    static func hint(_ hint: StringMatch<StringExpr>) -> Self {
        Self(hint: hint)
    }

    static func hint(_ hint: StringExpr) -> Self {
        Self(hint: StringMatch(hint))
    }

    static func hint(_ hint: String) -> Self {
        .hint(.literal(hint))
    }

    static func traits(_ traits: [HeistTrait]) -> Self {
        Self(traits: traits)
    }

    static func actions(_ actions: [ElementAction]) -> Self {
        Self(actions: actions)
    }

    static func customContent(_ match: CustomContentMatch<StringExpr>) -> Self {
        Self(customContent: match)
    }

    static func rotors(_ rotors: [StringMatch<StringExpr>]) -> Self {
        Self(rotors: rotors)
    }

    static func exclude(_ check: ElementPredicateCheck<StringExpr>) -> Self {
        Self([.exclude(check)])
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> Self {
        Self(checks, traits: traits, actions: actions)
    }
}

public extension AccessibilityTarget {
    @_disfavoredOverload
    static func label(_ label: StringMatch<StringExpr>) -> Self {
        .predicate(.label(label))
    }

    static func label(_ label: StringExpr) -> Self {
        .predicate(.label(label))
    }

    static func label(_ label: String) -> Self {
        .predicate(.label(label))
    }

    @_disfavoredOverload
    static func identifier(_ identifier: StringMatch<StringExpr>) -> Self {
        .predicate(.identifier(identifier))
    }

    static func identifier(_ identifier: StringExpr) -> Self {
        .predicate(.identifier(identifier))
    }

    static func identifier(_ identifier: String) -> Self {
        .predicate(.identifier(identifier))
    }

    @_disfavoredOverload
    static func value(_ value: StringMatch<StringExpr>) -> Self {
        .predicate(.value(value))
    }

    static func value(_ value: StringExpr) -> Self {
        .predicate(.value(value))
    }

    static func value(_ value: String) -> Self {
        .predicate(.value(value))
    }

    @_disfavoredOverload
    static func hint(_ hint: StringMatch<StringExpr>) -> Self {
        .predicate(.hint(hint))
    }

    static func hint(_ hint: StringExpr) -> Self {
        .predicate(.hint(hint))
    }

    static func hint(_ hint: String) -> Self {
        .predicate(.hint(hint))
    }

    static func traits(_ traits: [HeistTrait]) -> Self {
        .predicate(.traits(traits))
    }

    static func actions(_ actions: [ElementAction]) -> Self {
        .predicate(.actions(actions))
    }

    static func customContent(_ match: CustomContentMatch<StringExpr>) -> Self {
        .predicate(.customContent(match))
    }

    static func rotors(_ rotors: [StringMatch<StringExpr>]) -> Self {
        .predicate(.rotors(rotors))
    }

    static func exclude(_ check: ElementPredicateCheck<StringExpr>) -> Self {
        .predicate(.exclude(check))
    }

    static func element(
        _ checks: ElementPredicateCheck<StringExpr>...,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> Self {
        .predicate(ElementPredicateTemplate(checks, traits: traits, actions: actions))
    }

    static func target(_ predicate: ElementPredicateTemplate, ordinal: Int) -> Self {
        .predicate(predicate, ordinal: ordinal)
    }

    static func within(container: ContainerPredicateExpr, _ target: Self) -> Self {
        .within(container: container, target: target)
    }
}

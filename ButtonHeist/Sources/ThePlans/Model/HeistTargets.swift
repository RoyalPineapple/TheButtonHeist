public extension ElementPredicate {
    @_disfavoredOverload
    static func label(_ match: StringMatch) -> Self { Self(label: match) }
    static func label(_ label: String) -> Self { Self(label: .exact(label)) }
    @_disfavoredOverload
    static func label(_ reference: HeistReferenceName) -> Self { Self(label: .exact(reference)) }

    @_disfavoredOverload
    static func identifier(_ match: StringMatch) -> Self { Self(identifier: match) }
    static func identifier(_ identifier: String) -> Self { Self(identifier: .exact(identifier)) }
    @_disfavoredOverload
    static func identifier(_ reference: HeistReferenceName) -> Self { Self(identifier: .exact(reference)) }

    @_disfavoredOverload
    static func value(_ match: StringMatch) -> Self { Self(value: match) }
    static func value(_ value: String) -> Self { Self(value: .exact(value)) }
    @_disfavoredOverload
    static func value(_ reference: HeistReferenceName) -> Self { Self(value: .exact(reference)) }

    @_disfavoredOverload
    static func hint(_ match: StringMatch) -> Self { Self(hint: match) }
    static func hint(_ hint: String) -> Self { Self(hint: .exact(hint)) }
    @_disfavoredOverload
    static func hint(_ reference: HeistReferenceName) -> Self { Self(hint: .exact(reference)) }

    static func traits(_ traits: [HeistTrait]) -> Self { Self(traits: traits) }
    static func actions(_ actions: [ElementAction]) -> Self { Self(actions: actions) }
    static func customContent(_ match: CustomContentMatch) -> Self { Self(customContent: match) }
    static func rotors(_ rotors: [StringMatch]) -> Self { Self(rotors: rotors) }
    static func exclude(_ check: ElementPredicateCheck) -> Self { Self([.exclude(check)]) }

    static func element(
        _ checks: ElementPredicateCheck...,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> Self {
        Self(checks, traits: traits, actions: actions)
    }
}

public extension AccessibilityTarget {
    @_disfavoredOverload
    static func label(_ match: StringMatch) -> Self { .predicate(.label(match)) }
    static func label(_ label: String) -> Self { .predicate(.label(label)) }
    @_disfavoredOverload
    static func label(_ reference: HeistReferenceName) -> Self { .predicate(.label(reference)) }

    @_disfavoredOverload
    static func identifier(_ match: StringMatch) -> Self { .predicate(.identifier(match)) }
    static func identifier(_ identifier: String) -> Self { .predicate(.identifier(identifier)) }
    @_disfavoredOverload
    static func identifier(_ reference: HeistReferenceName) -> Self { .predicate(.identifier(reference)) }

    @_disfavoredOverload
    static func value(_ match: StringMatch) -> Self { .predicate(.value(match)) }
    static func value(_ value: String) -> Self { .predicate(.value(value)) }
    @_disfavoredOverload
    static func value(_ reference: HeistReferenceName) -> Self { .predicate(.value(reference)) }

    @_disfavoredOverload
    static func hint(_ match: StringMatch) -> Self { .predicate(.hint(match)) }
    static func hint(_ hint: String) -> Self { .predicate(.hint(hint)) }
    @_disfavoredOverload
    static func hint(_ reference: HeistReferenceName) -> Self { .predicate(.hint(reference)) }

    static func traits(_ traits: [HeistTrait]) -> Self { .predicate(.traits(traits)) }
    static func actions(_ actions: [ElementAction]) -> Self { .predicate(.actions(actions)) }
    static func customContent(_ match: CustomContentMatch) -> Self { .predicate(.customContent(match)) }
    static func rotors(_ rotors: [StringMatch]) -> Self { .predicate(.rotors(rotors)) }
    static func exclude(_ check: ElementPredicateCheck) -> Self { .predicate(.exclude(check)) }

    static func element(
        _ checks: ElementPredicateCheck...,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) -> Self {
        .predicate(ElementPredicate(checks, traits: traits, actions: actions))
    }

    static func target(_ predicate: ElementPredicate, ordinal: Int) -> Self {
        .predicate(predicate, ordinal: ordinal)
    }

    static func within(container: ContainerPredicate, _ target: Self) -> Self {
        .within(container: container, target: target)
    }
}

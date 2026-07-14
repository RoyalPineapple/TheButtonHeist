package enum ElementPropertyChangeCore<Text> {
    case value(PropertyChangeCore<StringMatchCore<Text>>)
    case traits(PropertyChangeCore<TraitSetMatch>)
    case hint(PropertyChangeCore<StringMatchCore<Text>>)
    case actions(PropertyChangeCore<ActionSetMatch>)
    case frame(PropertyChangeCore<ElementFrameMatch>)
    case activationPoint(PropertyChangeCore<ElementPointMatch>)
    case customContent(PropertyChangeCore<CustomContentMatchCore<Text>>)
    case rotors(PropertyChangeCore<RotorSetMatchCore<Text>>)

    package var property: ElementProperty {
        switch self {
        case .value: return .value
        case .traits: return .traits
        case .hint: return .hint
        case .actions: return .actions
        case .frame: return .frame
        case .activationPoint: return .activationPoint
        case .customContent: return .customContent
        case .rotors: return .rotors
        }
    }
}

extension ElementPropertyChangeCore: Sendable where Text: Sendable {}
extension ElementPropertyChangeCore: Equatable where Text: Equatable {}

package extension ElementPropertyChangeCore where Text == Expr<String> {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPropertyChangeCore<String> {
        switch self {
        case .value(let change):
            return try .value(change.map { try resolve($0, in: environment) })
        case .traits(let change):
            return .traits(change)
        case .hint(let change):
            return try .hint(change.map { try resolve($0, in: environment) })
        case .actions(let change):
            return .actions(change)
        case .frame(let change):
            return .frame(change)
        case .activationPoint(let change):
            return .activationPoint(change)
        case .customContent(let change):
            return try .customContent(change.map { try $0.map { try $0.resolve(in: environment) } })
        case .rotors(let change):
            return try .rotors(change.map { try $0.map { try $0.resolve(in: environment) } })
        }
    }

    private func resolve(
        _ match: StringMatchCore<Expr<String>>,
        in environment: HeistExecutionEnvironment
    ) throws -> StringMatchCore<String> {
        let resolved = try match.map { try $0.resolve(in: environment) }
        if resolved.hasInvalidEmptyBroadLiteral {
            throw HeistExpressionError.invalidStringMatch(mode: resolved.mode.rawValue)
        }
        return resolved
    }
}

public extension ElementPropertyChange {
    static func value(
        before: StringMatch? = nil,
        after: StringMatch? = nil
    ) -> Self {
        Self(core: .value(PropertyChangeCore(before: before?.core, after: after?.core)))
    }

    @_disfavoredOverload
    static func value(_ after: StringMatch) -> Self {
        .value(after: after)
    }

    static func value(_ after: String) -> Self {
        .value(after: .exact(after))
    }

    static func value(reference: HeistReferenceName) -> Self {
        .value(after: .exact(reference))
    }

    static func traits(
        before: TraitSetMatch? = nil,
        after: TraitSetMatch? = nil
    ) -> Self {
        Self(core: .traits(PropertyChangeCore(before: before, after: after)))
    }

    static func hint(
        before: StringMatch? = nil,
        after: StringMatch? = nil
    ) -> Self {
        Self(core: .hint(PropertyChangeCore(before: before?.core, after: after?.core)))
    }

    static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        Self(core: .actions(PropertyChangeCore(before: before, after: after)))
    }

    static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        Self(core: .frame(PropertyChangeCore(before: before, after: after)))
    }

    static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        Self(core: .activationPoint(PropertyChangeCore(before: before, after: after)))
    }

    static func customContent(
        before: CustomContentMatch? = nil,
        after: CustomContentMatch? = nil
    ) -> Self {
        Self(core: .customContent(PropertyChangeCore(before: before?.core, after: after?.core)))
    }

    static func rotors(
        before: RotorSetMatch? = nil,
        after: RotorSetMatch? = nil
    ) -> Self {
        Self(core: .rotors(PropertyChangeCore(before: before?.core, after: after?.core)))
    }
}

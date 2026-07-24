package enum AuthoredElementPropertyChange: Sendable, Equatable {
    case value(PropertyChangeCore<StringMatch>)
    case traits(PropertyChangeCore<TraitSetMatch>)
    case hint(PropertyChangeCore<StringMatch>)
    case actions(PropertyChangeCore<ActionSetMatch>)
    case frame(PropertyChangeCore<ElementFrameMatch>)
    case activationPoint(PropertyChangeCore<ElementPointMatch>)
    case customContent(PropertyChangeCore<CustomContentMatch>)
    case rotors(PropertyChangeCore<RotorSetMatch>)

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

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPropertyChangeValue {
        switch self {
        case .value(let change):
            return .value(try change.map { try $0.resolve(in: environment) })
        case .traits(let change):
            return .traits(change)
        case .hint(let change):
            return .hint(try change.map { try $0.resolve(in: environment) })
        case .actions(let change):
            return .actions(change)
        case .frame(let change):
            return .frame(change)
        case .activationPoint(let change):
            return .activationPoint(change)
        case .customContent(let change):
            return .customContent(try change.map { try $0.resolve(in: environment) })
        case .rotors(let change):
            return .rotors(try change.map { try $0.resolve(in: environment) })
        }
    }
}

package enum ResolvedElementPropertyChangeValue: Sendable, Equatable {
    case value(PropertyChangeCore<ResolvedStringMatch>)
    case traits(PropertyChangeCore<TraitSetMatch>)
    case hint(PropertyChangeCore<ResolvedStringMatch>)
    case actions(PropertyChangeCore<ActionSetMatch>)
    case frame(PropertyChangeCore<ElementFrameMatch>)
    case activationPoint(PropertyChangeCore<ElementPointMatch>)
    case customContent(PropertyChangeCore<ResolvedCustomContentMatch>)
    case rotors(PropertyChangeCore<ResolvedRotorSetMatch>)

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

public extension ElementPropertyChange {
    static func value(
        before: StringMatch? = nil,
        after: StringMatch? = nil
    ) -> Self {
        Self(value: .value(PropertyChangeCore(before: before, after: after)))
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
        Self(value: .traits(PropertyChangeCore(before: before, after: after)))
    }

    static func hint(
        before: StringMatch? = nil,
        after: StringMatch? = nil
    ) -> Self {
        Self(value: .hint(PropertyChangeCore(before: before, after: after)))
    }

    static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        Self(value: .actions(PropertyChangeCore(before: before, after: after)))
    }

    static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        Self(value: .frame(PropertyChangeCore(before: before, after: after)))
    }

    static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        Self(value: .activationPoint(PropertyChangeCore(before: before, after: after)))
    }

    static func customContent(
        before: CustomContentMatch? = nil,
        after: CustomContentMatch? = nil
    ) -> Self {
        Self(value: .customContent(PropertyChangeCore(before: before, after: after)))
    }

    static func rotors(
        before: RotorSetMatch? = nil,
        after: RotorSetMatch? = nil
    ) -> Self {
        Self(value: .rotors(PropertyChangeCore(before: before, after: after)))
    }
}

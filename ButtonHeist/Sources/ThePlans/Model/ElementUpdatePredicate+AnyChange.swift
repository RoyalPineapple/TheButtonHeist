// MARK: - Erased Element Property Changes

public enum AnyPropertyChange: Sendable, Equatable {
    case value(ElementPropertyChange<ValueProperty>)
    case traits(ElementPropertyChange<TraitsProperty>)
    case hint(ElementPropertyChange<HintProperty>)
    case actions(ElementPropertyChange<ActionsProperty>)
    case frame(ElementPropertyChange<FrameProperty>)
    case activationPoint(ElementPropertyChange<ActivationPointProperty>)
    case customContent(ElementPropertyChange<CustomContentProperty>)
    case rotors(ElementPropertyChange<RotorsProperty>)

    public var property: ElementProperty {
        switch self {
        case .value: return ValueProperty.property
        case .traits: return TraitsProperty.property
        case .hint: return HintProperty.property
        case .actions: return ActionsProperty.property
        case .frame: return FrameProperty.property
        case .activationPoint: return ActivationPointProperty.property
        case .customContent: return CustomContentProperty.property
        case .rotors: return RotorsProperty.property
        }
    }

    public static func value(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .value(ElementPropertyChange(before: before, after: after))
    }

    @_disfavoredOverload
    public static func value(_ after: StringMatch<String>) -> Self {
        .value(after: after)
    }

    public static func value(_ after: String) -> Self {
        .value(after: .exact(after))
    }

    public static func traits(
        before: TraitSetMatch? = nil,
        after: TraitSetMatch? = nil
    ) -> Self {
        .traits(ElementPropertyChange(before: before, after: after))
    }

    public static func hint(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .hint(ElementPropertyChange(before: before, after: after))
    }

    public static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        .actions(ElementPropertyChange(before: before, after: after))
    }

    public static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        .frame(ElementPropertyChange(before: before, after: after))
    }

    public static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChange(before: before, after: after))
    }

    public static func customContent(
        before: CustomContentMatch<String>? = nil,
        after: CustomContentMatch<String>? = nil
    ) -> Self {
        .customContent(ElementPropertyChange(before: before, after: after))
    }

    public static func rotors(
        before: RotorSetMatch<String>? = nil,
        after: RotorSetMatch<String>? = nil
    ) -> Self {
        .rotors(ElementPropertyChange(before: before, after: after))
    }
}

public enum AnyPropertyChangeExpr: Sendable, Equatable {
    case value(ElementPropertyChangeExpr<ValueProperty>)
    case traits(ElementPropertyChangeExpr<TraitsProperty>)
    case hint(ElementPropertyChangeExpr<HintProperty>)
    case actions(ElementPropertyChangeExpr<ActionsProperty>)
    case frame(ElementPropertyChangeExpr<FrameProperty>)
    case activationPoint(ElementPropertyChangeExpr<ActivationPointProperty>)
    case customContent(ElementPropertyChangeExpr<CustomContentProperty>)
    case rotors(ElementPropertyChangeExpr<RotorsProperty>)

    public var property: ElementProperty {
        switch self {
        case .value: return ValueProperty.property
        case .traits: return TraitsProperty.property
        case .hint: return HintProperty.property
        case .actions: return ActionsProperty.property
        case .frame: return FrameProperty.property
        case .activationPoint: return ActivationPointProperty.property
        case .customContent: return CustomContentProperty.property
        case .rotors: return RotorsProperty.property
        }
    }

    public init(_ change: AnyPropertyChange) {
        switch change {
        case .value(let change):
            self = .value(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        case .traits(let change):
            self = .traits(ElementPropertyChangeExpr(before: change.before, after: change.after))
        case .hint(let change):
            self = .hint(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        case .actions(let change):
            self = .actions(ElementPropertyChangeExpr(before: change.before, after: change.after))
        case .frame(let change):
            self = .frame(ElementPropertyChangeExpr(before: change.before, after: change.after))
        case .activationPoint(let change):
            self = .activationPoint(ElementPropertyChangeExpr(before: change.before, after: change.after))
        case .customContent(let change):
            self = .customContent(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        case .rotors(let change):
            self = .rotors(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> AnyPropertyChange {
        switch self {
        case .value(let change):
            return .value(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        case .traits(let change):
            return .traits(ElementPropertyChange(before: change.before, after: change.after))
        case .hint(let change):
            return .hint(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        case .actions(let change):
            return .actions(ElementPropertyChange(before: change.before, after: change.after))
        case .frame(let change):
            return .frame(ElementPropertyChange(before: change.before, after: change.after))
        case .activationPoint(let change):
            return .activationPoint(ElementPropertyChange(before: change.before, after: change.after))
        case .customContent(let change):
            return .customContent(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        case .rotors(let change):
            return .rotors(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        }
    }

    public static func value(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .value(ElementPropertyChangeExpr(before: before, after: after))
    }

    @_disfavoredOverload
    public static func value(_ after: StringMatch<StringExpr>) -> Self {
        .value(after: after)
    }

    public static func value(_ after: StringExpr) -> Self {
        .value(after: .exact(after))
    }

    public static func value(_ after: String) -> Self {
        .value(.literal(after))
    }

    public static func traits(
        before: TraitSetMatch? = nil,
        after: TraitSetMatch? = nil
    ) -> Self {
        .traits(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func hint(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .hint(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        .actions(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        .frame(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func customContent(
        before: CustomContentMatch<StringExpr>? = nil,
        after: CustomContentMatch<StringExpr>? = nil
    ) -> Self {
        .customContent(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func rotors(
        before: RotorSetMatch<StringExpr>? = nil,
        after: RotorSetMatch<StringExpr>? = nil
    ) -> Self {
        .rotors(ElementPropertyChangeExpr(before: before, after: after))
    }
}

fileprivate extension CustomContentMatch where Value == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> CustomContentMatch<String> {
        try map { try $0.resolve(in: environment) }
    }
}

fileprivate extension RotorSetMatch where Value == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> RotorSetMatch<String> {
        try map { try $0.resolve(in: environment) }
    }
}

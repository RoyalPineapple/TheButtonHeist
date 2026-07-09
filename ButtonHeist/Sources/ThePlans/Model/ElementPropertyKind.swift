// MARK: - Element Property Kinds

/// One accessibility property and the checker types used to match that
/// property's before/after values.
public protocol ElementPropertyKind: Sendable {
    associatedtype Checker: Codable, Sendable, Equatable
    associatedtype ExprChecker: Codable, Sendable, Equatable

    static var property: ElementProperty { get }
}

public enum ValueProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property: ElementProperty = .value
}

public enum LabelProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property: ElementProperty = .label
}

public enum IdentifierProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property: ElementProperty = .identifier
}

public enum TraitsProperty: ElementPropertyKind {
    public typealias Checker = TraitSetMatch
    public typealias ExprChecker = TraitSetMatch
    public static let property: ElementProperty = .traits
}

public enum HintProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property: ElementProperty = .hint
}

public enum ActionsProperty: ElementPropertyKind {
    public typealias Checker = ActionSetMatch
    public typealias ExprChecker = ActionSetMatch
    public static let property: ElementProperty = .actions
}

public enum FrameProperty: ElementPropertyKind {
    public typealias Checker = ElementFrameMatch
    public typealias ExprChecker = ElementFrameMatch
    public static let property: ElementProperty = .frame
}

public enum ActivationPointProperty: ElementPropertyKind {
    public typealias Checker = ElementPointMatch
    public typealias ExprChecker = ElementPointMatch
    public static let property: ElementProperty = .activationPoint
}

public enum CustomContentProperty: ElementPropertyKind {
    public typealias Checker = CustomContentMatch<String>
    public typealias ExprChecker = CustomContentMatch<StringExpr>
    public static let property: ElementProperty = .customContent
}

public enum RotorsProperty: ElementPropertyKind {
    public typealias Checker = RotorSetMatch<String>
    public typealias ExprChecker = RotorSetMatch<StringExpr>
    public static let property: ElementProperty = .rotors
}

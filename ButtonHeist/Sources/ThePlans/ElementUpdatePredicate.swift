import Foundation

// MARK: - Element Property Change Predicates

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
    public static let property = ElementProperty.value
}

public enum LabelProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.label
}

public enum IdentifierProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.identifier
}

public enum TraitsProperty: ElementPropertyKind {
    public typealias Checker = TraitSetMatch
    public typealias ExprChecker = TraitSetMatch
    public static let property = ElementProperty.traits
}

public enum HintProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.hint
}

public enum ActionsProperty: ElementPropertyKind {
    public typealias Checker = ActionSetMatch
    public typealias ExprChecker = ActionSetMatch
    public static let property = ElementProperty.actions
}

public enum FrameProperty: ElementPropertyKind {
    public typealias Checker = ElementFrameMatch
    public typealias ExprChecker = ElementFrameMatch
    public static let property = ElementProperty.frame
}

public enum ActivationPointProperty: ElementPropertyKind {
    public typealias Checker = ElementPointMatch
    public typealias ExprChecker = ElementPointMatch
    public static let property = ElementProperty.activationPoint
}

public enum CustomContentProperty: ElementPropertyKind {
    public typealias Checker = CustomContentMatch<String>
    public typealias ExprChecker = CustomContentMatch<StringExpr>
    public static let property = ElementProperty.customContent
}

public enum RotorsProperty: ElementPropertyKind {
    public typealias Checker = RotorSetMatch<String>
    public typealias ExprChecker = RotorSetMatch<StringExpr>
    public static let property = ElementProperty.rotors
}

/// Required and forbidden traits in a property's trait set.
public struct TraitSetMatch: Sendable, Equatable {
    public let include: Set<HeistTrait>
    public let exclude: Set<HeistTrait>

    public init(include: [HeistTrait] = [], exclude: [HeistTrait] = []) {
        self.include = include.heistTraitSet
        self.exclude = exclude.heistTraitSet
    }

    public static func include(_ traits: [HeistTrait]) -> Self {
        Self(include: traits)
    }

    public static func exclude(_ traits: [HeistTrait]) -> Self {
        Self(exclude: traits)
    }

    public static func match(include: [HeistTrait] = [], exclude: [HeistTrait] = []) -> Self {
        Self(include: include, exclude: exclude)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }
}

extension TraitSetMatch: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "trait set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([HeistTrait].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([HeistTrait].self, forKey: .exclude) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include.canonicalHeistTraitArray, forKey: .include)
        try container.encode(exclude.canonicalHeistTraitArray, forKey: .exclude)
    }
}

extension TraitSetMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("traits", [
            include.isEmpty ? nil : "include=[\(include.canonicalHeistTraitArray.map { ".\($0.rawValue)" }.joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.canonicalHeistTraitArray.map { ".\($0.rawValue)" }.joined(separator: ", "))]",
        ].compactMap { $0 })
    }
}

/// Required and forbidden actions in an element's action list.
public struct ActionSetMatch: Codable, Sendable, Equatable {
    public let include: Set<ElementAction>
    public let exclude: Set<ElementAction>

    public init(include: Set<ElementAction> = [], exclude: Set<ElementAction> = []) {
        self.include = include
        self.exclude = exclude
    }

    public static func include(_ actions: Set<ElementAction>) -> Self {
        Self(include: actions)
    }

    public static func exclude(_ actions: Set<ElementAction>) -> Self {
        Self(exclude: actions)
    }

    public static func match(include: Set<ElementAction> = [], exclude: Set<ElementAction> = []) -> Self {
        Self(include: include, exclude: exclude)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: Set(try container.decodeIfPresent([ElementAction].self, forKey: .include) ?? []),
            exclude: Set(try container.decodeIfPresent([ElementAction].self, forKey: .exclude) ?? [])
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include.canonicalElementActionArray, forKey: .include)
        try container.encode(exclude.canonicalElementActionArray, forKey: .exclude)
    }
}

extension ActionSetMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("actions", [
            include.isEmpty ? nil : "include=[\(include.canonicalElementActionArray.map(\.description).joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.canonicalElementActionArray.map(\.description).joined(separator: ", "))]",
        ].compactMap { $0 })
    }
}

/// Integer geometry checker for a captured accessibility frame.
public struct ElementFrameMatch: Codable, Sendable, Equatable {
    public let x: Int?
    public let y: Int?
    public let width: Int?
    public let height: Int?

    public init(x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func exact(x: Int, y: Int, width: Int, height: Int) -> Self {
        Self(x: x, y: y, width: width, height: height)
    }

    public static func match(x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) -> Self {
        Self(x: x, y: y, width: width, height: height)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, width, height
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "frame match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Int.self, forKey: .x),
            y: try container.decodeIfPresent(Int.self, forKey: .y),
            width: try container.decodeIfPresent(Int.self, forKey: .width),
            height: try container.decodeIfPresent(Int.self, forKey: .height)
        )
    }

}

extension ElementFrameMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("frame", [
            x.map { "x=\($0)" },
            y.map { "y=\($0)" },
            width.map { "width=\($0)" },
            height.map { "height=\($0)" },
        ].compactMap { $0 })
    }
}

/// Integer geometry checker for a captured accessibility activation point.
public struct ElementPointMatch: Codable, Sendable, Equatable {
    public let x: Int?
    public let y: Int?

    public init(x: Int? = nil, y: Int? = nil) {
        self.x = x
        self.y = y
    }

    public static func exact(x: Int, y: Int) -> Self {
        Self(x: x, y: y)
    }

    public static func match(x: Int? = nil, y: Int? = nil) -> Self {
        Self(x: x, y: y)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "activation point match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decodeIfPresent(Int.self, forKey: .x),
            y: try container.decodeIfPresent(Int.self, forKey: .y)
        )
    }

}

extension ElementPointMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("activationPoint", [
            x.map { "x=\($0)" },
            y.map { "y=\($0)" },
        ].compactMap { $0 })
    }
}

/// Field-level checker for one custom-content item in the element's custom content list.
public struct CustomContentMatch<Value: StringMatchPayload>: Sendable, Equatable where Value: Codable {
    public let label: StringMatch<Value>?
    public let value: StringMatch<Value>?
    public let isImportant: Bool?

    public init(
        label: StringMatch<Value>? = nil,
        value: StringMatch<Value>? = nil,
        isImportant: Bool? = nil
    ) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    public static func match(
        label: StringMatch<Value>? = nil,
        value: StringMatch<Value>? = nil,
        isImportant: Bool? = nil
    ) -> Self {
        Self(label: label, value: value, isImportant: isImportant)
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> CustomContentMatch<NewValue> where NewValue: Codable {
        try CustomContentMatch<NewValue>(
            label: label?.map(transform),
            value: value?.map(transform),
            isImportant: isImportant
        )
    }
}

extension CustomContentMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, value, isImportant
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "custom content match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(StringMatch<Value>.self, forKey: .label),
            value: try container.decodeIfPresent(StringMatch<Value>.self, forKey: .value),
            isImportant: try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(isImportant, forKey: .isImportant)
    }
}

extension CustomContentMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("customContent", [
            label.map { "label=\($0)" },
            value.map { "value=\($0)" },
            isImportant.map { "isImportant=\($0)" },
        ].compactMap { $0 })
    }
}

/// Required and forbidden rotor names in an element's rotor list.
public struct RotorSetMatch<Value: StringMatchPayload>: Sendable, Equatable where Value: Codable {
    public let include: [StringMatch<Value>]
    public let exclude: [StringMatch<Value>]

    public init(include: [StringMatch<Value>] = [], exclude: [StringMatch<Value>] = []) {
        self.include = include
        self.exclude = exclude
    }

    public static func include(_ names: [StringMatch<Value>]) -> Self {
        Self(include: names)
    }

    public static func exclude(_ names: [StringMatch<Value>]) -> Self {
        Self(exclude: names)
    }

    public static func match(include: [StringMatch<Value>] = [], exclude: [StringMatch<Value>] = []) -> Self {
        Self(include: include, exclude: exclude)
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> RotorSetMatch<NewValue> where NewValue: Codable {
        try RotorSetMatch<NewValue>(
            include: include.map { try $0.map(transform) },
            exclude: exclude.map { try $0.map(transform) }
        )
    }
}

public extension RotorSetMatch where Value == String {
    static func include(_ names: [String]) -> Self {
        include(names.map { StringMatch<String>.exact($0) })
    }

    static func exclude(_ names: [String]) -> Self {
        exclude(names.map { StringMatch<String>.exact($0) })
    }
}

public extension RotorSetMatch where Value == StringExpr {
    static func include(_ names: [String]) -> Self {
        include(names.map { StringMatch<StringExpr>.exact(.literal($0)) })
    }

    static func exclude(_ names: [String]) -> Self {
        exclude(names.map { StringMatch<StringExpr>.exact(.literal($0)) })
    }
}

extension RotorSetMatch: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case include, exclude
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "rotor set match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            include: try container.decodeIfPresent([StringMatch<Value>].self, forKey: .include) ?? [],
            exclude: try container.decodeIfPresent([StringMatch<Value>].self, forKey: .exclude) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(include, forKey: .include)
        try container.encode(exclude, forKey: .exclude)
    }
}

extension RotorSetMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("rotors", [
            include.isEmpty ? nil : "include=[\(include.map(\.description).joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.map(\.description).joined(separator: ", "))]",
        ].compactMap { $0 })
    }
}

private extension CustomContentMatch where Value == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> CustomContentMatch<String> {
        try map { try $0.resolve(in: environment) }
    }
}

private extension RotorSetMatch where Value == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> RotorSetMatch<String> {
        try map { try $0.resolve(in: environment) }
    }
}

/// A before/after predicate for one property. The generic property kind locks
/// both sides to the same checker type and derives the wire property name.
public struct ElementPropertyChange<P: ElementPropertyKind>: Codable, Sendable, Equatable {
    public let before: P.Checker?
    public let after: P.Checker?
    public var property: ElementProperty { P.property }

    public init(before: P.Checker? = nil, after: P.Checker? = nil) {
        self.before = before
        self.after = after
    }
}

/// Source-time variant of `ElementPropertyChange`, preserving string refs until
/// a heist executes.
public struct ElementPropertyChangeExpr<P: ElementPropertyKind>: Codable, Sendable, Equatable {
    public let before: P.ExprChecker?
    public let after: P.ExprChecker?
    public var property: ElementProperty { P.property }

    public init(before: P.ExprChecker? = nil, after: P.ExprChecker? = nil) {
        self.before = before
        self.after = after
    }
}

public enum AnyPropertyChange: Codable, Sendable, Equatable {
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

    public static func value(
        from: StringMatch<String>? = nil,
        to: StringMatch<String>
    ) -> Self {
        .value(before: from, after: to)
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

    public static func traits(
        from: TraitSetMatch? = nil,
        to: TraitSetMatch
    ) -> Self {
        .traits(before: from, after: to)
    }

    public static func hint(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .hint(ElementPropertyChange(before: before, after: after))
    }

    public static func hint(
        from: StringMatch<String>? = nil,
        to: StringMatch<String>
    ) -> Self {
        .hint(before: from, after: to)
    }

    public static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        .actions(ElementPropertyChange(before: before, after: after))
    }

    public static func actions(
        from: ActionSetMatch? = nil,
        to: ActionSetMatch
    ) -> Self {
        .actions(before: from, after: to)
    }

    public static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        .frame(ElementPropertyChange(before: before, after: after))
    }

    public static func frame(
        from: ElementFrameMatch? = nil,
        to: ElementFrameMatch
    ) -> Self {
        .frame(before: from, after: to)
    }

    public static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChange(before: before, after: after))
    }

    public static func activationPoint(
        from: ElementPointMatch? = nil,
        to: ElementPointMatch
    ) -> Self {
        .activationPoint(before: from, after: to)
    }

    public static func customContent(
        before: CustomContentMatch<String>? = nil,
        after: CustomContentMatch<String>? = nil
    ) -> Self {
        .customContent(ElementPropertyChange(before: before, after: after))
    }

    public static func customContent(
        from: CustomContentMatch<String>? = nil,
        to: CustomContentMatch<String>
    ) -> Self {
        .customContent(before: from, after: to)
    }

    public static func rotors(
        before: RotorSetMatch<String>? = nil,
        after: RotorSetMatch<String>? = nil
    ) -> Self {
        .rotors(ElementPropertyChange(before: before, after: after))
    }

    public static func rotors(
        from: RotorSetMatch<String>? = nil,
        to: RotorSetMatch<String>
    ) -> Self {
        .rotors(before: from, after: to)
    }
}

public enum AnyPropertyChangeExpr: Codable, Sendable, Equatable {
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

    public static func value(
        from: StringMatch<StringExpr>? = nil,
        to: StringMatch<StringExpr>
    ) -> Self {
        .value(before: from, after: to)
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

    public static func traits(
        from: TraitSetMatch? = nil,
        to: TraitSetMatch
    ) -> Self {
        .traits(before: from, after: to)
    }

    public static func hint(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .hint(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func hint(
        from: StringMatch<StringExpr>? = nil,
        to: StringMatch<StringExpr>
    ) -> Self {
        .hint(before: from, after: to)
    }

    public static func actions(
        before: ActionSetMatch? = nil,
        after: ActionSetMatch? = nil
    ) -> Self {
        .actions(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func actions(
        from: ActionSetMatch? = nil,
        to: ActionSetMatch
    ) -> Self {
        .actions(before: from, after: to)
    }

    public static func frame(
        before: ElementFrameMatch? = nil,
        after: ElementFrameMatch? = nil
    ) -> Self {
        .frame(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func frame(
        from: ElementFrameMatch? = nil,
        to: ElementFrameMatch
    ) -> Self {
        .frame(before: from, after: to)
    }

    public static func activationPoint(
        before: ElementPointMatch? = nil,
        after: ElementPointMatch? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func activationPoint(
        from: ElementPointMatch? = nil,
        to: ElementPointMatch
    ) -> Self {
        .activationPoint(before: from, after: to)
    }

    public static func customContent(
        before: CustomContentMatch<StringExpr>? = nil,
        after: CustomContentMatch<StringExpr>? = nil
    ) -> Self {
        .customContent(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func customContent(
        from: CustomContentMatch<StringExpr>? = nil,
        to: CustomContentMatch<StringExpr>
    ) -> Self {
        .customContent(before: from, after: to)
    }

    public static func rotors(
        before: RotorSetMatch<StringExpr>? = nil,
        after: RotorSetMatch<StringExpr>? = nil
    ) -> Self {
        .rotors(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func rotors(
        from: RotorSetMatch<StringExpr>? = nil,
        to: RotorSetMatch<StringExpr>
    ) -> Self {
        .rotors(before: from, after: to)
    }
}

// MARK: - Element Update Predicate

/// Predicate over a single element-property change in a baseline-to-current
/// transition.
///
/// `element` is an orthogonal identity matcher for the paired element.
/// `change` names at most one changed property. Its generic property kind locks
/// before and after to the same checker type, so contradictory predicates such
/// as "value before/after but property traits" are unrepresentable in Swift.
public struct ElementUpdatePredicate: Sendable, Equatable {
    public let element: ElementPredicate?
    public let change: AnyPropertyChange?

    public init(
        element: ElementPredicate? = nil,
        change: AnyPropertyChange? = nil
    ) {
        self.element = element
        self.change = change
    }

    /// Any tracked element property changed (all filters unset).
    public static let any = ElementUpdatePredicate()
}

public struct ElementUpdatePredicateExpr: Sendable, Equatable {
    public let element: ElementPredicateTemplate?
    public let change: AnyPropertyChangeExpr?

    public init(
        element: ElementPredicateTemplate? = nil,
        change: AnyPropertyChangeExpr? = nil
    ) {
        self.element = element
        self.change = change
    }

    public init(_ update: ElementUpdatePredicate) {
        self.init(
            element: update.element.map(ElementPredicateTemplate.init),
            change: update.change.map(AnyPropertyChangeExpr.init)
        )
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementUpdatePredicate {
        try ElementUpdatePredicate(
            element: element?.resolve(in: environment),
            change: change?.resolve(in: environment)
        )
    }
}

// MARK: - Element Delta Predicate

/// Predicate over one same-screen element delta.
///
/// These predicates reuse the same `ElementPredicate` and string matching
/// machinery as targeting. The only difference is the side of the delta they
/// are evaluated against:
/// - `appeared`: matches an element absent from the baseline and present in the
///   final tree.
/// - `disappeared`: matches an element present in the baseline and absent from
///   the final tree.
/// - `updated`: matches a paired element whose tracked properties changed.
public enum ElementDeltaPredicate: Sendable, Equatable {
    case appearedElement(ElementPredicate)
    case disappearedElement(ElementPredicate)
    case updatedElement(ElementUpdatePredicate)
}

// MARK: - Codable

private enum ElementUpdateCodingKeys: String, CodingKey, CaseIterable {
    case type, element, before, after, property
}

private func unsupportedUpdateProperty(
    _ property: ElementProperty,
    in container: KeyedDecodingContainer<ElementUpdateCodingKeys>
) -> DecodingError {
    DecodingError.dataCorruptedError(
        forKey: .property,
        in: container,
        debugDescription: "\(property.rawValue) is an element identity matcher, not an update property"
    )
}

extension ElementUpdatePredicate: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ElementUpdateCodingKeys.self, typeName: "element update predicate")
        let container = try decoder.container(keyedBy: ElementUpdateCodingKeys.self)
        self.init(
            element: try container.decodeIfPresent(ElementPredicate.self, forKey: .element),
            change: try AnyPropertyChange.decodeIfPresent(from: container)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementUpdateCodingKeys.self)
        try container.encodeIfPresent(element, forKey: .element)
        try change?.encodeFields(to: &container)
    }
}

extension ElementUpdatePredicateExpr: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: ElementUpdateCodingKeys.self, typeName: "element update predicate expression")
        let container = try decoder.container(keyedBy: ElementUpdateCodingKeys.self)
        self.init(
            element: try container.decodeIfPresent(ElementPredicateTemplate.self, forKey: .element),
            change: try AnyPropertyChangeExpr.decodeIfPresent(from: container)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementUpdateCodingKeys.self)
        try container.encodeIfPresent(element, forKey: .element)
        try change?.encodeFields(to: &container)
    }
}

extension ElementDeltaPredicate: Codable {
    private enum WireType: String, CaseIterable {
        case appeared
        case disappeared
        case updated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ElementUpdateCodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        guard let wireType = WireType(rawValue: typeString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown element delta predicate type: \"\(typeString)\". Valid: \(WireType.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        switch wireType {
        case .appeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "appeared predicate")
            self = .appearedElement(try container.decode(ElementPredicate.self, forKey: .element))
        case .disappeared:
            try decoder.rejectUnknownKeys(allowed: ["type", "element"], typeName: "disappeared predicate")
            self = .disappearedElement(try container.decode(ElementPredicate.self, forKey: .element))
        case .updated:
            try decoder.rejectUnknownKeys(allowed: ElementUpdateCodingKeys.self, typeName: "updated predicate")
            self = .updatedElement(try ElementUpdatePredicate(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ElementUpdateCodingKeys.self)
        switch self {
        case .appearedElement(let element):
            try container.encode(WireType.appeared.rawValue, forKey: .type)
            try container.encode(element, forKey: .element)
        case .disappearedElement(let element):
            try container.encode(WireType.disappeared.rawValue, forKey: .type)
            try container.encode(element, forKey: .element)
        case .updatedElement(let update):
            try container.encode(WireType.updated.rawValue, forKey: .type)
            try container.encodeIfPresent(update.element, forKey: .element)
            try update.change?.encodeFields(to: &container)
        }
    }
}

private extension AnyPropertyChange {
    static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChange? {
        let hasBefore = container.contains(.before)
        let hasAfter = container.contains(.after)
        guard let property = try container.decodeIfPresent(ElementProperty.self, forKey: .property) else {
            guard !hasBefore && !hasAfter else {
                throw DecodingError.dataCorruptedError(
                    forKey: .property,
                    in: container,
                    debugDescription: "updated predicate before/after require property"
                )
            }
            return nil
        }
        return try decode(property: property, from: container)
    }

    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChange {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try ElementPropertyChange<ValueProperty>(from: container))
        case .traits:
            return .traits(try ElementPropertyChange<TraitsProperty>(from: container))
        case .hint:
            return .hint(try ElementPropertyChange<HintProperty>(from: container))
        case .actions:
            return .actions(try ElementPropertyChange<ActionsProperty>(from: container))
        case .frame:
            return .frame(try ElementPropertyChange<FrameProperty>(from: container))
        case .activationPoint:
            return .activationPoint(try ElementPropertyChange<ActivationPointProperty>(from: container))
        case .customContent:
            return .customContent(try ElementPropertyChange<CustomContentProperty>(from: container))
        case .rotors:
            return .rotors(try ElementPropertyChange<RotorsProperty>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property, forKey: .property)
        switch self {
        case .value(let change):
            try change.encodeFields(to: &container)
        case .traits(let change):
            try change.encodeFields(to: &container)
        case .hint(let change):
            try change.encodeFields(to: &container)
        case .actions(let change):
            try change.encodeFields(to: &container)
        case .frame(let change):
            try change.encodeFields(to: &container)
        case .activationPoint(let change):
            try change.encodeFields(to: &container)
        case .customContent(let change):
            try change.encodeFields(to: &container)
        case .rotors(let change):
            try change.encodeFields(to: &container)
        }
    }
}

private extension AnyPropertyChangeExpr {
    static func decodeIfPresent(
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChangeExpr? {
        let hasBefore = container.contains(.before)
        let hasAfter = container.contains(.after)
        guard let property = try container.decodeIfPresent(ElementProperty.self, forKey: .property) else {
            guard !hasBefore && !hasAfter else {
                throw DecodingError.dataCorruptedError(
                    forKey: .property,
                    in: container,
                    debugDescription: "updated predicate expression before/after require property"
                )
            }
            return nil
        }
        return try decode(property: property, from: container)
    }

    static func decode(
        property: ElementProperty,
        from container: KeyedDecodingContainer<ElementUpdateCodingKeys>
    ) throws -> AnyPropertyChangeExpr {
        switch property {
        case .label, .identifier:
            throw unsupportedUpdateProperty(property, in: container)
        case .value:
            return .value(try ElementPropertyChangeExpr<ValueProperty>(from: container))
        case .traits:
            return .traits(try ElementPropertyChangeExpr<TraitsProperty>(from: container))
        case .hint:
            return .hint(try ElementPropertyChangeExpr<HintProperty>(from: container))
        case .actions:
            return .actions(try ElementPropertyChangeExpr<ActionsProperty>(from: container))
        case .frame:
            return .frame(try ElementPropertyChangeExpr<FrameProperty>(from: container))
        case .activationPoint:
            return .activationPoint(try ElementPropertyChangeExpr<ActivationPointProperty>(from: container))
        case .customContent:
            return .customContent(try ElementPropertyChangeExpr<CustomContentProperty>(from: container))
        case .rotors:
            return .rotors(try ElementPropertyChangeExpr<RotorsProperty>(from: container))
        }
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encode(property, forKey: .property)
        switch self {
        case .value(let change):
            try change.encodeFields(to: &container)
        case .traits(let change):
            try change.encodeFields(to: &container)
        case .hint(let change):
            try change.encodeFields(to: &container)
        case .actions(let change):
            try change.encodeFields(to: &container)
        case .frame(let change):
            try change.encodeFields(to: &container)
        case .activationPoint(let change):
            try change.encodeFields(to: &container)
        case .customContent(let change):
            try change.encodeFields(to: &container)
        case .rotors(let change):
            try change.encodeFields(to: &container)
        }
    }
}

private extension ElementPropertyChange {
    init(from container: KeyedDecodingContainer<ElementUpdateCodingKeys>) throws {
        self.init(
            before: try container.decodeIfPresent(P.Checker.self, forKey: .before),
            after: try container.decodeIfPresent(P.Checker.self, forKey: .after)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

private extension ElementPropertyChangeExpr {
    init(from container: KeyedDecodingContainer<ElementUpdateCodingKeys>) throws {
        self.init(
            before: try container.decodeIfPresent(P.ExprChecker.self, forKey: .before),
            after: try container.decodeIfPresent(P.ExprChecker.self, forKey: .after)
        )
    }

    func encodeFields(to container: inout KeyedEncodingContainer<ElementUpdateCodingKeys>) throws {
        try container.encodeIfPresent(before, forKey: .before)
        try container.encodeIfPresent(after, forKey: .after)
    }
}

// MARK: - CustomStringConvertible

extension ElementUpdatePredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("update", [
            element.map { "element=\($0)" },
            change.map { "change=\($0)" },
        ].compactMap { $0 })
    }
}

extension ElementUpdatePredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("update", [
            element.map { "element=\($0)" },
            change.map { "change=\($0)" },
        ].compactMap { $0 })
    }
}

extension AnyPropertyChange: CustomStringConvertible {
    public var description: String {
        switch self {
        case .value(let change): return change.description(name: "value")
        case .traits(let change): return change.description(name: "traits")
        case .hint(let change): return change.description(name: "hint")
        case .actions(let change): return change.description(name: "actions")
        case .frame(let change): return change.description(name: "frame")
        case .activationPoint(let change): return change.description(name: "activationPoint")
        case .customContent(let change): return change.description(name: "customContent")
        case .rotors(let change): return change.description(name: "rotors")
        }
    }
}

extension AnyPropertyChangeExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .value(let change): return change.description(name: "value")
        case .traits(let change): return change.description(name: "traits")
        case .hint(let change): return change.description(name: "hint")
        case .actions(let change): return change.description(name: "actions")
        case .frame(let change): return change.description(name: "frame")
        case .activationPoint(let change): return change.description(name: "activationPoint")
        case .customContent(let change): return change.description(name: "customContent")
        case .rotors(let change): return change.description(name: "rotors")
        }
    }
}

private extension ElementPropertyChange {
    func description(name: String) -> String {
        ScoreDescription.call(name, [
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
        ].compactMap { $0 })
    }
}

private extension ElementPropertyChangeExpr {
    func description(name: String) -> String {
        ScoreDescription.call(name, [
            before.map { "before=\($0)" },
            after.map { "after=\($0)" },
        ].compactMap { $0 })
    }
}

private extension Set where Element == ElementAction {
    var canonicalElementActionArray: [ElementAction] {
        sorted { lhs, rhs in
            lhs.canonicalSortKey < rhs.canonicalSortKey
        }
    }
}

private extension ElementAction {
    var canonicalSortKey: String {
        switch self {
        case .activate:
            return "0:activate"
        case .increment:
            return "1:increment"
        case .decrement:
            return "2:decrement"
        case .custom(let name):
            return "3:\(name)"
        }
    }
}

extension ElementDeltaPredicate: CustomStringConvertible {
    public var description: String {
        switch self {
        case .appearedElement(let element):
            return ScoreDescription.call("appeared", [element.description])
        case .disappearedElement(let element):
            return ScoreDescription.call("disappeared", [element.description])
        case .updatedElement(let update):
            return ScoreDescription.call("updated", [update.description])
        }
    }
}

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
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.actions
}

public enum FrameProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.frame
}

public enum ActivationPointProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.activationPoint
}

public enum CustomContentProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.customContent
}

public enum RotorsProperty: ElementPropertyKind {
    public typealias Checker = StringMatch<String>
    public typealias ExprChecker = StringMatch<StringExpr>
    public static let property = ElementProperty.rotors
}

/// Required and forbidden traits in a property's trait set.
public struct TraitSetMatch: Codable, Sendable, Equatable {
    public let include: [HeistTrait]
    public let exclude: [HeistTrait]

    public init(include: [HeistTrait] = [], exclude: [HeistTrait] = []) {
        self.include = include
        self.exclude = exclude
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

extension TraitSetMatch: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("traits", [
            include.isEmpty ? nil : "include=[\(include.map { ".\($0.rawValue)" }.joined(separator: ", "))]",
            exclude.isEmpty ? nil : "exclude=[\(exclude.map { ".\($0.rawValue)" }.joined(separator: ", "))]",
        ].compactMap { $0 })
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
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .actions(ElementPropertyChange(before: before, after: after))
    }

    public static func frame(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .frame(ElementPropertyChange(before: before, after: after))
    }

    public static func activationPoint(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChange(before: before, after: after))
    }

    public static func customContent(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .customContent(ElementPropertyChange(before: before, after: after))
    }

    public static func rotors(
        before: StringMatch<String>? = nil,
        after: StringMatch<String>? = nil
    ) -> Self {
        .rotors(ElementPropertyChange(before: before, after: after))
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
            self = .actions(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        case .frame(let change):
            self = .frame(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
        case .activationPoint(let change):
            self = .activationPoint(ElementPropertyChangeExpr(
                before: change.before?.map(StringExpr.literal),
                after: change.after?.map(StringExpr.literal)
            ))
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
            return .actions(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        case .frame(let change):
            return .frame(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
        case .activationPoint(let change):
            return .activationPoint(ElementPropertyChange(
                before: try change.before?.resolve(in: environment),
                after: try change.after?.resolve(in: environment)
            ))
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
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .actions(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func frame(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .frame(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func activationPoint(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .activationPoint(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func customContent(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .customContent(ElementPropertyChangeExpr(before: before, after: after))
    }

    public static func rotors(
        before: StringMatch<StringExpr>? = nil,
        after: StringMatch<StringExpr>? = nil
    ) -> Self {
        .rotors(ElementPropertyChangeExpr(before: before, after: after))
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

import Foundation

public enum AccessibilityContainerKind: String, Codable, CaseIterable, Sendable {
    case none
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case series
}

package enum SemanticContainerPredicateCore<Text> {
    case label(StringMatchCore<Text>)
    case value(StringMatchCore<Text>)

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> SemanticContainerPredicateCore<NewText> {
        switch self {
        case .label(let match):
            return try .label(match.map(transform))
        case .value(let match):
            return try .value(match.map(transform))
        }
    }
}

extension SemanticContainerPredicateCore: Sendable where Text: Sendable {}
extension SemanticContainerPredicateCore: Equatable where Text: Equatable {}
extension SemanticContainerPredicateCore: Hashable where Text: Hashable {}

package extension SemanticContainerPredicateCore where Text: StringMatchLeaf {
    var invalidPayloadDescription: String? {
        switch self {
        case .label(let match):
            return Self.invalidStringPayloadDescription(match, field: "container label")
        case .value(let match):
            return Self.invalidStringPayloadDescription(match, field: "container value")
        }
    }

    var wireKindValue: String {
        switch self {
        case .label:
            return "label"
        case .value:
            return "value"
        }
    }

    private static func invalidStringPayloadDescription(
        _ match: StringMatchCore<Text>,
        field: String
    ) -> String? {
        match.payload?.stringMatchLiteralIsEmpty == true ? "\(field) match value must not be empty" : nil
    }
}

public struct SemanticContainerPredicate: Codable, Sendable, Equatable, Hashable {
    package let core: SemanticContainerPredicateCore<Expr<String>>

    package init(core: SemanticContainerPredicateCore<Expr<String>>) {
        self.core = core
    }

    public static func label(_ match: StringMatch) -> Self { Self(core: .label(match.core)) }
    public static func label(_ label: String) -> Self { .label(.exact(label)) }
    @_disfavoredOverload
    public static func label(_ reference: HeistReferenceName) -> Self { .label(.exact(reference)) }
    public static func value(_ match: StringMatch) -> Self { Self(core: .value(match.core)) }
    public static func value(_ value: String) -> Self { .value(.exact(value)) }
    @_disfavoredOverload
    public static func value(_ reference: HeistReferenceName) -> Self { .value(.exact(reference)) }

    public init(from decoder: Decoder) throws {
        core = try SemanticContainerPredicateCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension SemanticContainerPredicate: CustomStringConvertible {
    public var description: String { core.description }
}

public struct ContainerPredicateCount: Codable, Sendable, Equatable, Hashable {
    public let value: UInt

    public init(_ value: UInt) {
        self.value = value
    }

    init?(exactly value: Int) {
        guard let value = UInt(exactly: value) else { return nil }
        self.value = value
    }

    fileprivate func matches(_ value: Int) -> Bool {
        UInt(exactly: value) == self.value
    }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(UInt.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct ContainerPredicateActions: Sendable, Equatable, Hashable {
    public let values: Set<ElementAction>

    public init(_ first: ElementAction, _ rest: ElementAction...) {
        values = Set([first] + rest)
    }

    init?(_ values: Set<ElementAction>) {
        guard !values.isEmpty else { return nil }
        self.values = values
    }
}

public enum ContainerPredicateRoleFacts: Codable, Sendable, Equatable, Hashable {
    case none
    case semanticGroup(label: String?, value: String?)
    case list
    case landmark
    case dataTable(rowCount: Int, columnCount: Int)
    case tabBar
    case series

    public var kind: AccessibilityContainerKind {
        switch self {
        case .none: return .none
        case .semanticGroup: return .semanticGroup
        case .list: return .list
        case .landmark: return .landmark
        case .dataTable: return .dataTable
        case .tabBar: return .tabBar
        case .series: return .series
        }
    }
}

package enum ContainerPredicateCheckCore<Text> {
    case type(AccessibilityContainerKind)
    case identifier(StringMatchCore<Text>)
    case semantic(SemanticContainerPredicateCore<Text>)
    case rowCount(ContainerPredicateCount)
    case columnCount(ContainerPredicateCount)
    case modalBoundary(Bool)
    case scrollable(Bool)
    case actions(ContainerPredicateActions)

    package func map<NewText>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> ContainerPredicateCheckCore<NewText> {
        switch self {
        case .type(let type): return .type(type)
        case .identifier(let match): return try .identifier(match.map(transform))
        case .semantic(let predicate): return try .semantic(predicate.map(transform))
        case .rowCount(let count): return .rowCount(count)
        case .columnCount(let count): return .columnCount(count)
        case .modalBoundary(let required): return .modalBoundary(required)
        case .scrollable(let required): return .scrollable(required)
        case .actions(let actions): return .actions(actions)
        }
    }
}

extension ContainerPredicateCheckCore: Sendable where Text: Sendable {}
extension ContainerPredicateCheckCore: Equatable where Text: Equatable {}
extension ContainerPredicateCheckCore: Hashable where Text: Hashable {}

package extension ContainerPredicateCheckCore where Text: StringMatchLeaf {
    var invalidEmptyPayloadDescription: String? {
        switch self {
        case .identifier(let match):
            return match.payload?.stringMatchLiteralIsEmpty == true
                ? "container identifier match value must not be empty"
                : nil
        case .semantic(let predicate):
            return predicate.invalidPayloadDescription
        case .actions:
            return nil
        case .type, .rowCount, .columnCount, .modalBoundary, .scrollable:
            return nil
        }
    }
}

public struct ContainerPredicateCheck: Codable, Sendable, Equatable, Hashable {
    package let core: ContainerPredicateCheckCore<Expr<String>>

    package init(core: ContainerPredicateCheckCore<Expr<String>>) {
        self.core = core
    }

    public static func type(_ type: AccessibilityContainerKind) -> Self { Self(core: .type(type)) }
    public static func identifier(_ match: StringMatch) -> Self { Self(core: .identifier(match.core)) }
    public static func identifier(_ value: String) -> Self { .identifier(.exact(value)) }
    @_disfavoredOverload
    public static func identifier(_ reference: HeistReferenceName) -> Self { .identifier(.exact(reference)) }
    public static func semantic(_ predicate: SemanticContainerPredicate) -> Self { Self(core: .semantic(predicate.core)) }
    public static func rowCount(_ count: ContainerPredicateCount) -> Self { Self(core: .rowCount(count)) }
    public static func columnCount(_ count: ContainerPredicateCount) -> Self { Self(core: .columnCount(count)) }
    public static func modalBoundary(_ required: Bool) -> Self { Self(core: .modalBoundary(required)) }
    public static func scrollable(_ required: Bool) -> Self { Self(core: .scrollable(required)) }
    public static func actions(_ actions: ContainerPredicateActions) -> Self { Self(core: .actions(actions)) }

    public static var wireKindValues: [String] { ContainerPredicateCheckCore<Expr<String>>.wireKindValues }
    public var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

    public init(from decoder: Decoder) throws {
        core = try ContainerPredicateCheckCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ContainerPredicateCheck: CustomStringConvertible {
    public var description: String { core.description }
}

package struct ContainerPredicateCore<Text: Sendable> {
    package let checks: NonEmptyArray<ContainerPredicateCheckCore<Text>>

    package init(checks: NonEmptyArray<ContainerPredicateCheckCore<Text>>) {
        self.checks = checks
    }

    package func map<NewText: Sendable>(
        _ transform: (Text) throws -> NewText
    ) rethrows -> ContainerPredicateCore<NewText> {
        try ContainerPredicateCore<NewText>(checks: checks.mapNonEmpty { try $0.map(transform) })
    }
}

extension ContainerPredicateCore: Sendable {}
extension ContainerPredicateCore: Equatable where Text: Equatable {}
extension ContainerPredicateCore: Hashable where Text: Hashable {}

package extension ContainerPredicateCore where Text: StringMatchLeaf {
    var invalidEmptyPayloadDescription: String? {
        checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first
    }
}

/// An authored container predicate with unresolved leaves hidden behind a
/// nongeneric public surface.
public struct ContainerPredicate: Codable, Sendable, Equatable, Hashable {
    package let core: ContainerPredicateCore<Expr<String>>

    package init(core: ContainerPredicateCore<Expr<String>>) {
        self.core = core
    }

    public var checks: [ContainerPredicateCheck] {
        core.checks.map { ContainerPredicateCheck(core: $0) }
    }

    public var hasPredicates: Bool { core.invalidEmptyPayloadDescription == nil }
    public var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

    public static func identifier(_ identifier: String) -> Self { matching(.identifier(identifier)) }
    @_disfavoredOverload
    public static func identifier(_ identifier: HeistReferenceName) -> Self { matching(.identifier(identifier)) }
    public static func identifier(_ identifier: StringMatch) -> Self { matching(.identifier(identifier)) }
    public static func label(_ label: String) -> Self { matching(.semantic(.label(label))) }
    @_disfavoredOverload
    public static func label(_ label: HeistReferenceName) -> Self { matching(.semantic(.label(label))) }
    public static func label(_ label: StringMatch) -> Self { matching(.semantic(.label(label))) }
    public static func value(_ value: String) -> Self { matching(.semantic(.value(value))) }
    @_disfavoredOverload
    public static func value(_ value: HeistReferenceName) -> Self { matching(.semantic(.value(value))) }
    public static func value(_ value: StringMatch) -> Self { matching(.semantic(.value(value))) }
    public static func type(_ type: AccessibilityContainerKind) -> Self { matching(.type(type)) }
    public static var none: Self { .type(.none) }
    public static var semanticGroup: Self { .type(.semanticGroup) }
    public static var list: Self { .type(.list) }
    public static var landmark: Self { .type(.landmark) }
    public static var tabBar: Self { .type(.tabBar) }

    public static func dataTable(
        rowCount: ContainerPredicateCount? = nil,
        columnCount: ContainerPredicateCount? = nil
    ) -> Self {
        let checks = [
            rowCount.map(ContainerPredicateCheck.rowCount),
            columnCount.map(ContainerPredicateCheck.columnCount),
        ].compactMap { $0 }
        return matching(.type(.dataTable), checks)
    }

    public static var modalBoundary: Self { matching(.modalBoundary(true)) }
    public static func scrollable(_ required: Bool) -> Self { matching(.scrollable(required)) }
    public static func actions(_ actions: ContainerPredicateActions) -> Self { matching(.actions(actions)) }

    public static func matching(
        _ first: ContainerPredicateCheck,
        _ rest: ContainerPredicateCheck...
    ) -> Self {
        matching(first, rest)
    }

    private static func matching(
        _ first: ContainerPredicateCheck,
        _ rest: [ContainerPredicateCheck]
    ) -> Self {
        Self(core: ContainerPredicateCore(checks: NonEmptyArray(first.core, rest: rest.map(\.core))))
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedContainerPredicate {
        ResolvedContainerPredicate(core: try core.map { try $0.resolve(in: environment) })
    }

    public init(from decoder: Decoder) throws {
        core = try ContainerPredicateCore(from: decoder)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
        }
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ContainerPredicate: CustomStringConvertible {
    public var description: String { core.description }
}

/// A resolved container predicate. It cannot contain references.
public struct ResolvedContainerPredicate: Codable, Sendable, Equatable, Hashable {
    package let core: ContainerPredicateCore<String>

    package init(core: ContainerPredicateCore<String>) {
        self.core = core
    }

    public var hasPredicates: Bool { core.invalidEmptyPayloadDescription == nil }
    public var invalidEmptyPayloadDescription: String? { core.invalidEmptyPayloadDescription }

    public func matches(_ facts: ContainerPredicateFacts) -> Bool {
        invalidEmptyPayloadDescription == nil && core.checks.allSatisfy { $0.matches(facts) }
    }

    public init(from decoder: Decoder) throws {
        core = try ContainerPredicateCore(from: decoder)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
        }
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }
}

extension ResolvedContainerPredicate: CustomStringConvertible {
    public var description: String { core.description }
}

public struct ContainerPredicateFacts: Sendable, Equatable, Hashable {
    public let role: ContainerPredicateRoleFacts
    public let identifier: String?
    public let isModalBoundary: Bool
    public let isScrollable: Bool
    public let actions: Set<ElementAction>

    public init(
        role: ContainerPredicateRoleFacts,
        identifier: String? = nil,
        isModalBoundary: Bool = false,
        isScrollable: Bool = false,
        actions: Set<ElementAction> = []
    ) {
        self.role = role
        self.identifier = identifier
        self.isModalBoundary = isModalBoundary
        self.isScrollable = isScrollable
        self.actions = actions
    }
}

// MARK: - Core Evaluation

private extension SemanticContainerPredicateCore where Text == String {
    func matches(_ facts: ContainerPredicateFacts) -> Bool {
        guard case .semanticGroup(let label, let value) = facts.role else { return false }
        switch self {
        case .label(let match):
            return ResolvedStringMatch(core: match).matches(optional: label)
        case .value(let match):
            return ResolvedStringMatch(core: match).matches(optional: value)
        }
    }
}

private extension ContainerPredicateCheckCore where Text == String {
    func matches(_ facts: ContainerPredicateFacts) -> Bool {
        switch self {
        case .type(let type): return facts.role.kind == type
        case .identifier(let match): return ResolvedStringMatch(core: match).matches(optional: facts.identifier)
        case .semantic(let predicate): return predicate.matches(facts)
        case .rowCount(let count):
            guard case .dataTable(let actual, _) = facts.role else { return false }
            return count.matches(actual)
        case .columnCount(let count):
            guard case .dataTable(_, let actual) = facts.role else { return false }
            return count.matches(actual)
        case .modalBoundary(let required): return facts.isModalBoundary == required
        case .scrollable(let required): return facts.isScrollable == required
        case .actions(let required): return facts.actions.isSuperset(of: required.values)
        }
    }
}

// MARK: - Core Codable

extension SemanticContainerPredicateCore: Codable where Text: Codable & StringMatchLeaf {
    private enum Kind: String, Codable, CaseIterable { case label, value }
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, match }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "semantic container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label: self = .label(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        case .value: self = .value(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        }
        if let description = invalidPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.match],
                debugDescription: description
            ))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .label(let match):
            try container.encode(Kind.label, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .value(let match):
            try container.encode(Kind.value, forKey: .kind)
            try container.encode(match, forKey: .match)
        }
    }
}

extension SemanticContainerPredicateCore: CustomStringConvertible {
    package var description: String {
        switch self {
        case .label(let match): return ScoreDescription.call("semantic", ["label=\(match)"])
        case .value(let match): return ScoreDescription.call("semantic", ["value=\(match)"])
        }
    }
}

extension ContainerPredicateCheckCore: Codable where Text: Codable & StringMatchLeaf {
    private enum Kind: String, Codable, CaseIterable {
        case type, identifier, semantic, rowCount, columnCount, modalBoundary, scrollable, actions

        var payloadKey: CodingKeys {
            switch self {
            case .type: return .type
            case .identifier: return .match
            case .semantic: return .semantic
            case .rowCount, .columnCount, .modalBoundary, .scrollable: return .value
            case .actions: return .values
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, type, semantic, match, value, values
    }

    package static var wireKindValues: [String] { Kind.allCases.map(\.rawValue) }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try decoder.rejectUnknownKeys(
            allowed: Set([CodingKeys.kind.stringValue, kind.payloadKey.stringValue]),
            typeName: "\(kind.rawValue) container predicate check"
        )
        switch kind {
        case .type: self = .type(try container.decode(AccessibilityContainerKind.self, forKey: .type))
        case .identifier: self = .identifier(try container.decode(StringMatchCore<Text>.self, forKey: .match))
        case .semantic:
            self = .semantic(try container.decode(SemanticContainerPredicateCore<Text>.self, forKey: .semantic))
        case .rowCount: self = .rowCount(try container.decode(ContainerPredicateCount.self, forKey: .value))
        case .columnCount: self = .columnCount(try container.decode(ContainerPredicateCount.self, forKey: .value))
        case .modalBoundary: self = .modalBoundary(try container.decode(Bool.self, forKey: .value))
        case .scrollable: self = .scrollable(try container.decode(Bool.self, forKey: .value))
        case .actions:
            let values = Set(try container.decode([ElementAction].self, forKey: .values))
            guard let actions = ContainerPredicateActions(values) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath + [CodingKeys.values],
                    debugDescription: "container actions check must not be empty"
                ))
            }
            self = .actions(actions)
        }
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: description))
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .type(let type):
            try container.encode(Kind.type, forKey: .kind)
            try container.encode(type, forKey: .type)
        case .identifier(let match):
            try container.encode(Kind.identifier, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .semantic(let predicate):
            try container.encode(Kind.semantic, forKey: .kind)
            try container.encode(predicate, forKey: .semantic)
        case .rowCount(let count):
            try container.encode(Kind.rowCount, forKey: .kind)
            try container.encode(count, forKey: .value)
        case .columnCount(let count):
            try container.encode(Kind.columnCount, forKey: .kind)
            try container.encode(count, forKey: .value)
        case .modalBoundary(let value):
            try container.encode(Kind.modalBoundary, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .scrollable(let value):
            try container.encode(Kind.scrollable, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .actions(let actions):
            try container.encode(Kind.actions, forKey: .kind)
            try container.encode(actions.values.canonicalElementActionArray, forKey: .values)
        }
    }
}

extension ContainerPredicateCheckCore: CustomStringConvertible {
    package var description: String {
        switch self {
        case .type(let type): return "type=\(type)"
        case .identifier(let match): return "identifier=\(match)"
        case .semantic(let predicate): return "semantic=\(predicate)"
        case .rowCount(let count): return "rowCount=\(count.value)"
        case .columnCount(let count): return "columnCount=\(count.value)"
        case .modalBoundary(let required): return "modal=\(required)"
        case .scrollable(let required): return "scrollable=\(required)"
        case .actions(let actions):
            return "actions=[\(actions.values.canonicalElementActionArray.map(\.description).joined(separator: ", "))]"
        }
    }
}

extension ContainerPredicateCore: Codable where Text: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable { case checks }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checks = try container.decode(NonEmptyArray<ContainerPredicateCheckCore<Text>>.self, forKey: .checks)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checks, forKey: .checks)
    }
}

extension ContainerPredicateCore: CustomStringConvertible {
    package var description: String {
        ScoreDescription.call("container", checks.map(\.description))
    }
}

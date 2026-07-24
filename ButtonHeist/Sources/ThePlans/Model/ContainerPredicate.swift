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

public enum SemanticContainerPredicate: Codable, Sendable, Equatable, Hashable {
    case label(StringMatch)
    case value(StringMatch)

    private enum Kind: String, Codable, CaseIterable { case label, value }
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, match }

    public static func label(_ label: String) -> Self { .label(.exact(label)) }
    @_disfavoredOverload
    public static func label(_ reference: HeistReferenceName) -> Self { .label(.exact(reference)) }
    public static func value(_ value: String) -> Self { .value(.exact(value)) }
    @_disfavoredOverload
    public static func value(_ reference: HeistReferenceName) -> Self { .value(.exact(reference)) }

    package var invalidPayloadDescription: String? {
        switch self {
        case .label(let match):
            return match.value?.literalIsEmpty == true ? "container label match value must not be empty" : nil
        case .value(let match):
            return match.value?.literalIsEmpty == true ? "container value match value must not be empty" : nil
        }
    }

    package var wireKindValue: String {
        switch self {
        case .label: return "label"
        case .value: return "value"
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedSemanticContainerPredicate {
        switch self {
        case .label(let match): return .label(try match.resolve(in: environment))
        case .value(let match): return .value(try match.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "semantic container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label: self = .label(try container.decode(StringMatch.self, forKey: .match))
        case .value: self = .value(try container.decode(StringMatch.self, forKey: .match))
        }
        if let description = invalidPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.match],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
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

extension SemanticContainerPredicate: CustomStringConvertible {
    public var description: String {
        switch self {
        case .label(let match): return CanonicalValueDescription.call("semantic", ["label=\(match)"])
        case .value(let match): return CanonicalValueDescription.call("semantic", ["value=\(match)"])
        }
    }
}

package enum ResolvedSemanticContainerPredicate: Codable, Sendable, Equatable, Hashable {
    case label(ResolvedStringMatch)
    case value(ResolvedStringMatch)

    private enum Kind: String, Codable, CaseIterable { case label, value }
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, match }

    package var invalidPayloadDescription: String? {
        switch self {
        case .label(let match):
            return match.value?.isEmpty == true ? "container label match value must not be empty" : nil
        case .value(let match):
            return match.value?.isEmpty == true ? "container value match value must not be empty" : nil
        }
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "semantic container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label: self = .label(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .value: self = .value(try container.decode(ResolvedStringMatch.self, forKey: .match))
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

extension ResolvedSemanticContainerPredicate: CustomStringConvertible {
    package var description: String {
        switch self {
        case .label(let match): return CanonicalValueDescription.call("semantic", ["label=\(match)"])
        case .value(let match): return CanonicalValueDescription.call("semantic", ["value=\(match)"])
        }
    }
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

public enum ContainerPredicateCheck: Codable, Sendable, Equatable, Hashable {
    case type(AccessibilityContainerKind)
    case identifier(StringMatch)
    case semantic(SemanticContainerPredicate)
    case rowCount(ContainerPredicateCount)
    case columnCount(ContainerPredicateCount)
    case modalBoundary(Bool)
    case scrollable(Bool)
    case actions(ContainerPredicateActions)

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

    public static func identifier(_ value: String) -> Self { .identifier(.exact(value)) }
    @_disfavoredOverload
    public static func identifier(_ reference: HeistReferenceName) -> Self { .identifier(.exact(reference)) }
    public static var wireKindValues: [String] { Kind.allCases.map(\.rawValue) }

    public var invalidEmptyPayloadDescription: String? {
        switch self {
        case .identifier(let match):
            return match.value?.literalIsEmpty == true ? "container identifier match value must not be empty" : nil
        case .semantic(let predicate):
            return predicate.invalidPayloadDescription
        case .type, .rowCount, .columnCount, .modalBoundary, .scrollable, .actions:
            return nil
        }
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedContainerPredicateCheck {
        switch self {
        case .type(let type): return .type(type)
        case .identifier(let match): return .identifier(try match.resolve(in: environment))
        case .semantic(let predicate): return .semantic(try predicate.resolve(in: environment))
        case .rowCount(let count): return .rowCount(count)
        case .columnCount(let count): return .columnCount(count)
        case .modalBoundary(let required): return .modalBoundary(required)
        case .scrollable(let required): return .scrollable(required)
        case .actions(let actions): return .actions(actions)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try decoder.rejectUnknownKeys(
            allowed: Set([CodingKeys.kind.stringValue, kind.payloadKey.stringValue]),
            typeName: "\(kind.rawValue) container predicate check"
        )
        switch kind {
        case .type: self = .type(try container.decode(AccessibilityContainerKind.self, forKey: .type))
        case .identifier: self = .identifier(try container.decode(StringMatch.self, forKey: .match))
        case .semantic: self = .semantic(try container.decode(SemanticContainerPredicate.self, forKey: .semantic))
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

    public func encode(to encoder: Encoder) throws {
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

extension ContainerPredicateCheck: CustomStringConvertible {
    public var description: String {
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

package enum ResolvedContainerPredicateCheck: Codable, Sendable, Equatable, Hashable {
    case type(AccessibilityContainerKind)
    case identifier(ResolvedStringMatch)
    case semantic(ResolvedSemanticContainerPredicate)
    case rowCount(ContainerPredicateCount)
    case columnCount(ContainerPredicateCount)
    case modalBoundary(Bool)
    case scrollable(Bool)
    case actions(ContainerPredicateActions)

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

    package var invalidEmptyPayloadDescription: String? {
        switch self {
        case .identifier(let match):
            return match.value?.isEmpty == true ? "container identifier match value must not be empty" : nil
        case .semantic(let predicate):
            return predicate.invalidPayloadDescription
        case .type, .rowCount, .columnCount, .modalBoundary, .scrollable, .actions:
            return nil
        }
    }

    package func matches(_ facts: ContainerPredicateFacts) -> Bool {
        switch self {
        case .type(let type): return facts.role.kind == type
        case .identifier(let match): return match.matches(optional: facts.identifier)
        case .semantic(let predicate):
            guard case .semanticGroup(let label, let value) = facts.role else { return false }
            switch predicate {
            case .label(let match): return match.matches(optional: label)
            case .value(let match): return match.matches(optional: value)
            }
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

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try decoder.rejectUnknownKeys(
            allowed: Set([CodingKeys.kind.stringValue, kind.payloadKey.stringValue]),
            typeName: "\(kind.rawValue) container predicate check"
        )
        switch kind {
        case .type: self = .type(try container.decode(AccessibilityContainerKind.self, forKey: .type))
        case .identifier: self = .identifier(try container.decode(ResolvedStringMatch.self, forKey: .match))
        case .semantic:
            self = .semantic(try container.decode(ResolvedSemanticContainerPredicate.self, forKey: .semantic))
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

extension ResolvedContainerPredicateCheck: CustomStringConvertible {
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

/// An authored container predicate.
public struct ContainerPredicate: Codable, Sendable, Equatable, Hashable {
    package let authoredChecks: NonEmptyArray<ContainerPredicateCheck>

    package init(checks: NonEmptyArray<ContainerPredicateCheck>) {
        authoredChecks = checks
    }

    public var checks: [ContainerPredicateCheck] { Array(authoredChecks) }
    public var hasPredicates: Bool { invalidEmptyPayloadDescription == nil }
    public var invalidEmptyPayloadDescription: String? {
        authoredChecks.lazy.compactMap(\.invalidEmptyPayloadDescription).first
    }

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
        matching(.type(.dataTable), [
            rowCount.map(ContainerPredicateCheck.rowCount),
            columnCount.map(ContainerPredicateCheck.columnCount),
        ].compactMap { $0 })
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
        Self(checks: NonEmptyArray(first, rest: rest))
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedContainerPredicate {
        try ResolvedContainerPredicate(
            validating: authoredChecks.mapNonEmpty { try $0.resolve(in: environment) }
        )
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authoredChecks = try container.decode(NonEmptyArray<ContainerPredicateCheck>.self, forKey: .checks)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: description))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(authoredChecks, forKey: .checks)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case checks }
}

extension ContainerPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("container", authoredChecks.map(\.description))
    }
}

/// A resolved container predicate. It cannot contain references.
public struct ResolvedContainerPredicate: Codable, Sendable, Equatable, Hashable {
    package let checks: NonEmptyArray<ResolvedContainerPredicateCheck>

    package init(validating checks: NonEmptyArray<ResolvedContainerPredicateCheck>) throws {
        if let reason = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            throw InvalidResolvedPredicateError(reason: reason)
        }
        self.checks = checks
    }

    public func matches(_ facts: ContainerPredicateFacts) -> Bool {
        checks.allSatisfy { $0.matches(facts) }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let checks = try container.decode(NonEmptyArray<ResolvedContainerPredicateCheck>.self, forKey: .checks)
        do {
            try self.init(validating: checks)
        } catch let error as InvalidResolvedPredicateError {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: error.reason
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checks, forKey: .checks)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case checks }
}

extension ResolvedContainerPredicate: CustomStringConvertible {
    public var description: String {
        CanonicalValueDescription.call("container", checks.map(\.description))
    }
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

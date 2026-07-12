import Foundation

// MARK: - Container Predicates

public enum AccessibilityContainerKind: String, Codable, CaseIterable, Sendable {
    case none
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case series
}

public enum SemanticContainerPredicate<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    case label(StringMatch<Value>)
    case value(StringMatch<Value>)

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> SemanticContainerPredicate<NewValue> {
        switch self {
        case .label(let match):
            return try .label(match.map(transform))
        case .value(let match):
            return try .value(match.map(transform))
        }
    }

    fileprivate var invalidPayloadDescription: String? {
        switch self {
        case .label(let match):
            return Self.invalidStringPayloadDescription(match, field: "container label")
        case .value(let match):
            return Self.invalidStringPayloadDescription(match, field: "container value")
        }
    }

    private static func invalidStringPayloadDescription(
        _ match: StringMatch<Value>,
        field: String
    ) -> String? {
        match.valueIfPresent?.stringMatchLiteralIsEmpty == true ? "\(field) match value must not be empty" : nil
    }
}

public extension SemanticContainerPredicate where Value == String {
    static func label(_ label: String) -> SemanticContainerPredicate {
        .label(.exact(label))
    }

    static func value(_ value: String) -> SemanticContainerPredicate {
        .value(.exact(value))
    }
}

public extension SemanticContainerPredicate where Value == StringExpr {
    static func label(_ label: StringExpr) -> SemanticContainerPredicate {
        .label(.exact(label))
    }

    static func label(_ label: String) -> SemanticContainerPredicate {
        .label(StringMatch<StringExpr>.literal(label))
    }

    static func value(_ value: StringExpr) -> SemanticContainerPredicate {
        .value(.exact(value))
    }

    static func value(_ value: String) -> SemanticContainerPredicate {
        .value(StringMatch<StringExpr>.literal(value))
    }
}

extension SemanticContainerPredicate: Codable where Value: Codable {
    private enum Kind: String, Codable, CaseIterable {
        case label, value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, match
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "semantic container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .label:
            self = .label(try container.decode(StringMatch<Value>.self, forKey: .match))
        case .value:
            self = .value(try container.decode(StringMatch<Value>.self, forKey: .match))
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
        case .label(let match):
            return ScoreDescription.call("semantic", ["label=\(match)"])
        case .value(let match):
            return ScoreDescription.call("semantic", ["value=\(match)"])
        }
    }
}

private extension SemanticContainerPredicate where Value == String {
    func matches(_ facts: ContainerPredicateFacts) -> Bool {
        guard case .semanticGroup(let label, let value) = facts.role else { return false }
        switch self {
        case .label(let match):
            return match.matches(optional: label)
        case .value(let match):
            return match.matches(optional: value)
        }
    }
}

public struct ContainerPredicateCount: Codable, Sendable, Equatable, Hashable {
    public let value: UInt

    public init(_ value: UInt) {
        self.value = value
    }

    public init?(exactly value: Int) {
        guard let value = UInt(exactly: value) else { return nil }
        self.value = value
    }

    fileprivate func matches(_ value: Int) -> Bool {
        UInt(exactly: value) == self.value
    }

    public init(from decoder: Decoder) throws {
        self.value = try decoder.singleValueContainer().decode(UInt.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct ContainerPredicateActions: Sendable, Equatable, Hashable {
    public let values: Set<ElementAction>

    public init(_ first: ElementAction, _ rest: ElementAction...) {
        self.values = Set([first] + rest)
    }

    public init?(_ values: Set<ElementAction>) {
        guard !values.isEmpty else { return nil }
        self.values = values
    }
}

public enum ContainerPredicateRoleFacts: Sendable, Equatable, Hashable {
    case none
    case semanticGroup(label: String?, value: String?)
    case list
    case landmark
    case dataTable(rowCount: Int, columnCount: Int)
    case tabBar
    case series

    public var kind: AccessibilityContainerKind {
        switch self {
        case .none:
            return .none
        case .semanticGroup:
            return .semanticGroup
        case .list:
            return .list
        case .landmark:
            return .landmark
        case .dataTable:
            return .dataTable
        case .tabBar:
            return .tabBar
        case .series:
            return .series
        }
    }
}

public enum ContainerPredicateCheck<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    case type(AccessibilityContainerKind)
    case identifier(StringMatch<Value>)
    case semantic(SemanticContainerPredicate<Value>)
    case rowCount(ContainerPredicateCount)
    case columnCount(ContainerPredicateCount)
    case modalBoundary(Bool)
    case scrollable(Bool)
    case actions(ContainerPredicateActions)

    private enum Kind: String, Codable, CaseIterable {
        case type, identifier, semantic, rowCount, columnCount, modalBoundary, scrollable, actions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, type, semantic, match, value, values
    }

    public static var wireKindValues: [String] {
        Kind.allCases.map(\.rawValue)
    }

    public var invalidEmptyPayloadDescription: String? {
        switch self {
        case .identifier(let match):
            return Self.invalidStringPayloadDescription(match, field: "container identifier")
        case .semantic(let predicate):
            return predicate.invalidPayloadDescription
        case .type, .rowCount, .columnCount, .modalBoundary, .scrollable, .actions:
            return nil
        }
    }

    private static func invalidStringPayloadDescription(
        _ match: StringMatch<Value>,
        field: String
    ) -> String? {
        match.valueIfPresent?.stringMatchLiteralIsEmpty == true ? "\(field) match value must not be empty" : nil
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> ContainerPredicateCheck<NewValue> {
        switch self {
        case .type(let type):
            return .type(type)
        case .identifier(let match):
            return try .identifier(match.map(transform))
        case .semantic(let predicate):
            return try .semantic(predicate.map(transform))
        case .rowCount(let count):
            return .rowCount(count)
        case .columnCount(let count):
            return .columnCount(count)
        case .modalBoundary(let required):
            return .modalBoundary(required)
        case .scrollable(let required):
            return .scrollable(required)
        case .actions(let actions):
            return .actions(actions)
        }
    }

    fileprivate func matches(_ facts: ContainerPredicateFacts) -> Bool where Value == String {
        switch self {
        case .type(let type):
            return facts.role.kind == type
        case .identifier(let match):
            return match.matches(optional: facts.identifier)
        case .semantic(let predicate):
            return predicate.matches(facts)
        case .rowCount(let rowCount):
            guard case .dataTable(let actual, _) = facts.role else { return false }
            return rowCount.matches(actual)
        case .columnCount(let columnCount):
            guard case .dataTable(_, let actual) = facts.role else { return false }
            return columnCount.matches(actual)
        case .modalBoundary(let required):
            return facts.isModalBoundary == required
        case .scrollable(let required):
            return facts.isScrollable == required
        case .actions(let required):
            return facts.actions.isSuperset(of: required.values)
        }
    }
}

extension ContainerPredicateCheck: Codable where Value: Codable {
    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .type:
            self = .type(try container.decode(AccessibilityContainerKind.self, forKey: .type))
        case .identifier:
            self = .identifier(try container.decode(StringMatch<Value>.self, forKey: .match))
        case .semantic:
            self = .semantic(try container.decode(SemanticContainerPredicate<Value>.self, forKey: .semantic))
        case .rowCount:
            self = .rowCount(try container.decode(ContainerPredicateCount.self, forKey: .value))
        case .columnCount:
            self = .columnCount(try container.decode(ContainerPredicateCount.self, forKey: .value))
        case .modalBoundary:
            self = .modalBoundary(try container.decode(Bool.self, forKey: .value))
        case .scrollable:
            self = .scrollable(try container.decode(Bool.self, forKey: .value))
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
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: description
            ))
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
        case .type(let type):
            return "type=\(type)"
        case .identifier(let match):
            return "identifier=\(match)"
        case .semantic(let predicate):
            return "semantic=\(predicate)"
        case .rowCount(let rowCount):
            return "rowCount=\(rowCount.value)"
        case .columnCount(let columnCount):
            return "columnCount=\(columnCount.value)"
        case .modalBoundary(let required):
            return "modal=\(required)"
        case .scrollable(let required):
            return "scrollable=\(required)"
        case .actions(let actions):
            return "actions=[\(actions.values.canonicalElementActionArray.map(\.description).joined(separator: ", "))]"
        }
    }
}

public struct ContainerPredicate: Codable, Sendable, Equatable, Hashable {
    public let checks: NonEmptyArray<ContainerPredicateCheck<String>>

    fileprivate init(checks: NonEmptyArray<ContainerPredicateCheck<String>>) {
        self.checks = checks
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public var hasPredicates: Bool {
        invalidEmptyPayloadDescription == nil
    }

    public var invalidEmptyPayloadDescription: String? {
        checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first
    }

    public func matches(_ facts: ContainerPredicateFacts) -> Bool {
        invalidEmptyPayloadDescription == nil && checks.allSatisfy { $0.matches(facts) }
    }

    public static func identifier(_ identifier: String) -> ContainerPredicate {
        matching(.identifier(.exact(identifier)))
    }

    public static func identifier(_ identifier: StringMatch<String>) -> ContainerPredicate {
        matching(.identifier(identifier))
    }

    public static func label(_ label: String) -> ContainerPredicate {
        matching(.semantic(.label(label)))
    }

    public static func label(_ label: StringMatch<String>) -> ContainerPredicate {
        matching(.semantic(.label(label)))
    }

    public static func value(_ value: String) -> ContainerPredicate {
        matching(.semantic(.value(value)))
    }

    public static func value(_ value: StringMatch<String>) -> ContainerPredicate {
        matching(.semantic(.value(value)))
    }

    public static func type(_ type: AccessibilityContainerKind) -> ContainerPredicate {
        matching(.type(type))
    }

    public static var none: ContainerPredicate { .type(.none) }
    public static var semanticGroup: ContainerPredicate { .type(.semanticGroup) }
    public static var list: ContainerPredicate { .type(.list) }
    public static var landmark: ContainerPredicate { .type(.landmark) }
    public static var tabBar: ContainerPredicate { .type(.tabBar) }
    public static func dataTable(
        rowCount: ContainerPredicateCount? = nil,
        columnCount: ContainerPredicateCount? = nil
    ) -> ContainerPredicate {
        let countChecks = [
            rowCount.map(ContainerPredicateCheck<String>.rowCount),
            columnCount.map(ContainerPredicateCheck<String>.columnCount),
        ].compactMap { $0 }
        return ContainerPredicate(
            checks: NonEmptyArray(.type(.dataTable), rest: countChecks)
        )
    }

    public static var modalBoundary: ContainerPredicate {
        matching(.modalBoundary(true))
    }

    public static func scrollable(_ required: Bool) -> ContainerPredicate {
        matching(.scrollable(required))
    }

    public static func actions(_ actions: ContainerPredicateActions) -> ContainerPredicate {
        matching(.actions(actions))
    }

    public static func matching(
        _ first: ContainerPredicateCheck<String>,
        _ rest: ContainerPredicateCheck<String>...
    ) -> ContainerPredicate {
        ContainerPredicate(checks: NonEmptyArray(first, rest: rest))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.checks = try container.decode(NonEmptyArray<ContainerPredicateCheck<String>>.self, forKey: .checks)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.checks],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checks, forKey: .checks)
    }
}

extension ContainerPredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", checks.map(\.description))
    }
}

public struct ContainerPredicateExpr: Codable, Sendable, Equatable, Hashable {
    public let checks: NonEmptyArray<ContainerPredicateCheck<StringExpr>>

    internal init(checks: NonEmptyArray<ContainerPredicateCheck<StringExpr>>) {
        self.checks = checks
    }

    public init(_ predicate: ContainerPredicate) {
        self.checks = predicate.checks.mapNonEmpty { $0.map { .literal($0) } }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public var hasPredicates: Bool {
        invalidEmptyPayloadDescription == nil
    }

    public var invalidEmptyPayloadDescription: String? {
        checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ContainerPredicate {
        ContainerPredicate(checks: try checks.mapNonEmpty { try $0.map { try $0.resolve(in: environment) } })
    }

    public static func identifier(_ identifier: StringExpr) -> ContainerPredicateExpr {
        matching(.identifier(.exact(identifier)))
    }

    public static func identifier(_ identifier: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        matching(.identifier(identifier))
    }

    public static func identifier(_ identifier: String) -> ContainerPredicateExpr {
        matching(.identifier(StringMatch<StringExpr>.literal(identifier)))
    }

    public static func label(_ label: StringExpr) -> ContainerPredicateExpr {
        matching(.semantic(.label(label)))
    }

    public static func label(_ label: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        matching(.semantic(.label(label)))
    }

    public static func label(_ label: String) -> ContainerPredicateExpr {
        matching(.semantic(.label(label)))
    }

    public static func value(_ value: StringExpr) -> ContainerPredicateExpr {
        matching(.semantic(.value(value)))
    }

    public static func value(_ value: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        matching(.semantic(.value(value)))
    }

    public static func value(_ value: String) -> ContainerPredicateExpr {
        matching(.semantic(.value(value)))
    }

    public static func type(_ type: AccessibilityContainerKind) -> ContainerPredicateExpr {
        matching(.type(type))
    }

    public static var none: ContainerPredicateExpr { .type(.none) }
    public static var semanticGroup: ContainerPredicateExpr { .type(.semanticGroup) }
    public static var list: ContainerPredicateExpr { .type(.list) }
    public static var landmark: ContainerPredicateExpr { .type(.landmark) }
    public static var tabBar: ContainerPredicateExpr { .type(.tabBar) }
    public static func dataTable(
        rowCount: ContainerPredicateCount? = nil,
        columnCount: ContainerPredicateCount? = nil
    ) -> ContainerPredicateExpr {
        let countChecks = [
            rowCount.map(ContainerPredicateCheck<StringExpr>.rowCount),
            columnCount.map(ContainerPredicateCheck<StringExpr>.columnCount),
        ].compactMap { $0 }
        return ContainerPredicateExpr(
            checks: NonEmptyArray(.type(.dataTable), rest: countChecks)
        )
    }

    public static var modalBoundary: ContainerPredicateExpr {
        matching(.modalBoundary(true))
    }

    public static func scrollable(_ required: Bool) -> ContainerPredicateExpr {
        matching(.scrollable(required))
    }

    public static func actions(_ actions: ContainerPredicateActions) -> ContainerPredicateExpr {
        matching(.actions(actions))
    }

    public static func matching(
        _ first: ContainerPredicateCheck<StringExpr>,
        _ rest: ContainerPredicateCheck<StringExpr>...
    ) -> ContainerPredicateExpr {
        ContainerPredicateExpr(checks: NonEmptyArray(first, rest: rest))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.checks = try container.decode(NonEmptyArray<ContainerPredicateCheck<StringExpr>>.self, forKey: .checks)
        if let description = invalidEmptyPayloadDescription {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.checks],
                debugDescription: description
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(checks, forKey: .checks)
    }
}

extension ContainerPredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", checks.map(\.description))
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

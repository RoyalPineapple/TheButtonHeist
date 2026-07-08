import Foundation

// MARK: - Container Predicates

public enum AccessibilityContainerKind: String, Codable, CaseIterable, Sendable {
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case scrollable
}

public enum SemanticContainerPredicate<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    case label(StringMatch<Value>)
    case value(StringMatch<Value>)
    case identifier(StringMatch<Value>)

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> SemanticContainerPredicate<NewValue> {
        switch self {
        case .label(let match):
            return try .label(match.map(transform))
        case .value(let match):
            return try .value(match.map(transform))
        case .identifier(let match):
            return try .identifier(match.map(transform))
        }
    }

    fileprivate var invalidPayloadDescription: String? {
        switch self {
        case .label(let match):
            return Self.invalidStringPayloadDescription(match, field: "container label")
        case .value(let match):
            return Self.invalidStringPayloadDescription(match, field: "container value")
        case .identifier(let match):
            return Self.invalidStringPayloadDescription(match, field: "container identifier")
        }
    }

    fileprivate var hasPredicates: Bool {
        switch self {
        case .label(let match), .value(let match), .identifier(let match):
            if case .isEmpty = match { return true }
            return match.hasPredicateLiteral
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

    static func identifier(_ identifier: String) -> SemanticContainerPredicate {
        .identifier(.exact(identifier))
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

    static func identifier(_ identifier: StringExpr) -> SemanticContainerPredicate {
        .identifier(.exact(identifier))
    }

    static func identifier(_ identifier: String) -> SemanticContainerPredicate {
        .identifier(StringMatch<StringExpr>.literal(identifier))
    }
}

extension SemanticContainerPredicate: Codable where Value: Codable {
    private enum Kind: String, Codable, CaseIterable {
        case label, value, identifier
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
        case .identifier:
            self = .identifier(try container.decode(StringMatch<Value>.self, forKey: .match))
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
        case .identifier(let match):
            try container.encode(Kind.identifier, forKey: .kind)
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
        case .identifier(let match):
            return ScoreDescription.call("semantic", ["identifier=\(match)"])
        }
    }
}

private extension SemanticContainerPredicate where Value == String {
    func matches(_ facts: ContainerPredicateFacts) -> Bool {
        guard facts.type == .semanticGroup else { return false }
        switch self {
        case .label(let match):
            return match.matches(optional: facts.label)
        case .value(let match):
            return match.matches(optional: facts.value)
        case .identifier(let match):
            return match.matches(optional: facts.identifier)
        }
    }
}

public enum ContainerPredicateCheck<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    case type(AccessibilityContainerKind)
    case semantic(SemanticContainerPredicate<Value>)
    case rowCount(Int)
    case columnCount(Int)
    case modalBoundary(Bool)

    private enum Kind: String, Codable, CaseIterable {
        case type, semantic, rowCount, columnCount, modalBoundary
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, type, semantic, value
    }

    public var hasPredicates: Bool {
        switch self {
        case .type, .rowCount, .columnCount, .modalBoundary:
            return true
        case .semantic(let predicate):
            return predicate.hasPredicates
        }
    }

    public var invalidEmptyPayloadDescription: String? {
        switch self {
        case .semantic(let predicate):
            return predicate.invalidPayloadDescription
        case .rowCount(let rowCount) where rowCount < 0:
            return "container rowCount must be non-negative"
        case .columnCount(let columnCount) where columnCount < 0:
            return "container columnCount must be non-negative"
        case .type, .rowCount, .columnCount, .modalBoundary:
            return nil
        }
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> ContainerPredicateCheck<NewValue> {
        switch self {
        case .type(let type):
            return .type(type)
        case .semantic(let predicate):
            return try .semantic(predicate.map(transform))
        case .rowCount(let count):
            return .rowCount(count)
        case .columnCount(let count):
            return .columnCount(count)
        case .modalBoundary(let required):
            return .modalBoundary(required)
        }
    }

    fileprivate func matches(_ facts: ContainerPredicateFacts) -> Bool where Value == String {
        switch self {
        case .type(let type):
            return facts.type == type
        case .semantic(let predicate):
            return predicate.matches(facts)
        case .rowCount(let rowCount):
            return facts.type == .dataTable && facts.rowCount == rowCount
        case .columnCount(let columnCount):
            return facts.type == .dataTable && facts.columnCount == columnCount
        case .modalBoundary(let required):
            return facts.isModalBoundary == required
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
        case .semantic:
            self = .semantic(try container.decode(SemanticContainerPredicate<Value>.self, forKey: .semantic))
        case .rowCount:
            self = .rowCount(try container.decode(Int.self, forKey: .value))
        case .columnCount:
            self = .columnCount(try container.decode(Int.self, forKey: .value))
        case .modalBoundary:
            self = .modalBoundary(try container.decode(Bool.self, forKey: .value))
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
        }
    }
}

extension ContainerPredicateCheck: CustomStringConvertible {
    public var description: String {
        switch self {
        case .type(let type):
            return "type=\(type)"
        case .semantic(let predicate):
            return "semantic=\(predicate)"
        case .rowCount(let rowCount):
            return "rowCount=\(rowCount)"
        case .columnCount(let columnCount):
            return "columnCount=\(columnCount)"
        case .modalBoundary(let required):
            return "modal=\(required)"
        }
    }
}

public struct ContainerPredicate: Codable, Sendable, Equatable, Hashable {
    public let checks: [ContainerPredicateCheck<String>]

    public init(_ checks: [ContainerPredicateCheck<String>]) {
        self.checks = checks
        if let description = invalidEmptyPayloadDescription {
            preconditionFailure(description)
        }
    }

    public init(
        _ checks: ContainerPredicateCheck<String>...
    ) {
        self.init(checks)
    }

    public init(identifier: String) {
        self.init(.semantic(.identifier(identifier)))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public var hasPredicates: Bool {
        checks.contains { $0.hasPredicates }
    }

    public var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : "container predicate must include at least one field"
    }

    public func matches(_ facts: ContainerPredicateFacts) -> Bool {
        hasPredicates && checks.allSatisfy { $0.matches(facts) }
    }

    public static func identifier(_ identifier: String) -> ContainerPredicate {
        ContainerPredicate(.semantic(.identifier(identifier)))
    }

    public static func identifier(_ identifier: StringMatch<String>) -> ContainerPredicate {
        ContainerPredicate(.semantic(.identifier(identifier)))
    }

    public static func label(_ label: String) -> ContainerPredicate {
        ContainerPredicate(.semantic(.label(label)))
    }

    public static func label(_ label: StringMatch<String>) -> ContainerPredicate {
        ContainerPredicate(.semantic(.label(label)))
    }

    public static func value(_ value: String) -> ContainerPredicate {
        ContainerPredicate(.semantic(.value(value)))
    }

    public static func value(_ value: StringMatch<String>) -> ContainerPredicate {
        ContainerPredicate(.semantic(.value(value)))
    }

    public static func type(_ type: AccessibilityContainerKind) -> ContainerPredicate {
        ContainerPredicate(.type(type))
    }

    public static func semantic(_ predicate: SemanticContainerPredicate<String>) -> ContainerPredicate {
        ContainerPredicate(.semantic(predicate))
    }

    public static var semanticGroup: ContainerPredicate { .type(.semanticGroup) }
    public static var list: ContainerPredicate { .type(.list) }
    public static var landmark: ContainerPredicate { .type(.landmark) }
    public static var tabBar: ContainerPredicate { .type(.tabBar) }
    public static var scrollable: ContainerPredicate { .type(.scrollable) }

    public static func dataTable(rowCount: Int? = nil, columnCount: Int? = nil) -> ContainerPredicate {
        var checks: [ContainerPredicateCheck<String>] = [.type(.dataTable)]
        if let rowCount { checks.append(.rowCount(rowCount)) }
        if let columnCount { checks.append(.columnCount(columnCount)) }
        return ContainerPredicate(checks)
    }

    public static var modalBoundary: ContainerPredicate {
        ContainerPredicate(.modalBoundary(true))
    }

    public static func matching(_ checks: ContainerPredicateCheck<String>...) -> ContainerPredicate {
        ContainerPredicate(checks)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.checks = try container.decodeIfPresent([ContainerPredicateCheck<String>].self, forKey: .checks) ?? []
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
    public let checks: [ContainerPredicateCheck<StringExpr>]

    public init(_ checks: [ContainerPredicateCheck<StringExpr>]) {
        self.checks = checks
        if let description = invalidEmptyPayloadDescription {
            preconditionFailure(description)
        }
    }

    public init(_ checks: ContainerPredicateCheck<StringExpr>...) {
        self.init(checks)
    }

    public init(identifier: String) {
        self.init(.semantic(.identifier(identifier)))
    }

    public init(_ predicate: ContainerPredicate) {
        self.init(predicate.checks.map { $0.map { .literal($0) } })
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public var hasPredicates: Bool {
        checks.contains { $0.hasPredicates }
    }

    public var invalidEmptyPayloadDescription: String? {
        if let description = checks.lazy.compactMap(\.invalidEmptyPayloadDescription).first {
            return description
        }
        return hasPredicates ? nil : "container predicate must include at least one field"
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ContainerPredicate {
        try ContainerPredicate(checks.map { try $0.map { try $0.resolve(in: environment) } })
    }

    public static func identifier(_ identifier: StringExpr) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.identifier(identifier)))
    }

    public static func identifier(_ identifier: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.identifier(identifier)))
    }

    public static func identifier(_ identifier: String) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.identifier(identifier)))
    }

    public static func label(_ label: StringExpr) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.label(label)))
    }

    public static func label(_ label: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.label(label)))
    }

    public static func label(_ label: String) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.label(label)))
    }

    public static func value(_ value: StringExpr) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.value(value)))
    }

    public static func value(_ value: StringMatch<StringExpr>) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.value(value)))
    }

    public static func value(_ value: String) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(.value(value)))
    }

    public static func type(_ type: AccessibilityContainerKind) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.type(type))
    }

    public static func semantic(_ predicate: SemanticContainerPredicate<StringExpr>) -> ContainerPredicateExpr {
        ContainerPredicateExpr(.semantic(predicate))
    }

    public static var semanticGroup: ContainerPredicateExpr { .type(.semanticGroup) }
    public static var list: ContainerPredicateExpr { .type(.list) }
    public static var landmark: ContainerPredicateExpr { .type(.landmark) }
    public static var tabBar: ContainerPredicateExpr { .type(.tabBar) }
    public static var scrollable: ContainerPredicateExpr { .type(.scrollable) }

    public static func dataTable(rowCount: Int? = nil, columnCount: Int? = nil) -> ContainerPredicateExpr {
        var checks: [ContainerPredicateCheck<StringExpr>] = [.type(.dataTable)]
        if let rowCount { checks.append(.rowCount(rowCount)) }
        if let columnCount { checks.append(.columnCount(columnCount)) }
        return ContainerPredicateExpr(checks)
    }

    public static var modalBoundary: ContainerPredicateExpr {
        ContainerPredicateExpr(.modalBoundary(true))
    }

    public static func matching(_ checks: ContainerPredicateCheck<StringExpr>...) -> ContainerPredicateExpr {
        ContainerPredicateExpr(checks)
    }
}

extension ContainerPredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", checks.map(\.description))
    }
}

public struct ContainerPredicateFacts: Sendable, Equatable, Hashable {
    public let type: AccessibilityContainerKind
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let rowCount: Int?
    public let columnCount: Int?
    public let isModalBoundary: Bool

    public init(
        type: AccessibilityContainerKind,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        rowCount: Int? = nil,
        columnCount: Int? = nil,
        isModalBoundary: Bool = false
    ) {
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.isModalBoundary = isModalBoundary
    }
}

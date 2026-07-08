import Foundation

// MARK: - Container Predicates

public struct ContainerIdentifier: RawRepresentable, Codable, Hashable, Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        guard let normalized = Self.normalized(rawValue) else {
            preconditionFailure("ContainerIdentifier must not be empty")
        }
        self = normalized
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(validating value: String) throws {
        guard let normalized = Self.normalized(value) else {
            throw HeistExpressionError.emptyReference("container identifier")
        }
        self = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let normalized = Self.normalized(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "container identifier must not be empty"
            )
        }
        self = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func normalized(_ value: String) -> ContainerIdentifier? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ContainerIdentifier(unchecked: trimmed)
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ContainerIdentifier: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

extension ContainerIdentifier {
    static func decode<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> ContainerIdentifier {
        let value = try container.decode(String.self, forKey: key)
        guard let normalized = normalized(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "container identifier must not be empty"
            )
        }
        return normalized
    }
}

public struct ContainerPredicate: Codable, Sendable, Equatable, Hashable {
    public let identifier: ContainerIdentifier

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case identifier
    }

    public init(identifier: ContainerIdentifier) {
        self.identifier = identifier
    }

    public init(identifier: String) {
        self.init(identifier: ContainerIdentifier(rawValue: identifier))
    }

    public static func identifier(_ identifier: String) -> ContainerPredicate {
        ContainerPredicate(identifier: identifier)
    }

    public func matches(identifier candidate: String?) -> Bool {
        guard let candidate else { return false }
        return ElementPredicate.stringEquals(candidate, identifier.rawValue)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(identifier: try ContainerIdentifier.decode(from: container, forKey: .identifier))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
    }
}

extension ContainerPredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", ["identifier=\(ScoreDescription.quoted(identifier.rawValue))"])
    }
}

public struct ContainerPredicateExpr: Codable, Sendable, Equatable, Hashable {
    public let identifier: StringExpr

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case identifier
    }

    public init(identifier: StringExpr) {
        self.identifier = identifier
    }

    public init(identifier: String) {
        self.identifier = .literal(identifier)
    }

    public init(_ predicate: ContainerPredicate) {
        self.identifier = .literal(predicate.identifier.rawValue)
    }

    public static func identifier(_ identifier: StringExpr) -> ContainerPredicateExpr {
        ContainerPredicateExpr(identifier: identifier)
    }

    public static func identifier(_ identifier: String) -> ContainerPredicateExpr {
        ContainerPredicateExpr(identifier: identifier)
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ContainerPredicate {
        try ContainerPredicate(identifier: ContainerIdentifier(validating: identifier.resolve(in: environment)))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "container predicate expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(StringExpr.self, forKey: .identifier)
        if identifier.stringMatchLiteralIsEmpty == true {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: container,
                debugDescription: "container identifier must not be empty"
            )
        }
        self.init(identifier: identifier)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
    }
}

extension ContainerPredicateExpr: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("container", ["identifier=\(identifier.description)"])
    }
}

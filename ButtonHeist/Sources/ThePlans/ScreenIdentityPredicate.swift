import Foundation

// MARK: - Screen Identity Predicates

public struct ScreenIdentityId: RawRepresentable, Codable, Hashable, Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        guard let normalized = Self.normalized(rawValue) else {
            preconditionFailure("ScreenIdentityId must not be empty")
        }
        self = normalized
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(validating value: String) throws {
        guard let normalized = Self.normalized(value) else {
            throw HeistExpressionError.emptyReference("screen identity")
        }
        self = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let normalized = Self.normalized(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "screen identity id must not be empty"
            )
        }
        self = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func normalized(_ value: String) -> ScreenIdentityId? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ScreenIdentityId(unchecked: trimmed)
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ScreenIdentityId: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

extension ScreenIdentityId {
    static func decode<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> ScreenIdentityId {
        let value = try container.decode(String.self, forKey: key)
        guard let normalized = normalized(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "screen identity id must not be empty"
            )
        }
        return normalized
    }
}

public enum ScreenIdentityPredicate: Codable, Sendable, Equatable, Hashable {
    case id(ScreenIdentityId)
    case header(StringMatch<String>)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, id, header
    }

    public init(id: String) {
        self = .id(ScreenIdentityId(rawValue: id))
    }

    public init(header: StringMatch<String>) {
        self = .header(header)
    }

    public init(header: String) {
        self = .header(.exact(header))
    }

    public func matches(screenId: String?, header: String?) -> Bool {
        switch self {
        case .id(let expected):
            return screenId == expected.rawValue
        case .header(let expected):
            return expected.matches(optional: header)
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try container.decodeIfPresent(String.self, forKey: .type),
           type != AccessibilityPredicateContract.StateWireType.screen.rawValue {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "screen predicate type must be \"screen\""
            )
        }

        let hasId = container.contains(.id)
        let hasHeader = container.contains(.header)
        switch (hasId, hasHeader) {
        case (true, false):
            self = .id(try ScreenIdentityId.decode(from: container, forKey: .id))
        case (false, true):
            self = .header(try container.decode(StringMatch<String>.self, forKey: .header))
        case (true, true):
            throw DecodingError.dataCorruptedError(
                forKey: .header,
                in: container,
                debugDescription: "screen predicate accepts either id or header, not both"
            )
        case (false, false):
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "screen predicate requires id or header"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id):
            try container.encode(id, forKey: .id)
        case .header(let header):
            try container.encode(header, forKey: .header)
        }
    }
}

extension ScreenIdentityPredicate: CustomStringConvertible {
    public var description: String {
        switch self {
        case .id(let id):
            return ScoreDescription.call("screen", ["id=\(ScoreDescription.quoted(id.rawValue))"])
        case .header(let header):
            return ScoreDescription.call("screen", ["header=\(ScoreDescription.stringMatch(header))"])
        }
    }
}

public enum ScreenIdentityPredicateExpr: Codable, Sendable, Equatable, Hashable {
    case id(StringExpr)
    case header(StringMatch<StringExpr>)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, id, header
    }

    public init(_ predicate: ScreenIdentityPredicate) {
        switch predicate {
        case .id(let id):
            self = .id(.literal(id.rawValue))
        case .header(let header):
            self = .header(header.map(StringExpr.literal))
        }
    }

    public init(id: StringExpr) {
        self = .id(id)
    }

    public init(id: String) {
        self = .id(.literal(id))
    }

    public init(header: StringMatch<StringExpr>) {
        self = .header(header)
    }

    public init(header: StringExpr) {
        self = .header(.exact(header))
    }

    public init(header: String) {
        self = .header(.exact(.literal(header)))
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ScreenIdentityPredicate {
        switch self {
        case .id(let id):
            return .id(try ScreenIdentityId(validating: id.resolve(in: environment)))
        case .header(let header):
            return .header(try header.resolve(in: environment))
        }
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "screen predicate expression")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let type = try container.decodeIfPresent(String.self, forKey: .type),
           type != AccessibilityPredicateContract.StateWireType.screen.rawValue {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "screen predicate expression type must be \"screen\""
            )
        }

        let hasId = container.contains(.id)
        let hasHeader = container.contains(.header)
        switch (hasId, hasHeader) {
        case (true, false):
            let id = try container.decode(StringExpr.self, forKey: .id)
            if id.stringMatchLiteralIsEmpty == true {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "screen identity id must not be empty"
                )
            }
            self = .id(id)
        case (false, true):
            self = .header(try container.decode(StringMatch<StringExpr>.self, forKey: .header))
        case (true, true):
            throw DecodingError.dataCorruptedError(
                forKey: .header,
                in: container,
                debugDescription: "screen predicate expression accepts either id or header, not both"
            )
        case (false, false):
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "screen predicate expression requires id or header"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .id(let id):
            try container.encode(id, forKey: .id)
        case .header(let header):
            try container.encode(header, forKey: .header)
        }
    }
}

extension ScreenIdentityPredicateExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .id(let id):
            return ScoreDescription.call("screen", ["id=\(id.description)"])
        case .header(let header):
            return ScoreDescription.call("screen", ["header=\(header.description)"])
        }
    }
}

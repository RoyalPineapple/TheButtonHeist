import Foundation

// MARK: - String Expressions

public enum StringExpr: Codable, Sendable, Equatable, Hashable {
    case literal(String)
    case ref(HeistReferenceName)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    public init(_ literal: String) {
        self = .literal(literal)
    }

    public init(ref: HeistReferenceName) throws {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HeistExpressionError.emptyReference("string") }
        self = .ref(trimmed)
    }

    public init(from decoder: Decoder) throws {
        if let literal = try? decoder.singleValueContainer().decode(String.self) {
            self = .literal(literal)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string expression")
        let reference = try container.decode(String.self, forKey: .ref)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .ref,
                in: container,
                debugDescription: "string reference must not be empty"
            )
        }
        self = .ref(reference)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .literal(let literal):
            var container = encoder.singleValueContainer()
            try container.encode(literal)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> String {
        switch self {
        case .literal(let literal):
            return literal
        case .ref(let reference):
            guard let string = environment.strings[reference] else {
                throw HeistExpressionError.unresolvedStringReference(reference)
            }
            return string
        }
    }
}

extension StringExpr: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .literal(value)
    }
}

extension StringExpr: CustomStringConvertible {
    public var description: String {
        switch self {
        case .literal(let literal):
            return ScoreDescription.quoted(literal)
        case .ref(let reference):
            return ScoreDescription.call("stringRef", [ScoreDescription.quoted(reference)])
        }
    }
}

extension StringExpr: StringMatchPayload {
    public var stringMatchLiteralIsEmpty: Bool? {
        switch self {
        case .literal(let value):
            return value.isEmpty
        case .ref:
            return nil
        }
    }
}

extension StringMatch where Value == StringExpr {
    public static func literal(_ value: String) -> StringMatch<StringExpr> {
        .exact(.literal(value))
    }

    public static func ref(_ reference: HeistReferenceName) -> StringMatch<StringExpr> {
        .exact(.ref(reference))
    }

    func resolve(in environment: HeistExecutionEnvironment) throws -> StringMatch<String> {
        let resolved = try map { try $0.resolve(in: environment) }
        if resolved.hasInvalidEmptyBroadLiteral {
            throw HeistExpressionError.invalidStringMatch(mode: resolved.mode.rawValue)
        }
        return resolved
    }
}

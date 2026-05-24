import Foundation

public struct SchemaValidationError: Error, LocalizedError, Equatable, Sendable {
    public let field: String
    public let observed: String
    public let expected: String

    public init(field: String, observed: String, expected: String) {
        self.field = field
        self.observed = observed
        self.expected = expected
    }

    public init(field: String, observed value: Any?, expected: String) {
        self.init(
            field: field,
            observed: Self.observedDescription(value),
            expected: expected
        )
    }

    public var message: String {
        "schema validation failed for \(field): observed \(observed); expected \(expected)"
    }

    public var errorDescription: String? { message }

    public static func expectedEnum<E>(_ type: E.Type) -> String where E: CaseIterable & RawRepresentable, E.RawValue == String {
        expectedEnumValues(type.allCases.map(\.rawValue))
    }

    public static func expectedEnumValues(_ values: [String]) -> String {
        "enum one of \(values.joined(separator: ", "))"
    }

    public static func observedDescription(_ value: Any?) -> String {
        guard let value else { return "missing" }
        if value is NSNull { return "null" }
        if let value = value as? Bool { return "boolean \(value)" }
        if let value = value as? Int { return "integer \(value)" }
        if let value = value as? Double { return "number \(Self.formatNumber(value))" }
        if let value = value as? String { return "string \"\(value)\"" }
        if let value = value as? [Any] { return "array count \(value.count)" }
        if value is [String: Any] { return "object" }
        return String(describing: type(of: value))
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.1f", value)
        }
        return String(value)
    }
}

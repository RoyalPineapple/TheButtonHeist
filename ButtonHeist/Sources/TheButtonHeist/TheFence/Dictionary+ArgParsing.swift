import Foundation
import TheScore

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
        "enum one of \(type.allCases.map(\.rawValue).joined(separator: ", "))"
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

/// Type-safe accessors for `[String: Any]` dictionaries from CLI/MCP argument parsing.
/// Converts loosely-typed JSON values (String, Int, Double, Bool) at the system boundary.
extension Dictionary where Key == String, Value == Any {

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func integer(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? Double { return Int(value) }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func boolean(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? Int { return value != 0 }
        if let value = self[key] as? String { return value == "true" || value == "1" }
        return nil
    }

    func number(_ key: String) -> Double? {
        number(self[key])
    }

    func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    func unitPoint(_ key: String) -> UnitPoint? {
        guard let dictionary = self[key] as? [String: Any],
              let x = dictionary.number("x"),
              let y = dictionary.number("y") else { return nil }
        return UnitPoint(x: x, y: y)
    }

    func schemaString(_ key: String) throws -> String? {
        guard let value = self[key] else { return nil }
        guard let string = value as? String else {
            throw SchemaValidationError(field: key, observed: value, expected: "string")
        }
        return string
    }

    func requiredSchemaString(_ key: String) throws -> String {
        guard let value = try schemaString(key) else {
            throw SchemaValidationError(field: key, observed: nil, expected: "string")
        }
        return value
    }

    func schemaInteger(_ key: String) throws -> Int? {
        guard let value = self[key] else { return nil }
        if let integer = integer(key) { return integer }
        throw SchemaValidationError(field: key, observed: value, expected: "integer")
    }

    func requiredSchemaInteger(_ key: String) throws -> Int {
        guard let value = try schemaInteger(key) else {
            throw SchemaValidationError(field: key, observed: nil, expected: "integer")
        }
        return value
    }

    func schemaBoolean(_ key: String) throws -> Bool? {
        guard let value = self[key] else { return nil }
        if let boolean = boolean(key) { return boolean }
        throw SchemaValidationError(field: key, observed: value, expected: "boolean")
    }

    func schemaNumber(_ key: String) throws -> Double? {
        guard let value = self[key] else { return nil }
        if let number = number(value) { return number }
        throw SchemaValidationError(field: key, observed: value, expected: "number")
    }

    func requiredSchemaNumber(_ key: String) throws -> Double {
        guard let value = try schemaNumber(key) else {
            throw SchemaValidationError(field: key, observed: nil, expected: "number")
        }
        return value
    }

    func schemaStringArray(_ key: String) throws -> [String]? {
        guard let value = self[key] else { return nil }
        guard let array = value as? [Any] else {
            throw SchemaValidationError(field: key, observed: value, expected: "array of strings")
        }
        var strings: [String] = []
        strings.reserveCapacity(array.count)
        for (index, item) in array.enumerated() {
            guard let string = item as? String else {
                throw SchemaValidationError(field: "\(key)[\(index)]", observed: item, expected: "string")
            }
            strings.append(string)
        }
        return strings
    }

    func schemaDictionaryArray(_ key: String) throws -> [[String: Any]]? {
        guard let value = self[key] else { return nil }
        guard let array = value as? [Any] else {
            throw SchemaValidationError(field: key, observed: value, expected: "array of objects")
        }
        var dictionaries: [[String: Any]] = []
        dictionaries.reserveCapacity(array.count)
        for (index, item) in array.enumerated() {
            guard let dictionary = item as? [String: Any] else {
                throw SchemaValidationError(field: "\(key)[\(index)]", observed: item, expected: "object")
            }
            dictionaries.append(dictionary)
        }
        return dictionaries
    }

    func requiredSchemaDictionaryArray(_ key: String) throws -> [[String: Any]] {
        guard let array = try schemaDictionaryArray(key) else {
            throw SchemaValidationError(field: key, observed: nil, expected: "array of objects")
        }
        return array
    }

    func schemaUnitPoint(_ key: String) throws -> UnitPoint? {
        guard let value = self[key] else { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw SchemaValidationError(field: key, observed: value, expected: "object with numeric x and y")
        }
        guard let x = try dictionary.schemaNumber("x") else {
            throw SchemaValidationError(field: "\(key).x", observed: nil, expected: "number")
        }
        guard let y = try dictionary.schemaNumber("y") else {
            throw SchemaValidationError(field: "\(key).y", observed: nil, expected: "number")
        }
        return UnitPoint(x: x, y: y)
    }

    func schemaEnum<E>(
        _ key: String,
        as type: E.Type,
        normalizedBy normalize: (String) -> String = { $0 }
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else { return nil }
        guard let value = E(rawValue: normalize(rawValue)) else {
            throw SchemaValidationError(
                field: key,
                observed: rawValue as Any,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        return value
    }

    func requiredSchemaEnum<E>(
        _ key: String,
        as type: E.Type,
        normalizedBy normalize: (String) -> String = { $0 }
    ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else {
            throw SchemaValidationError(
                field: key,
                observed: nil,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        guard let value = E(rawValue: normalize(rawValue)) else {
            throw SchemaValidationError(
                field: key,
                observed: rawValue as Any,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        return value
    }
}

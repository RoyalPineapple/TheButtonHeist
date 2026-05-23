import Foundation

import TheScore

extension TheFence {

    /// Typed JSON-compatible command arguments after external routing has selected a command.
    struct CommandArgumentEnvelope: CommandArgumentReadable, Sendable {
        let argumentValues: [String: CommandArgumentValue]
        let argumentFieldPrefix: String? = nil

        init(arguments: [String: Any]) throws {
            var values: [String: CommandArgumentValue] = [:]
            for (key, value) in arguments where key != "command" {
                values[key] = try CommandArgumentValue(value, field: key)
            }
            self.argumentValues = values
        }

        init(values: [String: CommandArgumentValue]) {
            self.argumentValues = values
        }

        func decodeEdgeRawDictionary() -> [String: Any] {
            rawValue
        }

    }

    struct CommandArgumentObject: CommandArgumentReadable, Sendable {
        let argumentValues: [String: CommandArgumentValue]
        let argumentFieldPrefix: String?

        init(values: [String: CommandArgumentValue], fieldPrefix: String) {
            self.argumentValues = values
            self.argumentFieldPrefix = fieldPrefix
        }
    }

    protocol CommandArgumentReadable: Sendable {
        var argumentValues: [String: CommandArgumentValue] { get }
        var argumentFieldPrefix: String? { get }
    }

    /// JSON-compatible command argument value used between routing and request decoding.
    enum CommandArgumentValue: Sendable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([CommandArgumentValue])
        case object([String: CommandArgumentValue])
        case null

        init(_ value: Any, field: String) throws {
            if value is NSNull {
                self = .null
            } else if let value = value as? Bool {
                self = .bool(value)
            } else if let value = value as? Int {
                self = .int(value)
            } else if let value = value as? Double {
                self = .double(value)
            } else if let value = value as? String {
                self = .string(value)
            } else if let array = value as? [Any] {
                self = .array(try array.enumerated().map { index, item in
                    try CommandArgumentValue(item, field: "\(field)[\(index)]")
                })
            } else if let object = value as? [String: Any] {
                var values: [String: CommandArgumentValue] = [:]
                for (key, value) in object {
                    values[key] = try CommandArgumentValue(value, field: "\(field).\(key)")
                }
                self = .object(values)
            } else if let number = value as? NSNumber {
                let doubleValue = number.doubleValue
                if let integer = Int(exactly: doubleValue) {
                    self = .int(integer)
                } else {
                    self = .double(doubleValue)
                }
            } else {
                throw SchemaValidationError(field: field, observed: value, expected: "JSON value")
            }
        }

        init(_ value: HeistValue) {
            switch value {
            case .string(let value):
                self = .string(value)
            case .int(let value):
                self = .int(value)
            case .double(let value):
                self = .double(value)
            case .bool(let value):
                self = .bool(value)
            case .array(let values):
                self = .array(values.map(CommandArgumentValue.init))
            case .object(let values):
                self = .object(values.mapValues(CommandArgumentValue.init))
            }
        }

        var rawValue: Any {
            switch self {
            case .string(let value):
                return value
            case .int(let value):
                return value
            case .double(let value):
                return value
            case .bool(let value):
                return value
            case .array(let values):
                return values.map(\.rawValue)
            case .object(let values):
                return values.mapValues(\.rawValue)
            case .null:
                return NSNull()
            }
        }

        var integerValue: Int? {
            switch self {
            case .int(let value):
                return value
            case .double(let value) where value.isFinite:
                return Int(exactly: value)
            default:
                return nil
            }
        }

        var numberValue: Double? {
            switch self {
            case .int(let value):
                return Double(value)
            case .double(let value) where value.isFinite:
                return value
            default:
                return nil
            }
        }
    }
}

/// Strict typed accessors for command arguments after command routing.
/// This keeps raw dictionaries at public decode edges while preserving the
/// same field-qualified diagnostics as the old dictionary helpers.
extension TheFence.CommandArgumentReadable {
    var keys: Dictionary<String, TheFence.CommandArgumentValue>.Keys {
        argumentValues.keys
    }

    var rawValue: [String: Any] {
        argumentValues.mapValues(\.rawValue)
    }

    func string(_ key: String) -> String? {
        guard case .string(let value) = argumentValues[key] else { return nil }
        return value
    }

    func observedValue(for key: String) -> Any? {
        argumentValues[key]?.rawValue
    }

    func schemaInteger(_ key: String) throws -> Int? {
        guard let value = argumentValues[key] else { return nil }
        guard let integer = value.integerValue else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "integer")
        }
        return integer
    }

    func schemaNonNegativeInteger(_ key: String) throws -> Int? {
        guard let integer = try schemaInteger(key) else { return nil }
        guard integer >= 0 else {
            throw SchemaValidationError(field: field(key), observed: integer, expected: "integer >= 0")
        }
        return integer
    }

    func schemaString(_ key: String) throws -> String? {
        guard let value = argumentValues[key] else { return nil }
        guard case .string(let string) = value else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "string")
        }
        return string
    }

    func requiredSchemaString(_ key: String) throws -> String {
        guard let value = try schemaString(key) else {
            throw SchemaValidationError(field: field(key), observed: nil, expected: "string")
        }
        return value
    }

    func schemaBoolean(_ key: String) throws -> Bool? {
        guard let value = argumentValues[key] else { return nil }
        guard case .bool(let bool) = value else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "boolean")
        }
        return bool
    }

    func schemaNumber(_ key: String) throws -> Double? {
        guard let value = argumentValues[key] else { return nil }
        guard let number = value.numberValue else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "number")
        }
        return number
    }

    func schemaStringArray(_ key: String) throws -> [String]? {
        guard let value = argumentValues[key] else { return nil }
        guard case .array(let array) = value else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "array of strings")
        }
        return try array.enumerated().map { index, item in
            guard case .string(let string) = item else {
                throw SchemaValidationError(
                    field: "\(field(key))[\(index)]",
                    observed: item.rawValue,
                    expected: "string"
                )
            }
            return string
        }
    }

    func schemaDictionary(_ key: String) throws -> TheFence.CommandArgumentObject? {
        guard let value = argumentValues[key] else { return nil }
        guard case .object(let object) = value else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "object")
        }
        return TheFence.CommandArgumentObject(values: object, fieldPrefix: field(key))
    }

    func schemaEnum<E>(
        _ key: String,
        as type: E.Type,
        normalizedBy normalize: (String) -> String = { $0 }
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else { return nil }
        guard let value = E(rawValue: normalize(rawValue)) else {
            throw SchemaValidationError(
                field: field(key),
                observed: rawValue as Any,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        return value
    }

    func field(_ key: String) -> String {
        guard let argumentFieldPrefix else { return key }
        return "\(argumentFieldPrefix).\(key)"
    }
}

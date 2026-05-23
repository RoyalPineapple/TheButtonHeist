import Foundation

import TheScore

extension TheFence {

    /// Typed JSON-compatible command arguments after external routing has selected a command.
    struct CommandArgumentEnvelope: Sendable {
        private let values: [String: CommandArgumentValue]

        init(arguments: [String: Any]) throws {
            var values: [String: CommandArgumentValue] = [:]
            for (key, value) in arguments where key != "command" {
                values[key] = try CommandArgumentValue(value, field: key)
            }
            self.values = values
        }

        init(values: [String: CommandArgumentValue]) {
            self.values = values
        }

        var keys: Dictionary<String, CommandArgumentValue>.Keys {
            values.keys
        }

        func string(_ key: String) -> String? {
            guard case .string(let value) = values[key] else { return nil }
            return value
        }

        func schemaString(_ key: String) throws -> String? {
            guard let value = values[key] else { return nil }
            guard case .string(let string) = value else {
                throw SchemaValidationError(field: key, observed: value.rawValue, expected: "string")
            }
            return string
        }

        func schemaNonNegativeInteger(_ key: String) throws -> Int? {
            guard let value = values[key] else { return nil }
            let integer: Int
            switch value {
            case .int(let intValue):
                integer = intValue
            case .double(let doubleValue) where doubleValue.isFinite:
                guard let exactInteger = Int(exactly: doubleValue) else {
                    throw SchemaValidationError(field: key, observed: value.rawValue, expected: "integer")
                }
                integer = exactInteger
            default:
                throw SchemaValidationError(field: key, observed: value.rawValue, expected: "integer")
            }
            guard integer >= 0 else {
                throw SchemaValidationError(field: key, observed: integer, expected: "integer >= 0")
            }
            return integer
        }

        func schemaStringArray(_ key: String) throws -> [String]? {
            guard let value = values[key] else { return nil }
            guard case .array(let array) = value else {
                throw SchemaValidationError(field: key, observed: value.rawValue, expected: "array of strings")
            }
            return try array.enumerated().map { index, item in
                guard case .string(let string) = item else {
                    throw SchemaValidationError(
                        field: "\(key)[\(index)]",
                        observed: item.rawValue,
                        expected: "string"
                    )
                }
                return string
            }
        }

        func decodeEdgeRawDictionary() -> [String: Any] {
            values.mapValues(\.rawValue)
        }

        func observedValue(for key: String) -> Any? {
            values[key]?.rawValue
        }
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
    }
}

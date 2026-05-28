import Foundation

import TheScore

extension TheFence {

    /// Typed JSON-encodable command arguments after external routing has selected a command.
    public struct CommandArgumentEnvelope: CommandArgumentReadable, Sendable {
        public let argumentValues: [String: HeistValue]
        let argumentFieldPrefix: String?

        init(arguments: [String: Any], droppingCommandKey: Bool = true) throws {
            var values: [String: HeistValue] = [:]
            for (key, value) in arguments where !droppingCommandKey || key != "command" {
                values[key] = try HeistValue(jsonValue: value, field: key)
            }
            self.argumentValues = values
            argumentFieldPrefix = nil
        }

        public init(values: [String: HeistValue], fieldPrefix: String? = nil) {
            self.argumentValues = values
            argumentFieldPrefix = fieldPrefix
        }

        func dropping(_ key: String) -> CommandArgumentEnvelope {
            var values = argumentValues
            values.removeValue(forKey: key)
            return CommandArgumentEnvelope(values: values, fieldPrefix: argumentFieldPrefix)
        }
    }

    public struct CommandArgumentObject: CommandArgumentReadable, Sendable {
        public let argumentValues: [String: HeistValue]
        let argumentFieldPrefix: String?

        public init(values: [String: HeistValue], fieldPrefix: String?) {
            self.argumentValues = values
            self.argumentFieldPrefix = fieldPrefix
        }
    }

    protocol CommandArgumentReadable: Sendable {
        var argumentValues: [String: HeistValue] { get }
        var argumentFieldPrefix: String? { get }
    }
}

extension HeistValue {
    init(jsonValue value: Any, field: String) throws {
        if value is NSNull {
            throw SchemaValidationError(field: field, observed: value, expected: "JSON scalar, array, or object")
        } else if let value = value as? Bool {
            self = .bool(value)
        } else if let value = value as? Int {
            self = .int(value)
        } else if let value = value as? Double {
            guard value.isFinite else {
                throw SchemaValidationError(field: field, observed: value, expected: "finite JSON number")
            }
            self = .double(value)
        } else if let value = value as? String {
            self = .string(value)
        } else if let array = value as? [Any] {
            self = .array(try array.enumerated().map { index, item in
                try HeistValue(jsonValue: item, field: "\(field)[\(index)]")
            })
        } else if let object = value as? [String: Any] {
            var values: [String: HeistValue] = [:]
            for (key, value) in object {
                values[key] = try HeistValue(jsonValue: value, field: "\(field).\(key)")
            }
            self = .object(values)
        } else if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            guard doubleValue.isFinite else {
                throw SchemaValidationError(field: field, observed: value, expected: "finite JSON number")
            }
            if let integer = Int(exactly: doubleValue) {
                self = .int(integer)
            } else {
                self = .double(doubleValue)
            }
        } else {
            throw SchemaValidationError(field: field, observed: value, expected: "JSON scalar, array, or object")
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

/// Strict typed accessors for command arguments after command routing.
/// This keeps raw dictionaries at public decode edges while preserving the
/// field-qualified diagnostics expected by the current command contract.
extension TheFence.CommandArgumentReadable {
    var keys: Dictionary<String, HeistValue>.Keys {
        argumentValues.keys
    }

    func string(_ key: String) -> String? {
        guard case .string(let value) = argumentValues[key] else { return nil }
        return value
    }

    func observedValue(for key: String) -> Any? {
        argumentValues[key]?.rawValue
    }

    func observedDescription(for key: String) -> String? {
        argumentValues[key].map { SchemaValidationError.observedDescription($0.rawValue) }
    }

    var observedDescription: String {
        "object"
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

    func requiredSchemaNumber(_ key: String) throws -> Double {
        guard let value = try schemaNumber(key) else {
            throw SchemaValidationError(field: field(key), observed: nil, expected: "number")
        }
        return value
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

    func schemaObjectArray(_ key: String) throws -> [TheFence.CommandArgumentObject]? {
        guard let value = argumentValues[key] else { return nil }
        guard case .array(let array) = value else {
            throw SchemaValidationError(field: field(key), observed: value.rawValue, expected: "array of objects")
        }
        return try array.enumerated().map { index, item in
            guard case .object(let object) = item else {
                throw SchemaValidationError(
                    field: "\(field(key))[\(index)]",
                    observed: item.rawValue,
                    expected: "object"
                )
            }
            return TheFence.CommandArgumentObject(values: object, fieldPrefix: "\(field(key))[\(index)]")
        }
    }

    func requiredSchemaObjectArray(_ key: String) throws -> [TheFence.CommandArgumentObject] {
        guard let array = try schemaObjectArray(key) else {
            throw SchemaValidationError(field: field(key), observed: nil, expected: "array of objects")
        }
        return array
    }

    func schemaUnitPoint(_ key: String) throws -> UnitPoint? {
        guard let value = argumentValues[key] else { return nil }
        guard case .object(let values) = value else {
            throw SchemaValidationError(
                field: field(key),
                observed: value.rawValue,
                expected: "object with numeric x and y"
            )
        }
        let object = TheFence.CommandArgumentObject(values: values, fieldPrefix: field(key))
        try object.rejectUnknownKeys(allowed: ["x", "y"], expected: "valid unit point field")
        guard let x = try object.schemaNumber("x") else {
            throw SchemaValidationError(field: object.field("x"), observed: nil, expected: "number")
        }
        guard let y = try object.schemaNumber("y") else {
            throw SchemaValidationError(field: object.field("y"), observed: nil, expected: "number")
        }
        guard (0...1).contains(x) else {
            throw SchemaValidationError(field: object.field("x"), observed: x, expected: "number in 0...1")
        }
        guard (0...1).contains(y) else {
            throw SchemaValidationError(field: object.field("y"), observed: y, expected: "number in 0...1")
        }
        return UnitPoint(x: x, y: y)
    }

    func rejectUnknownKeys(allowed: Set<String>, expected: String) throws {
        let unknownKeys = keys.filter { !allowed.contains($0) }.sorted()
        guard let unknownKey = unknownKeys.first else { return }
        throw SchemaValidationError(
            field: field(unknownKey),
            observed: argumentValues[unknownKey]?.rawValue,
            expected: expected
        )
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
        as type: E.Type
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else { return nil }
        guard let value = E(rawValue: rawValue) else {
            throw SchemaValidationError(
                field: field(key),
                observed: rawValue as Any,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        return value
    }

    func requiredSchemaEnum<E>(
        _ key: String,
        as type: E.Type
    ) throws -> E where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else {
            throw SchemaValidationError(
                field: field(key),
                observed: nil,
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        guard let value = E(rawValue: rawValue) else {
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

import Foundation

import TheScore

extension TheFence {

    /// Typed command arguments after external routing has selected a command.
    public struct CommandArgumentEnvelope: Sendable {
        public let argumentValues: [String: HeistValue]
        public let elementTarget: ElementTarget?
        let argumentFieldPrefix: String?

        public init(
            values: [String: HeistValue],
            elementTarget: ElementTarget? = nil,
            fieldPrefix: String? = nil
        ) {
            self.argumentValues = values
            self.elementTarget = elementTarget
            argumentFieldPrefix = fieldPrefix
        }

        func dropping(_ key: String) -> CommandArgumentEnvelope {
            var values = argumentValues
            values.removeValue(forKey: key)
            return CommandArgumentEnvelope(
                values: values,
                elementTarget: elementTarget,
                fieldPrefix: argumentFieldPrefix
            )
        }
    }
}

extension HeistValue {
    var schemaObservedDescription: String {
        switch self {
        case .string(let value):
            return "string \"\(value)\""
        case .int(let value):
            return "integer \(value)"
        case .double(let value):
            return "number \(Self.schemaFormatNumber(value))"
        case .bool(let value):
            return "boolean \(value)"
        case .array(let values):
            return "array count \(values.count)"
        case .object:
            return "object"
        }
    }

    private static func schemaFormatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.1f", value)
        }
        return String(value)
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
extension TheFence.CommandArgumentEnvelope {
    var keys: Dictionary<String, HeistValue>.Keys {
        argumentValues.keys
    }

    func string(_ key: String) -> String? {
        guard case .string(let value) = argumentValues[key] else { return nil }
        return value
    }

    func observedDescription(for key: String) -> String? {
        argumentValues[key]?.schemaObservedDescription
    }

    var observedDescription: String {
        "object"
    }

    func schemaInteger(_ key: String) throws -> Int? {
        guard let value = argumentValues[key] else { return nil }
        guard let integer = value.integerValue else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "integer")
        }
        return integer
    }

    func requiredSchemaInteger(_ key: String) throws -> Int {
        guard let integer = try schemaInteger(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "integer")
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
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "string")
        }
        return string
    }

    func schemaStringMatch(_ key: String) throws -> StringMatch<String>? {
        guard let value = argumentValues[key] else { return nil }
        guard case .object = value else {
            throw SchemaValidationError(
                field: field(key),
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and value"
            )
        }

        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(StringMatch<String>.self, from: data)
        } catch let error as DecodingError {
            throw stringMatchPayloadFailure(error, key: key, value: value)
        } catch {
            throw FenceError.invalidRequest(String(describing: error))
        }
    }

    func requiredSchemaString(_ key: String) throws -> String {
        guard let value = try schemaString(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "string")
        }
        return value
    }

    func schemaBoolean(_ key: String) throws -> Bool? {
        guard let value = argumentValues[key] else { return nil }
        guard case .bool(let bool) = value else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "boolean")
        }
        return bool
    }

    func schemaNumber(_ key: String) throws -> Double? {
        guard let value = argumentValues[key] else { return nil }
        guard let number = value.numberValue else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "number")
        }
        return number
    }

    func requiredSchemaNumber(_ key: String) throws -> Double {
        guard let value = try schemaNumber(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "number")
        }
        return value
    }

    func schemaStringArray(_ key: String) throws -> [String]? {
        guard let value = argumentValues[key] else { return nil }
        guard case .array(let array) = value else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "array of strings")
        }
        return try array.enumerated().map { index, item in
            guard case .string(let string) = item else {
                throw SchemaValidationError(
                    field: "\(field(key))[\(index)]",
                    observed: item.schemaObservedDescription,
                    expected: "string"
                )
            }
            return string
        }
    }

    func schemaObjectArray(_ key: String) throws -> [TheFence.CommandArgumentEnvelope]? {
        guard let value = argumentValues[key] else { return nil }
        guard case .array(let array) = value else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "array of objects")
        }
        return try array.enumerated().map { index, item in
            guard case .object(let object) = item else {
                throw SchemaValidationError(
                    field: "\(field(key))[\(index)]",
                    observed: item.schemaObservedDescription,
                    expected: "object"
                )
            }
            return TheFence.CommandArgumentEnvelope(values: object, fieldPrefix: "\(field(key))[\(index)]")
        }
    }

    func requiredSchemaObjectArray(_ key: String) throws -> [TheFence.CommandArgumentEnvelope] {
        guard let array = try schemaObjectArray(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "array of objects")
        }
        return array
    }

    func rejectUnknownKeys(allowed: Set<String>, expected: String) throws {
        let unknownKeys = keys.filter { !allowed.contains($0) }.sorted()
        guard let unknownKey = unknownKeys.first else { return }
        throw SchemaValidationError(
            field: field(unknownKey),
            observed: argumentValues[unknownKey]?.schemaObservedDescription ?? "missing",
            expected: expected
        )
    }

    func schemaDictionary(_ key: String) throws -> TheFence.CommandArgumentEnvelope? {
        guard let value = argumentValues[key] else { return nil }
        guard case .object(let object) = value else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "object")
        }
        return TheFence.CommandArgumentEnvelope(values: object, fieldPrefix: field(key))
    }

    func schemaEnum<E>(
        _ key: String,
        as type: E.Type
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        guard let rawValue = try schemaString(key) else { return nil }
        guard let value = E(rawValue: rawValue) else {
            throw SchemaValidationError(
                field: field(key),
                observed: "string \"\(rawValue)\"",
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
                observed: "missing",
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        guard let value = E(rawValue: rawValue) else {
            throw SchemaValidationError(
                field: field(key),
                observed: "string \"\(rawValue)\"",
                expected: SchemaValidationError.expectedEnum(type)
            )
        }
        return value
    }

    func field(_ key: String) -> String {
        guard let argumentFieldPrefix else { return key }
        return "\(argumentFieldPrefix).\(key)"
    }

    private func stringMatchPayloadFailure(_ error: DecodingError, key: String, value: HeistValue) -> Error {
        switch error {
        case .typeMismatch(let type, let context):
            return SchemaValidationError(
                field: field(key, codingPath: context.codingPath),
                observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription
                    ?? value.schemaObservedDescription,
                expected: expectedDescription(for: type)
            )
        case .valueNotFound(let type, let context):
            return SchemaValidationError(
                field: field(key, codingPath: context.codingPath),
                observed: "missing",
                expected: expectedDescription(for: type)
            )
        case .keyNotFound(let missingKey, let context):
            return SchemaValidationError(
                field: field(key, codingPath: context.codingPath + [missingKey]),
                observed: "missing",
                expected: "present"
            )
        case .dataCorrupted(let context):
            return SchemaValidationError(
                field: field(key, codingPath: context.codingPath),
                observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription ?? "invalid value",
                expected: context.debugDescription
            )
        @unknown default:
            return FenceError.invalidRequest(String(describing: error))
        }
    }

    private func field(_ key: String, codingPath: [CodingKey]) -> String {
        let suffix = codingPath.reduce(into: "") { path, codingKey in
            if let index = codingKey.intValue {
                path += "[\(index)]"
            } else if path.isEmpty {
                path = codingKey.stringValue
            } else {
                path += ".\(codingKey.stringValue)"
            }
        }
        guard !suffix.isEmpty else { return field(key) }
        return field("\(key).\(suffix)")
    }

    private func payloadValue(at codingPath: [CodingKey], in value: HeistValue) -> HeistValue? {
        codingPath.reduce(Optional(value)) { current, key in
            guard let current else { return nil }
            if let index = key.intValue {
                guard case .array(let values) = current, values.indices.contains(index) else { return nil }
                return values[index]
            }
            guard case .object(let values) = current else { return nil }
            return values[key.stringValue]
        }
    }

    private func expectedDescription(for type: Any.Type) -> String {
        switch type {
        case is String.Type:
            return "string"
        case is Bool.Type:
            return "boolean"
        case is Int.Type:
            return "integer"
        case is Double.Type:
            return "number"
        default:
            if String(describing: type).hasPrefix("Array<") {
                return "array"
            }
            return String(describing: type)
        }
    }

}

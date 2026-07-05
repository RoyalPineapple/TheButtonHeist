import Foundation
import ThePlans

import TheScore

extension TheFence {

    /// Typed command arguments after external routing has selected a command.
    @_spi(ButtonHeistTooling) public struct CommandArgumentEnvelope: Sendable {
        @_spi(ButtonHeistTooling) public let argumentValues: [String: HeistValue]
        let argumentFieldPrefix: String?

        @_spi(ButtonHeistTooling) public init(
            values: [String: HeistValue],
            fieldPrefix: String? = nil
        ) {
            self.argumentValues = values
            argumentFieldPrefix = fieldPrefix
        }

        func dropping(_ key: FenceParameterKey) -> CommandArgumentEnvelope {
            var values = argumentValues
            values.removeValue(forKey: key.rawValue)
            return CommandArgumentEnvelope(
                values: values,
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

enum HeistValuePayloadDataCorruptedHandling {
    case schemaValidation
    case invalidRequest
}

extension TheFence {
    enum HeistValuePayloadDecoder {
        static func decode<T: Decodable>(
            _ value: HeistValue,
            field rootField: String,
            as type: T.Type,
            includesRootInField: Bool = true,
            dataCorruptedHandling: HeistValuePayloadDataCorruptedHandling = .schemaValidation
        ) throws -> T {
            do {
                let data = try JSONEncoder().encode(value)
                return try JSONDecoder().decode(type, from: data)
            } catch let error as DecodingError {
                throw payloadFailure(
                    error,
                    value: value,
                    rootField: rootField,
                    includesRootInField: includesRootInField,
                    dataCorruptedHandling: dataCorruptedHandling
                )
            } catch {
                throw FenceError.invalidRequest(String(describing: error))
            }
        }

        private static func payloadFailure(
            _ error: DecodingError,
            value: HeistValue,
            rootField: String,
            includesRootInField: Bool,
            dataCorruptedHandling: HeistValuePayloadDataCorruptedHandling
        ) -> Error {
            switch error {
            case .typeMismatch(let expectedType, let context):
                return SchemaValidationError(
                    field: field(rootField, codingPath: context.codingPath, includesRoot: includesRootInField),
                    observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription
                        ?? value.schemaObservedDescription,
                    expected: expectedDescription(for: expectedType, fallback: context.debugDescription)
                )
            case .valueNotFound(_, let context):
                return SchemaValidationError(
                    field: field(rootField, codingPath: context.codingPath, includesRoot: includesRootInField),
                    observed: "missing",
                    expected: context.debugDescription
                )
            case .keyNotFound(let key, let context):
                return SchemaValidationError(
                    field: field(
                        rootField,
                        codingPath: context.codingPath + [key],
                        includesRoot: includesRootInField
                    ),
                    observed: "missing",
                    expected: "present"
                )
            case .dataCorrupted(let context):
                switch dataCorruptedHandling {
                case .schemaValidation:
                    return SchemaValidationError(
                        field: field(rootField, codingPath: context.codingPath, includesRoot: includesRootInField),
                        observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription
                            ?? "invalid value",
                        expected: context.debugDescription
                    )
                case .invalidRequest:
                    return FenceError.invalidRequest(context.debugDescription)
                }
            @unknown default:
                return FenceError.invalidRequest(String(describing: error))
            }
        }

        private static func field(
            _ rootField: String,
            codingPath: [CodingKey],
            includesRoot: Bool
        ) -> String {
            let suffix = codingPathString(codingPath)
            guard !suffix.isEmpty else { return rootField }
            guard includesRoot else { return suffix }
            if suffix.hasPrefix("[") {
                return "\(rootField)\(suffix)"
            }
            return "\(rootField).\(suffix)"
        }

        private static func codingPathString(_ codingPath: [CodingKey]) -> String {
            codingPath.reduce(into: "") { path, codingKey in
                if let index = codingKey.intValue {
                    path += "[\(index)]"
                } else if path.isEmpty {
                    path = codingKey.stringValue
                } else {
                    path += ".\(codingKey.stringValue)"
                }
            }
        }

        private static func payloadValue(at codingPath: [CodingKey], in value: HeistValue) -> HeistValue? {
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

        private static func expectedDescription(for type: Any.Type, fallback: String) -> String {
            switch type {
            case is String.Type:
                return "string"
            case is Bool.Type:
                return "boolean"
            case is Int.Type:
                return "integer"
            case is Double.Type, is Float.Type:
                return "number"
            default:
                return fallback
            }
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

    func contains(_ key: FenceParameterKey) -> Bool {
        argumentValues[key.rawValue] != nil
    }

    func value(for key: FenceParameterKey) -> HeistValue? {
        argumentValues[key.rawValue]
    }

    func value<Value>(_ parameter: FenceParameter<Value>) throws -> Value? {
        guard let value = value(for: parameter.key) else { return nil }
        return try parameter.decode(value, field: field(parameter.key))
    }

    func requiredValue<Value>(_ parameter: FenceParameter<Value>) throws -> Value {
        guard let value = try value(parameter) else {
            throw SchemaValidationError(
                field: field(parameter.key),
                observed: "missing",
                expected: parameter.expectedTypeDescription
            )
        }
        return value
    }

    func value<Value>(
        _ parameter: FenceParameter<Value>,
        defaultFrom descriptor: FenceCommandDescriptor
    ) throws -> Value {
        try value(parameter) ?? descriptor.requiredDefaultValue(for: parameter)
    }

    func nonNegativeValue(_ parameter: FenceParameter<Int>) throws -> Int? {
        guard let integer = try value(parameter) else { return nil }
        guard integer >= 0 else {
            throw SchemaValidationError(field: field(parameter.key), observed: integer, expected: "integer >= 0")
        }
        return integer
    }

    func nonEmptyValue(_ parameter: FenceParameter<String>) throws -> String {
        let value = try requiredValue(parameter)
        if value.isEmpty {
            throw SchemaValidationError(field: field(parameter.key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func optionalNonEmptyValue(_ parameter: FenceParameter<String>) throws -> String? {
        guard let value = try value(parameter) else { return nil }
        if value.isEmpty {
            throw SchemaValidationError(field: field(parameter.key), observed: "string \"\"", expected: "non-empty string")
        }
        return value
    }

    func string(_ key: FenceParameterKey) -> String? {
        guard case .string(let value) = value(for: key) else { return nil }
        return value
    }

    func observedDescription(for key: FenceParameterKey) -> String? {
        argumentValues[key.rawValue]?.schemaObservedDescription
    }

    func observedDescription(forUnknownKey key: String) -> String? {
        argumentValues[key]?.schemaObservedDescription
    }

    var observedDescription: String {
        "object"
    }

    func schemaInteger(_ key: FenceParameterKey) throws -> Int? {
        try value(FenceParameter<Int>.integer(key))
    }

    func requiredSchemaInteger(_ key: FenceParameterKey) throws -> Int {
        try requiredValue(FenceParameter<Int>.integer(key))
    }

    func schemaNonNegativeInteger(_ key: FenceParameterKey) throws -> Int? {
        guard let integer = try schemaInteger(key) else { return nil }
        guard integer >= 0 else {
            throw SchemaValidationError(field: field(key), observed: integer, expected: "integer >= 0")
        }
        return integer
    }

    func schemaString(_ key: FenceParameterKey) throws -> String? {
        try value(FenceParameter<String>.string(key))
    }

    func schemaStringMatch(_ key: FenceParameterKey) throws -> StringMatch<String>? {
        guard let value = value(for: key) else { return nil }
        guard case .object = value else {
            throw SchemaValidationError(
                field: field(key),
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and optional value"
            )
        }

        return try decodePayload(value, forKey: key, as: StringMatch<String>.self)
    }

    func schemaStringMatches(_ key: FenceParameterKey) throws -> [StringMatch<String>] {
        guard let value = value(for: key) else { return [] }
        switch value {
        case .object:
            guard let match = try schemaStringMatch(key) else { return [] }
            return [match]
        case .array(let values):
            for (index, value) in values.enumerated() {
                guard case .object = value else {
                    throw SchemaValidationError(
                        field: "\(field(key))[\(index)]",
                        observed: value.schemaObservedDescription,
                        expected: "StringMatch object with mode and optional value"
                    )
                }
            }
            return try decodePayload(value, forKey: key, as: [StringMatch<String>].self)
        default:
            throw SchemaValidationError(
                field: field(key),
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and optional value, or array of StringMatch objects"
            )
        }
    }

    func requiredSchemaString(_ key: FenceParameterKey) throws -> String {
        try requiredValue(FenceParameter<String>.string(key))
    }

    func schemaBoolean(_ key: FenceParameterKey) throws -> Bool? {
        try value(FenceParameter<Bool>.boolean(key))
    }

    func schemaNumber(_ key: FenceParameterKey) throws -> Double? {
        try value(FenceParameter<Double>.number(key))
    }

    func requiredSchemaNumber(_ key: FenceParameterKey) throws -> Double {
        try requiredValue(FenceParameter<Double>.number(key))
    }

    func schemaStringArray(_ key: FenceParameterKey) throws -> [String]? {
        guard let value = value(for: key) else { return nil }
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

    func schemaObjectArray(_ key: FenceParameterKey) throws -> [TheFence.CommandArgumentEnvelope]? {
        guard let value = value(for: key) else { return nil }
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

    func requiredSchemaObjectArray(_ key: FenceParameterKey) throws -> [TheFence.CommandArgumentEnvelope] {
        guard let array = try schemaObjectArray(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "array of objects")
        }
        return array
    }

    func rejectUnknownKeys(allowed: Set<FenceParameterKey>, expected: String) throws {
        let allowedRawValues = Set(allowed.map(\.rawValue))
        let unknownKeys = keys.filter { !allowedRawValues.contains($0) }.sorted()
        guard let unknownKey = unknownKeys.first else { return }
        throw SchemaValidationError(
            field: field(forUnknownKey: unknownKey),
            observed: argumentValues[unknownKey]?.schemaObservedDescription ?? "missing",
            expected: expected
        )
    }

    func schemaDictionary(_ key: FenceParameterKey) throws -> TheFence.CommandArgumentEnvelope? {
        guard let value = value(for: key) else { return nil }
        guard case .object(let object) = value else {
            throw SchemaValidationError(field: field(key), observed: value.schemaObservedDescription, expected: "object")
        }
        return TheFence.CommandArgumentEnvelope(values: object, fieldPrefix: field(key))
    }

    func schemaEnum<E>(
        _ key: FenceParameterKey,
        as type: E.Type
    ) throws -> E? where E: CaseIterable & RawRepresentable & Sendable, E.RawValue == String {
        try value(FenceParameter<E>.enumValue(key))
    }

    func requiredSchemaEnum<E>(
        _ key: FenceParameterKey,
        as type: E.Type
    ) throws -> E where E: CaseIterable & RawRepresentable & Sendable, E.RawValue == String {
        try requiredValue(FenceParameter<E>.enumValue(key))
    }

    func field(_ key: FenceParameterKey) -> String {
        field(forRawKey: key.rawValue)
    }

    func field(forUnknownKey key: String) -> String {
        field(forRawKey: key)
    }

    func decodePayload<T: Decodable>(
        _ value: HeistValue,
        forKey key: FenceParameterKey,
        as type: T.Type
    ) throws -> T {
        try TheFence.HeistValuePayloadDecoder.decode(value, field: field(key), as: type)
    }

    private func field(forRawKey key: String) -> String {
        guard let argumentFieldPrefix else { return key }
        return "\(argumentFieldPrefix).\(key)"
    }

}

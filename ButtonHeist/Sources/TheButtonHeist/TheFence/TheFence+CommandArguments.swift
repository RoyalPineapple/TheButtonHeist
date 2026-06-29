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

        func dropping(_ key: String) -> CommandArgumentEnvelope {
            var values = argumentValues
            values.removeValue(forKey: key)
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

protocol HeistValuePayloadExpectationProviding: Decodable {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation { get }
}

enum HeistValueExpectedType: Sendable, Equatable {
    case string
    case boolean
    case integer
    case number
    case object
    case array
    case stringMatchObject
    case elementPredicateCheckObject
    case arrayOfElementPredicateCheckObjects
    case arrayOfTraitNames

    var description: String {
        switch self {
        case .string:
            return "string"
        case .boolean:
            return "boolean"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .object:
            return "object"
        case .array:
            return "array"
        case .stringMatchObject:
            return "StringMatch object with mode and value"
        case .elementPredicateCheckObject:
            return "element predicate check object"
        case .arrayOfElementPredicateCheckObjects:
            return "array of element predicate check objects"
        case .arrayOfTraitNames:
            return "array of trait names"
        }
    }
}

struct HeistValuePayloadExpectation: Sendable, Equatable {
    let root: HeistValueExpectedType
    let rootArrayItem: HeistValueExpectedType?
    let paths: [String: HeistValueExpectedType]
    let arrayItems: [String: HeistValueExpectedType]

    init(
        root: HeistValueExpectedType,
        rootArrayItem: HeistValueExpectedType? = nil,
        paths: [String: HeistValueExpectedType] = [:],
        arrayItems: [String: HeistValueExpectedType] = [:]
    ) {
        self.root = root
        self.rootArrayItem = rootArrayItem
        self.paths = paths
        self.arrayItems = arrayItems
    }

    func expectedDescription(at codingPath: [CodingKey]) -> String {
        guard let path = Self.pathKey(codingPath) else {
            return root.description
        }
        if codingPath.last?.intValue != nil {
            return exactOrSuffixMatch(path, in: arrayItems)?.description
                ?? rootArrayItem?.description
                ?? root.description
        }
        return exactOrSuffixMatch(path, in: paths)?.description ?? root.description
    }

    func asArray() -> HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: .array,
            rootArrayItem: root,
            paths: paths,
            arrayItems: arrayItems
        )
    }

    private func exactOrSuffixMatch(
        _ path: String,
        in expectations: [String: HeistValueExpectedType]
    ) -> HeistValueExpectedType? {
        if let expectedType = expectations[path] {
            return expectedType
        }
        let components = path.split(separator: ".")
        for index in components.indices.dropFirst() {
            let suffix = components[index...].joined(separator: ".")
            if let expectedType = expectations[suffix] {
                return expectedType
            }
        }
        return nil
    }

    private static func pathKey(_ codingPath: [CodingKey]) -> String? {
        let components = codingPath.compactMap { key -> String? in
            key.intValue == nil ? key.stringValue : nil
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: ".")
    }

    static let object = HeistValuePayloadExpectation(root: .object)

    static let stringMatch = HeistValuePayloadExpectation(
        root: .stringMatchObject,
        paths: [
            "mode": .string,
            "value": .string,
        ]
    )

    static let elementPredicateCheck = HeistValuePayloadExpectation(
        root: .elementPredicateCheckObject,
        paths: merged([
            [
                "kind": .string,
                "match": .stringMatchObject,
                "values": .arrayOfTraitNames,
            ],
            prefixed("match", stringMatch.paths),
        ]),
        arrayItems: ["values": .string]
    )

    static let elementPredicate = HeistValuePayloadExpectation(
        root: .object,
        paths: elementPredicatePaths,
        arrayItems: elementPredicateArrayItems
    )

    static let elementTarget = HeistValuePayloadExpectation(
        root: .object,
        paths: merged([
            elementPredicatePaths,
            ["ordinal": .integer],
        ]),
        arrayItems: elementPredicateArrayItems
    )

    static let accessibilityPredicate = HeistValuePayloadExpectation(
        root: .object,
        paths: merged([
            elementTarget.paths,
            [
                "type": .string,
                "element": .object,
                "target": .object,
                "states": .array,
                "scopes": .array,
                "assertions": .array,
                "property": .string,
                "before": .stringMatchObject,
                "after": .stringMatchObject,
            ],
            prefixed("before", stringMatch.paths),
            prefixed("after", stringMatch.paths),
        ]),
        arrayItems: merged([
            elementTarget.arrayItems,
            [
                "states": .object,
                "scopes": .object,
                "assertions": .object,
            ],
        ])
    )

    static let containerMatcher = HeistValuePayloadExpectation(
        root: .object,
        paths: [
            "containerName": .string,
            "type": .string,
            "label": .string,
            "value": .string,
            "identifier": .string,
            "isModalBoundary": .boolean,
        ]
    )

    static let subtreeSelector = HeistValuePayloadExpectation(
        root: .object,
        paths: merged([
            [
                "element": .object,
                "container": .object,
                "ordinal": .integer,
            ],
            prefixed("element", elementTarget.paths),
            prefixed("container", containerMatcher.paths),
        ]),
        arrayItems: merged([
            prefixed("element", elementTarget.arrayItems),
            prefixed("container", containerMatcher.arrayItems),
        ])
    )

    private static var elementPredicatePaths: [String: HeistValueExpectedType] {
        merged([
            [
                "checks": .arrayOfElementPredicateCheckObjects,
                "label": .stringMatchObject,
                "identifier": .stringMatchObject,
                "value": .stringMatchObject,
                "traits": .arrayOfTraitNames,
                "excludeTraits": .arrayOfTraitNames,
            ],
            prefixed("label", stringMatch.paths),
            prefixed("identifier", stringMatch.paths),
            prefixed("value", stringMatch.paths),
            prefixed("checks", elementPredicateCheck.paths),
        ])
    }

    private static var elementPredicateArrayItems: [String: HeistValueExpectedType] {
        merged([
            [
                "checks": .elementPredicateCheckObject,
                "traits": .string,
                "excludeTraits": .string,
            ],
            prefixed("checks", elementPredicateCheck.arrayItems),
        ])
    }

    static func prefixed(
        _ prefix: String,
        _ expectations: [String: HeistValueExpectedType]
    ) -> [String: HeistValueExpectedType] {
        expectations.reduce(into: [:]) { result, entry in
            result["\(prefix).\(entry.key)"] = entry.value
        }
    }

    static func merged(
        _ expectations: [[String: HeistValueExpectedType]]
    ) -> [String: HeistValueExpectedType] {
        expectations.reduce(into: [:]) { result, expectation in
            result.merge(expectation) { _, new in new }
        }
    }
}

extension Array: HeistValuePayloadExpectationProviding where Element: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        Element.heistValuePayloadExpectation.asArray()
    }
}

extension AccessibilityPredicate: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .accessibilityPredicate
    }
}

extension ElementPredicate: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .elementPredicate
    }
}

extension ElementPredicateCheck: HeistValuePayloadExpectationProviding where Value == String {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .elementPredicateCheck
    }
}

extension ElementTarget: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .elementTarget
    }
}

extension StringMatch: HeistValuePayloadExpectationProviding where Value == String {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .stringMatch
    }
}

extension ContainerMatcher: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .containerMatcher
    }
}

extension SubtreeSelector: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .subtreeSelector
    }
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
            try decode(
                value,
                field: rootField,
                as: type,
                expectation: .object,
                includesRootInField: includesRootInField,
                dataCorruptedHandling: dataCorruptedHandling
            )
        }

        static func decode<T: HeistValuePayloadExpectationProviding>(
            _ value: HeistValue,
            field rootField: String,
            as type: T.Type,
            includesRootInField: Bool = true,
            dataCorruptedHandling: HeistValuePayloadDataCorruptedHandling = .schemaValidation
        ) throws -> T {
            try decode(
                value,
                field: rootField,
                as: type,
                expectation: T.heistValuePayloadExpectation,
                includesRootInField: includesRootInField,
                dataCorruptedHandling: dataCorruptedHandling
            )
        }

        private static func decode<T: Decodable>(
            _ value: HeistValue,
            field rootField: String,
            as type: T.Type,
            expectation: HeistValuePayloadExpectation,
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
                    expectation: expectation,
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
            expectation: HeistValuePayloadExpectation,
            includesRootInField: Bool,
            dataCorruptedHandling: HeistValuePayloadDataCorruptedHandling
        ) -> Error {
            switch error {
            case .typeMismatch(_, let context):
                return SchemaValidationError(
                    field: field(rootField, codingPath: context.codingPath, includesRoot: includesRootInField),
                    observed: payloadValue(at: context.codingPath, in: value)?.schemaObservedDescription
                        ?? value.schemaObservedDescription,
                    expected: expectation.expectedDescription(at: context.codingPath)
                )
            case .valueNotFound(_, let context):
                return SchemaValidationError(
                    field: field(rootField, codingPath: context.codingPath, includesRoot: includesRootInField),
                    observed: "missing",
                    expected: expectation.expectedDescription(at: context.codingPath)
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

    func schemaInteger(_ key: FenceParameterKey) throws -> Int? {
        try schemaInteger(key.rawValue)
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

    func schemaString(_ key: FenceParameterKey) throws -> String? {
        try schemaString(key.rawValue)
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

        return try decodePayload(value, forKey: key, as: StringMatch<String>.self)
    }

    func schemaStringMatches(_ key: String) throws -> [StringMatch<String>] {
        guard let value = argumentValues[key] else { return [] }
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
                        expected: "StringMatch object with mode and value"
                    )
                }
            }
            return try decodePayload(value, forKey: key, as: [StringMatch<String>].self)
        default:
            throw SchemaValidationError(
                field: field(key),
                observed: value.schemaObservedDescription,
                expected: "StringMatch object with mode and value, or array of StringMatch objects"
            )
        }
    }

    func schemaStringMatches(_ key: FenceParameterKey) throws -> [StringMatch<String>] {
        try schemaStringMatches(key.rawValue)
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

    func schemaBoolean(_ key: FenceParameterKey) throws -> Bool? {
        try schemaBoolean(key.rawValue)
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

    func schemaStringArray(_ key: FenceParameterKey) throws -> [String]? {
        try schemaStringArray(key.rawValue)
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

    func schemaEnum<E>(
        _ key: FenceParameterKey,
        as type: E.Type
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        try schemaEnum(key.rawValue, as: type)
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

    func field(_ key: FenceParameterKey) -> String {
        field(key.rawValue)
    }

    func decodePayload<T: HeistValuePayloadExpectationProviding>(
        _ value: HeistValue,
        forKey key: String,
        as type: T.Type
    ) throws -> T {
        try TheFence.HeistValuePayloadDecoder.decode(value, field: field(key), as: type)
    }

    func decodePayload<T: HeistValuePayloadExpectationProviding>(
        _ value: HeistValue,
        forKey key: FenceParameterKey,
        as type: T.Type
    ) throws -> T {
        try decodePayload(value, forKey: key.rawValue, as: type)
    }

}

import Foundation
import TheScore

extension TheFence {
    internal enum DecodeLimits {
        internal static let maxRunHeistSteps = 100
        internal static let maxRunHeistRequestBytes = PublicJSONInputLimits.maxRequestBytes
        internal static let maxRunHeistNestingDepth = PublicJSONInputLimits.maxNestingDepth
        internal static let maxRunHeistObjectKeys = PublicJSONInputLimits.maxTotalObjectKeys
        internal static let maxHeistResultRows = maxRunHeistSteps
        internal static let maxInlineScreenshotBase64Bytes = 1_000_000
    }
}

extension FenceParameter where Value == String {
    internal static func string(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: String? = nil,
        minLength: Int? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .string,
                required: required,
                defaultValue: defaultValue.map(HeistValue.string),
                minLength: minLength
            ),
            expectedTypeDescription: "string",
            defaultValue: defaultValue,
            decodeValue: { value, field in
                let string = try decodeString(value, field: field)
                if let minLength, string.count < minLength {
                    throw SchemaValidationError(
                        field: field,
                        observed: value.schemaObservedDescription,
                        expected: minLength == 1 ? "non-empty string" : "string with length >= \(minLength)"
                    )
                }
                return string
            },
            encodeValue: { .string($0) }
        )
    }

    private static func decodeString(_ value: HeistValue, field: String) throws -> String {
        guard case .string(let string) = value else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "string")
        }
        return string
    }
}

extension FenceParameter where Value == Int {
    internal static func integer(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Int? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .integer,
                required: required,
                defaultValue: defaultValue.map(HeistValue.int),
                minimum: minimum,
                maximum: maximum
            ),
            expectedTypeDescription: "integer",
            defaultValue: defaultValue,
            decodeValue: { value, field in
                let integer = try decodeInteger(value, field: field)
                try validateInteger(
                    integer,
                    source: value,
                    field: field,
                    minimum: minimum,
                    maximum: maximum
                )
                return integer
            },
            encodeValue: { .int($0) }
        )
    }

    private static func decodeInteger(_ value: HeistValue, field: String) throws -> Int {
        guard let integer = value.integerValue else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "integer")
        }
        return integer
    }
}

extension FenceParameter where Value == Double {
    internal static func number(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .number,
                required: required,
                defaultValue: defaultValue.map(jsonSchemaNumber),
                maximum: maximum,
                exclusiveMinimum: exclusiveMinimum
            ),
            expectedTypeDescription: "number",
            defaultValue: defaultValue,
            decodeValue: { value, field in
                let number = try decodeNumber(value, field: field)
                try validateNumber(
                    number,
                    source: value,
                    field: field,
                    maximum: maximum,
                    exclusiveMinimum: exclusiveMinimum
                )
                return number
            },
            encodeValue: { jsonSchemaNumber($0) }
        )
    }

    private static func decodeNumber(_ value: HeistValue, field: String) throws -> Double {
        guard let number = value.numberValue else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "number")
        }
        return number
    }
}

extension FenceParameter where Value == Bool {
    internal static func boolean(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Bool? = nil
    ) -> Self {
        FenceParameter(
            key: key,
            spec: param(
                key,
                .boolean,
                required: required,
                defaultValue: defaultValue.map(HeistValue.bool)
            ),
            expectedTypeDescription: "boolean",
            defaultValue: defaultValue,
            decodeValue: { value, field in try decodeBoolean(value, field: field) },
            encodeValue: { .bool($0) }
        )
    }

    private static func decodeBoolean(_ value: HeistValue, field: String) throws -> Bool {
        guard case .bool(let bool) = value else {
            throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "boolean")
        }
        return bool
    }
}

extension FenceParameter where Value: CaseIterable & RawRepresentable, Value.RawValue == String {
    internal static func enumValue(
        _ key: FenceParameterKey,
        required: Bool = false,
        defaultValue: Value? = nil
    ) -> Self {
        let rawValues = Value.allCases.map(\.rawValue)
        return FenceParameter(
            key: key,
            spec: param(
                key,
                .string,
                required: required,
                enumValues: rawValues,
                defaultValue: defaultValue.map { .string($0.rawValue) }
            ),
            expectedTypeDescription: SchemaValidationError.expectedEnumValues(rawValues),
            defaultValue: defaultValue,
            allowedRawValues: rawValues,
            decodeValue: { value, field in
                guard case .string(let rawValue) = value else {
                    throw SchemaValidationError(field: field, observed: value.schemaObservedDescription, expected: "string")
                }
                guard let enumValue = Value(rawValue: rawValue) else {
                    throw SchemaValidationError(
                        field: field,
                        observed: "string \"\(rawValue)\"",
                        expected: SchemaValidationError.expectedEnumValues(rawValues)
                    )
                }
                return enumValue
            },
            encodeValue: { .string($0.rawValue) }
        )
    }
}

internal func fenceEnumValues<E>(_ type: E.Type) -> [String]
where E: CaseIterable & RawRepresentable, E.RawValue == String {
    type.allCases.map(\.rawValue)
}

private func validateInteger(
    _ integer: Int,
    source: HeistValue,
    field: String,
    minimum: Double?,
    maximum: Double?
) throws {
    if let minimum, Double(integer) < minimum {
        throw SchemaValidationError(
            field: field,
            observed: source.schemaObservedDescription,
            expected: numericBoundsDescription(type: "integer", minimum: minimum, maximum: maximum)
        )
    }
    if let maximum, Double(integer) > maximum {
        throw SchemaValidationError(
            field: field,
            observed: source.schemaObservedDescription,
            expected: numericBoundsDescription(type: "integer", minimum: minimum, maximum: maximum)
        )
    }
}

private func validateNumber(
    _ number: Double,
    source: HeistValue,
    field: String,
    maximum: Double?,
    exclusiveMinimum: Double?
) throws {
    if let exclusiveMinimum, number <= exclusiveMinimum {
        throw SchemaValidationError(
            field: field,
            observed: source.schemaObservedDescription,
            expected: "number > \(formatConstraintNumber(exclusiveMinimum))"
        )
    }
    if let maximum, number > maximum {
        let expected = if let exclusiveMinimum {
            "number in \(formatConstraintNumber(exclusiveMinimum))...\(formatNumberUpperBound(maximum))"
        } else {
            "number <= \(formatConstraintNumber(maximum))"
        }
        throw SchemaValidationError(field: field, observed: source.schemaObservedDescription, expected: expected)
    }
}

private func numericBoundsDescription(type: String, minimum: Double?, maximum: Double?) -> String {
    switch (minimum, maximum) {
    case (.some(let minimum), .some(let maximum)):
        return "\(type) between \(formatConstraintNumber(minimum)) and \(formatConstraintNumber(maximum))"
    case (.some(let minimum), nil):
        return "\(type) >= \(formatConstraintNumber(minimum))"
    case (nil, .some(let maximum)):
        return "\(type) <= \(formatConstraintNumber(maximum))"
    case (nil, nil):
        return type
    }
}

private func formatNumberUpperBound(_ value: Double) -> String {
    value != 0 && value.rounded(.towardZero) == value ? String(format: "%.1f", value) : formatConstraintNumber(value)
}

private func formatConstraintNumber(_ value: Double) -> String {
    value.rounded(.towardZero) == value ? String(format: "%.0f", value) : String(value)
}

import Foundation

import TheScore

extension TheFence.CommandArgumentReadable {
    func number(_ key: String) throws -> Double? {
        try schemaNumber(key)
    }

    func hasAny(_ keys: String...) -> Bool {
        keys.contains { argumentValues[$0] != nil }
    }

    func requiredNumber(_ key: String) throws -> Double {
        try requiredSchemaNumber(key)
    }

    func positiveNumber(_ key: String) throws -> Double? {
        guard let value = try number(key) else { return nil }
        guard value > 0 else {
            throw SchemaValidationError(field: key, observed: value, expected: "number > 0")
        }
        return value
    }

    func requiredPositiveNumber(_ key: String) throws -> Double {
        guard let value = try positiveNumber(key) else {
            throw SchemaValidationError(field: key, observed: "missing", expected: "number > 0")
        }
        return value
    }

    func gestureDuration() throws -> Double? {
        try boundedPositiveNumber("duration", maximum: TheFence.DecodeLimits.maxDrawGestureDurationSeconds)
    }

    func boundedPositiveNumber(_ key: String, maximum: Double) throws -> Double? {
        guard let value = try positiveNumber(key) else { return nil }
        guard value <= maximum else {
            throw SchemaValidationError(field: key, observed: value, expected: "number in 0...\(maximum)")
        }
        return value
    }

    func boundedPositiveInteger(_ key: String, minimum: Int, maximum: Int) throws -> Int? {
        guard let value = try schemaInteger(key) else { return nil }
        guard value >= minimum && value <= maximum else {
            throw SchemaValidationError(field: key, observed: value, expected: "integer in \(minimum)...\(maximum)")
        }
        return value
    }

    func unitPoint(_ key: String) throws -> UnitPoint? {
        try schemaUnitPoint(key)
    }

    func enumValue<E>(
        _ key: String,
        as type: E.Type
    ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
        try schemaEnum(key, as: type)
    }

    func requiredObjectArray(_ key: String) throws -> [TheFence.CommandArgumentObject] {
        try requiredSchemaObjectArray(key)
    }
}

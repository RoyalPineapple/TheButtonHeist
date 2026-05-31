import Foundation

import TheScore

extension TheFence.CommandArgumentEnvelope {
    func hasAny(_ keys: String...) -> Bool {
        keys.contains { argumentValues[$0] != nil }
    }

    func positiveNumber(_ key: String) throws -> Double? {
        guard let value = try schemaNumber(key) else { return nil }
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
        try boundedPositiveNumber("duration", maximum: TheFence.DecodeLimits.maxGestureDurationSeconds)
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

}

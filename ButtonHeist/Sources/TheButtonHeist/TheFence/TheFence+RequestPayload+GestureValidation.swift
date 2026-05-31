import Foundation

extension TheFence {

    func validateArrayCount(
        field: String,
        count: Int,
        min: Int,
        max: Int,
        note: String
    ) throws {
        guard count >= min && count <= max else {
            throw SchemaValidationError(
                field: field,
                observed: "array count \(count)",
                expected: "array count \(min)...\(max) (\(note))"
            )
        }
    }

    func validatePositiveGestureNumber(_ value: Double?, field: String) throws {
        guard let value else { return }
        guard value > 0 else {
            throw SchemaValidationError(field: field, observed: value, expected: "number > 0")
        }
    }

    func validateGestureDuration(_ duration: Double?) throws {
        try validatePositiveGestureNumber(duration, field: "duration")
        guard let duration else { return }
        guard duration <= DecodeLimits.maxGestureDurationSeconds else {
            throw SchemaValidationError(
                field: "duration",
                observed: duration,
                expected: "number in 0...\(DecodeLimits.maxGestureDurationSeconds)"
            )
        }
    }
}

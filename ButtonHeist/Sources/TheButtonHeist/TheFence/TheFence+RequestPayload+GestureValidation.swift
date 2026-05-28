import Foundation

extension TheFence {

    func validateDrawTiming(duration: Double?, velocity: Double?) throws {
        guard duration == nil || velocity == nil else {
            throw SchemaValidationError(
                field: "duration/velocity",
                observed: "both duration and velocity",
                expected: "duration or velocity"
            )
        }
    }

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
}

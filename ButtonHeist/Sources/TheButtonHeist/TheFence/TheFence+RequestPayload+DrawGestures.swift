import Foundation

import TheScore

extension TheFence {

    func decodeDrawPathTarget(_ request: some CommandArgumentReadable) throws -> DrawPathTarget {
        let pointsArray = try request.requiredSchemaObjectArray("points")
        try validateArrayCount(
            field: "points",
            count: pointsArray.count,
            min: 2,
            max: DecodeLimits.maxDrawPathPoints,
            note: "at least 2 points"
        )
        let target = try request.decodeCommandPayload(DrawPathTarget.self)
        try validateDrawGestureTiming(duration: target.duration, velocity: target.velocity)
        return target
    }

    func decodeDrawBezierTarget(_ request: some CommandArgumentReadable) throws -> DrawBezierTarget {
        let segmentsArray = try request.requiredSchemaObjectArray("segments")
        try validateArrayCount(
            field: "segments",
            count: segmentsArray.count,
            min: 1,
            max: DecodeLimits.maxDrawBezierSegments,
            note: "At least 1 bezier segment is required"
        )
        let target = try request.decodeCommandPayload(DrawBezierTarget.self)
        try validateDrawBezierSamples(target.samplesPerSegment)
        try validateDrawGestureTiming(duration: target.duration, velocity: target.velocity)
        let resolvedSamplesPerSegment = target.samplesPerSegment ?? DrawBezierTarget.defaultSamplesPerSegment
        let generatedPointCount = target.segments.count * (resolvedSamplesPerSegment - 1) + 1
        guard generatedPointCount <= DecodeLimits.maxDrawBezierGeneratedPathPoints else {
            throw SchemaValidationError(
                field: "segments",
                observed: "generated path point count \(generatedPointCount)",
                expected: "generated path point count <= \(DecodeLimits.maxDrawBezierGeneratedPathPoints)"
            )
        }
        return target
    }

    private func validateDrawGestureTiming(duration: Double?, velocity: Double?) throws {
        if let duration {
            guard duration > 0, duration <= DecodeLimits.maxDrawGestureDurationSeconds else {
                throw SchemaValidationError(
                    field: "duration",
                    observed: duration,
                    expected: "number in 0...\(DecodeLimits.maxDrawGestureDurationSeconds)"
                )
            }
        }
        if let velocity {
            guard velocity > 0 else {
                throw SchemaValidationError(field: "velocity", observed: velocity, expected: "number > 0")
            }
        }
    }

    private func validateDrawBezierSamples(_ samplesPerSegment: Int?) throws {
        guard let samplesPerSegment else { return }
        guard samplesPerSegment >= DecodeLimits.minDrawBezierSamplesPerSegment,
              samplesPerSegment <= DecodeLimits.maxDrawBezierSamplesPerSegment else {
            throw SchemaValidationError(
                field: "samplesPerSegment",
                observed: samplesPerSegment,
                expected: "integer in \(DecodeLimits.minDrawBezierSamplesPerSegment)...\(DecodeLimits.maxDrawBezierSamplesPerSegment)"
            )
        }
    }
}

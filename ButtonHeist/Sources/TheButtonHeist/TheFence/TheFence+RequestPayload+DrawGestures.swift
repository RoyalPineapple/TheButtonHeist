import Foundation

import TheScore

extension TheFence {

    func decodeDrawPathTarget(_ request: GestureRequestInput) throws -> DrawPathTarget {
        let pointsArray = try request.requiredObjectArray("points")
        try validateArrayCount(
            field: "points",
            count: pointsArray.count,
            min: 2,
            max: DecodeLimits.maxDrawPathPoints,
            note: "at least 2 points"
        )
        let points = try pointsArray.enumerated().map { index, point -> PathPoint in
            try point.rejectUnknownKeys(["x", "y"], expected: "valid draw path point field")
            return PathPoint(
                x: try point.requiredNumber("x", field: "points[\(index)].x"),
                y: try point.requiredNumber("y", field: "points[\(index)].y")
            )
        }
        let duration = try request.boundedPositiveNumber(
            "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
        let velocity = try request.positiveNumber("velocity")
        try validateDrawTiming(duration: duration, velocity: velocity)
        return DrawPathTarget(
            points: points,
            duration: duration,
            velocity: velocity
        )
    }

    func decodeDrawBezierTarget(_ request: GestureRequestInput) throws -> DrawBezierTarget {
        let startX = try request.requiredNumber("startX")
        let startY = try request.requiredNumber("startY")
        let segmentsArray = try request.requiredObjectArray("segments")
        try validateArrayCount(
            field: "segments",
            count: segmentsArray.count,
            min: 1,
            max: DecodeLimits.maxDrawBezierSegments,
            note: "At least 1 bezier segment is required"
        )
        let segments = try segmentsArray.enumerated().map { index, segment -> BezierSegment in
            try segment.rejectUnknownKeys(
                ["cp1X", "cp1Y", "cp2X", "cp2Y", "endX", "endY"],
                expected: "valid bezier segment field"
            )
            return BezierSegment(
                cp1X: try segment.requiredNumber("cp1X", field: "segments[\(index)].cp1X"),
                cp1Y: try segment.requiredNumber("cp1Y", field: "segments[\(index)].cp1Y"),
                cp2X: try segment.requiredNumber("cp2X", field: "segments[\(index)].cp2X"),
                cp2Y: try segment.requiredNumber("cp2Y", field: "segments[\(index)].cp2Y"),
                endX: try segment.requiredNumber("endX", field: "segments[\(index)].endX"),
                endY: try segment.requiredNumber("endY", field: "segments[\(index)].endY")
            )
        }
        let samplesPerSegment = try request.boundedPositiveInteger(
            "samplesPerSegment",
            minimum: DecodeLimits.minDrawBezierSamplesPerSegment,
            maximum: DecodeLimits.maxDrawBezierSamplesPerSegment
        )
        let resolvedSamplesPerSegment = samplesPerSegment ?? DrawBezierTarget.defaultSamplesPerSegment
        let generatedPointCount = segments.count * (resolvedSamplesPerSegment - 1) + 1
        guard generatedPointCount <= DecodeLimits.maxDrawBezierGeneratedPathPoints else {
            throw SchemaValidationError(
                field: "segments",
                observed: "generated path point count \(generatedPointCount)",
                expected: "generated path point count <= \(DecodeLimits.maxDrawBezierGeneratedPathPoints)"
            )
        }
        let duration = try request.boundedPositiveNumber(
            "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
        let velocity = try request.positiveNumber("velocity")
        try validateDrawTiming(duration: duration, velocity: velocity)
        return DrawBezierTarget(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: samplesPerSegment,
            duration: duration,
            velocity: velocity
        )
    }
}

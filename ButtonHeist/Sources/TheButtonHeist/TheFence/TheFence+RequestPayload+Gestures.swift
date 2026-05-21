import Foundation

import TheScore

extension TheFence {

    func decodeGestureRequestPayload(
        command: Command,
        request: [String: Any]
    ) throws -> RequestPayload {
        .gesture(try decodeGesturePayload(command: command, request: request))
    }

    private func decodeGesturePayload(
        command: Command,
        request: [String: Any]
    ) throws -> GesturePayload {
        switch command {
        case .oneFingerTap:
            return .oneFingerTap(try decodeTouchTapTarget(request))
        case .longPress:
            return .longPress(try decodeLongPressTarget(request))
        case .swipe:
            return .swipe(try decodeSwipeTarget(request))
        case .drag:
            return .drag(try decodeDragTarget(request))
        case .pinch:
            return .pinch(try decodePinchTarget(request))
        case .rotate:
            return .rotate(try decodeRotateTarget(request))
        case .twoFingerTap:
            return .twoFingerTap(try decodeTwoFingerTapTarget(request))
        case .drawPath:
            return .drawPath(try decodeDrawPathTarget(request))
        case .drawBezier:
            return .drawBezier(try decodeDrawBezierTarget(request))
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private struct TouchTapGestureRequest {
        let elementTarget: ElementTarget?
        let pointX: Double?
        let pointY: Double?

        var target: TouchTapTarget {
            TouchTapTarget(elementTarget: elementTarget, pointX: pointX, pointY: pointY)
        }
    }

    private func decodeTouchTapTarget(_ request: [String: Any]) throws -> TouchTapTarget {
        let payload = TouchTapGestureRequest(
            elementTarget: try decodedElementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y")
        )
        let target = payload.target
        if target.elementTarget == nil, target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return target
    }

    private struct LongPressGestureRequest {
        let elementTarget: ElementTarget?
        let pointX: Double?
        let pointY: Double?
        let duration: Double

        var target: LongPressTarget {
            LongPressTarget(
                elementTarget: elementTarget,
                pointX: pointX,
                pointY: pointY,
                duration: duration
            )
        }
    }

    private func decodeLongPressTarget(_ request: [String: Any]) throws -> LongPressTarget {
        let payload = LongPressGestureRequest(
            elementTarget: try decodedElementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y"),
            duration: try schemaGestureDuration(request) ?? 0.5
        )
        let target = payload.target
        if target.elementTarget == nil, target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return target
    }

    private struct SwipeGestureRequest {
        let elementTarget: ElementTarget?
        let startX: Double?
        let startY: Double?
        let endX: Double?
        let endY: Double?
        let direction: SwipeDirection?
        let duration: Double?
        let start: UnitPoint?
        let end: UnitPoint?

        var target: SwipeTarget {
            SwipeTarget(
                elementTarget: elementTarget,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                direction: direction,
                duration: duration,
                start: start,
                end: end
            )
        }
    }

    private func decodeSwipeTarget(_ request: [String: Any]) throws -> SwipeTarget {
        let start = try request.schemaUnitPoint("start")
        let end = try request.schemaUnitPoint("end")
        let payload = SwipeGestureRequest(
            elementTarget: try decodedElementTarget(request),
            startX: try request.schemaNumber("startX"),
            startY: try request.schemaNumber("startY"),
            endX: try request.schemaNumber("endX"),
            endY: try request.schemaNumber("endY"),
            direction: try request.schemaEnum("direction", as: SwipeDirection.self) { $0.lowercased() },
            duration: try schemaGestureDuration(request),
            start: start,
            end: end
        )
        let target = payload.target
        if (target.start != nil) != (target.end != nil) {
            throw FenceError.invalidRequest("Unit-point swipe requires both start and end")
        }
        return target
    }

    private struct DragGestureRequest {
        let elementTarget: ElementTarget?
        let startX: Double?
        let startY: Double?
        let endX: Double
        let endY: Double
        let duration: Double?

        var target: DragTarget {
            DragTarget(
                elementTarget: elementTarget,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                duration: duration
            )
        }
    }

    private func decodeDragTarget(_ request: [String: Any]) throws -> DragTarget {
        DragGestureRequest(
            elementTarget: try decodedElementTarget(request),
            startX: try request.schemaNumber("startX"),
            startY: try request.schemaNumber("startY"),
            endX: try request.requiredSchemaNumber("endX"),
            endY: try request.requiredSchemaNumber("endY"),
            duration: try schemaGestureDuration(request)
        ).target
    }

    private struct PinchGestureRequest {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let scale: Double
        let spread: Double?
        let duration: Double?

        var target: PinchTarget {
            PinchTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                scale: scale,
                spread: spread,
                duration: duration
            )
        }
    }

    private func decodePinchTarget(_ request: [String: Any]) throws -> PinchTarget {
        PinchGestureRequest(
            elementTarget: try decodedElementTarget(request),
            centerX: try request.schemaNumber("centerX"),
            centerY: try request.schemaNumber("centerY"),
            scale: try requiredSchemaPositiveNumber(request, key: "scale"),
            spread: try schemaPositiveNumber(request, key: "spread"),
            duration: try schemaGestureDuration(request)
        ).target
    }

    private struct RotateGestureRequest {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let angle: Double
        let radius: Double?
        let duration: Double?

        var target: RotateTarget {
            RotateTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                angle: angle,
                radius: radius,
                duration: duration
            )
        }
    }

    private func decodeRotateTarget(_ request: [String: Any]) throws -> RotateTarget {
        RotateGestureRequest(
            elementTarget: try decodedElementTarget(request),
            centerX: try request.schemaNumber("centerX"),
            centerY: try request.schemaNumber("centerY"),
            angle: try request.requiredSchemaNumber("angle"),
            radius: try schemaPositiveNumber(request, key: "radius"),
            duration: try schemaGestureDuration(request)
        ).target
    }

    private struct TwoFingerTapGestureRequest {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let spread: Double?

        var target: TwoFingerTapTarget {
            TwoFingerTapTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                spread: spread
            )
        }
    }

    private func decodeTwoFingerTapTarget(_ request: [String: Any]) throws -> TwoFingerTapTarget {
        TwoFingerTapGestureRequest(
            elementTarget: try decodedElementTarget(request),
            centerX: try request.schemaNumber("centerX"),
            centerY: try request.schemaNumber("centerY"),
            spread: try schemaPositiveNumber(request, key: "spread")
        ).target
    }

    private struct DrawPathGestureRequest {
        let points: [PathPoint]
        let duration: Double?
        let velocity: Double?

        var target: DrawPathTarget {
            DrawPathTarget(points: points, duration: duration, velocity: velocity)
        }
    }

    private func decodeDrawPathTarget(_ request: [String: Any]) throws -> DrawPathTarget {
        let pointsArray = try request.requiredSchemaDictionaryArray("points")
        try validateArrayCount(
            field: "points",
            count: pointsArray.count,
            min: 2,
            max: DecodeLimits.maxDrawPathPoints,
            note: "at least 2 points"
        )
        let points = try pointsArray.enumerated().map { index, point -> PathPoint in
            PathPoint(
                x: try schemaNumber(in: point, key: "x", field: "points[\(index)].x"),
                y: try schemaNumber(in: point, key: "y", field: "points[\(index)].y")
            )
        }
        let duration = try schemaBoundedPositiveNumber(
            request,
            key: "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
        return DrawPathGestureRequest(
            points: points,
            duration: duration,
            velocity: try schemaPositiveNumber(request, key: "velocity")
        ).target
    }

    private struct DrawBezierGestureRequest {
        let startX: Double
        let startY: Double
        let segments: [BezierSegment]
        let samplesPerSegment: Int?
        let duration: Double?
        let velocity: Double?

        var target: DrawBezierTarget {
            DrawBezierTarget(
                startX: startX,
                startY: startY,
                segments: segments,
                samplesPerSegment: samplesPerSegment,
                duration: duration,
                velocity: velocity
            )
        }
    }

    private func decodeDrawBezierTarget(_ request: [String: Any]) throws -> DrawBezierTarget {
        let startX = try request.requiredSchemaNumber("startX")
        let startY = try request.requiredSchemaNumber("startY")
        let segmentsArray = try request.requiredSchemaDictionaryArray("segments")
        try validateArrayCount(
            field: "segments",
            count: segmentsArray.count,
            min: 1,
            max: DecodeLimits.maxDrawBezierSegments,
            note: "At least 1 bezier segment is required"
        )
        let segments = try segmentsArray.enumerated().map { index, segment -> BezierSegment in
            BezierSegment(
                cp1X: try schemaNumber(in: segment, key: "cp1X", field: "segments[\(index)].cp1X"),
                cp1Y: try schemaNumber(in: segment, key: "cp1Y", field: "segments[\(index)].cp1Y"),
                cp2X: try schemaNumber(in: segment, key: "cp2X", field: "segments[\(index)].cp2X"),
                cp2Y: try schemaNumber(in: segment, key: "cp2Y", field: "segments[\(index)].cp2Y"),
                endX: try schemaNumber(in: segment, key: "endX", field: "segments[\(index)].endX"),
                endY: try schemaNumber(in: segment, key: "endY", field: "segments[\(index)].endY")
            )
        }
        let samplesPerSegment = try schemaBoundedPositiveInteger(
            request,
            key: "samplesPerSegment",
            minimum: DecodeLimits.minDrawBezierSamplesPerSegment,
            maximum: DecodeLimits.maxDrawBezierSamplesPerSegment
        )
        let resolvedSamplesPerSegment = samplesPerSegment ?? 20
        let generatedPointCount = segments.count * (resolvedSamplesPerSegment - 1) + 1
        guard generatedPointCount <= DecodeLimits.maxDrawBezierGeneratedPathPoints else {
            throw SchemaValidationError(
                field: "segments",
                observed: "generated path point count \(generatedPointCount)",
                expected: "generated path point count <= \(DecodeLimits.maxDrawBezierGeneratedPathPoints)"
            )
        }
        let duration = try schemaBoundedPositiveNumber(
            request,
            key: "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
        return DrawBezierGestureRequest(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: samplesPerSegment,
            duration: duration,
            velocity: try schemaPositiveNumber(request, key: "velocity")
        ).target
    }

    private func validateArrayCount(
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

    private func requiredSchemaPositiveNumber(
        _ dictionary: [String: Any],
        key: String
    ) throws -> Double {
        guard let value = try schemaPositiveNumber(dictionary, key: key) else {
            throw SchemaValidationError(field: key, observed: nil, expected: "number > 0")
        }
        return value
    }

    private func schemaPositiveNumber(
        _ dictionary: [String: Any],
        key: String
    ) throws -> Double? {
        guard let value = try dictionary.schemaNumber(key) else { return nil }
        guard value > 0 else {
            throw SchemaValidationError(field: key, observed: value, expected: "number > 0")
        }
        return value
    }

    private func schemaGestureDuration(_ dictionary: [String: Any]) throws -> Double? {
        try schemaBoundedPositiveNumber(
            dictionary,
            key: "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
    }

    private func schemaBoundedPositiveNumber(
        _ dictionary: [String: Any],
        key: String,
        maximum: Double
    ) throws -> Double? {
        guard let value = try schemaPositiveNumber(dictionary, key: key) else { return nil }
        guard value <= maximum else {
            throw SchemaValidationError(field: key, observed: value, expected: "number in 0...\(maximum)")
        }
        return value
    }

    private func schemaPositiveInteger(
        _ dictionary: [String: Any],
        key: String
    ) throws -> Int? {
        guard let value = try dictionary.schemaInteger(key) else { return nil }
        guard value > 0 else {
            throw SchemaValidationError(field: key, observed: value, expected: "integer > 0")
        }
        return value
    }

    private func schemaBoundedPositiveInteger(
        _ dictionary: [String: Any],
        key: String,
        minimum: Int,
        maximum: Int
    ) throws -> Int? {
        guard let value = try dictionary.schemaInteger(key) else { return nil }
        guard value >= minimum && value <= maximum else {
            throw SchemaValidationError(field: key, observed: value, expected: "integer in \(minimum)...\(maximum)")
        }
        return value
    }

    private func schemaNumber(
        in dictionary: [String: Any],
        key: String,
        field: String
    ) throws -> Double {
        do {
            guard let value = try dictionary.schemaNumber(key) else {
                throw SchemaValidationError(field: field, observed: nil, expected: "number")
            }
            return value
        } catch let error as SchemaValidationError {
            throw SchemaValidationError(field: field, observed: error.observed, expected: error.expected)
        }
    }
}

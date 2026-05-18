import Foundation

import TheScore

extension TheFence {

    func decodeGesturePayload(
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

    private func decodeTouchTapTarget(_ request: [String: Any]) throws -> TouchTapTarget {
        let target = TouchTapTarget(
            elementTarget: try elementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y")
        )
        if target.elementTarget == nil, target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return target
    }

    private func decodeLongPressTarget(_ request: [String: Any]) throws -> LongPressTarget {
        let target = LongPressTarget(
            elementTarget: try elementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y"),
            duration: try schemaPositiveNumber(request, key: "duration") ?? 0.5
        )
        if target.elementTarget == nil, target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return target
    }

    private func decodeSwipeTarget(_ request: [String: Any]) throws -> SwipeTarget {
        let start = try request.schemaUnitPoint("start")
        let end = try request.schemaUnitPoint("end")
        let target = SwipeTarget(
            elementTarget: try elementTarget(request),
            startX: try request.schemaNumber("startX"),
            startY: try request.schemaNumber("startY"),
            endX: try request.schemaNumber("endX"),
            endY: try request.schemaNumber("endY"),
            direction: try request.schemaEnum("direction", as: SwipeDirection.self) { $0.lowercased() },
            duration: try schemaPositiveNumber(request, key: "duration"),
            start: start,
            end: end
        )
        if (target.start != nil) != (target.end != nil) {
            throw FenceError.invalidRequest("Unit-point swipe requires both start and end")
        }
        return target
    }

    private func decodeDragTarget(_ request: [String: Any]) throws -> DragTarget {
        DragTarget(
            elementTarget: try elementTarget(request),
            startX: try request.schemaNumber("startX") ?? request.schemaNumber("x"),
            startY: try request.schemaNumber("startY") ?? request.schemaNumber("y"),
            endX: try request.requiredSchemaNumber("endX"),
            endY: try request.requiredSchemaNumber("endY"),
            duration: try schemaPositiveNumber(request, key: "duration")
        )
    }

    private func decodePinchTarget(_ request: [String: Any]) throws -> PinchTarget {
        PinchTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            scale: try requiredSchemaPositiveNumber(request, key: "scale"),
            spread: try schemaPositiveNumber(request, key: "spread"),
            duration: try schemaPositiveNumber(request, key: "duration")
        )
    }

    private func decodeRotateTarget(_ request: [String: Any]) throws -> RotateTarget {
        RotateTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            angle: try request.requiredSchemaNumber("angle"),
            radius: try schemaPositiveNumber(request, key: "radius"),
            duration: try schemaPositiveNumber(request, key: "duration")
        )
    }

    private func decodeTwoFingerTapTarget(_ request: [String: Any]) throws -> TwoFingerTapTarget {
        TwoFingerTapTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            spread: try schemaPositiveNumber(request, key: "spread")
        )
    }

    private func decodeDrawPathTarget(_ request: [String: Any]) throws -> DrawPathTarget {
        let pointsArray = try request.requiredSchemaDictionaryArray("points")
        let points = try pointsArray.enumerated().map { index, point -> PathPoint in
            PathPoint(
                x: try schemaNumber(in: point, key: "x", field: "points[\(index)].x"),
                y: try schemaNumber(in: point, key: "y", field: "points[\(index)].y")
            )
        }
        guard points.count >= 2 else {
            throw FenceError.invalidRequest("Path requires at least 2 points")
        }
        return DrawPathTarget(
            points: points,
            duration: try schemaPositiveNumber(request, key: "duration"),
            velocity: try schemaPositiveNumber(request, key: "velocity")
        )
    }

    private func decodeDrawBezierTarget(_ request: [String: Any]) throws -> DrawBezierTarget {
        let startX = try request.requiredSchemaNumber("startX")
        let startY = try request.requiredSchemaNumber("startY")
        let segmentsArray = try request.requiredSchemaDictionaryArray("segments")
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
        guard !segments.isEmpty else {
            throw FenceError.invalidRequest("At least 1 bezier segment is required")
        }
        return DrawBezierTarget(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: try schemaPositiveInteger(request, key: "samplesPerSegment"),
            duration: try schemaPositiveNumber(request, key: "duration"),
            velocity: try schemaPositiveNumber(request, key: "velocity")
        )
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

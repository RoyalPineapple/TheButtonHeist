import Foundation

import TheScore

extension TheFence {

    func decodeGestureRequestPayload(
        command: Command,
        request: [String: Any]
    ) throws -> RequestPayload {
        .gesture(try decodeGesturePayload(command: command, request: GestureRequestInput(request)))
    }

    private func decodeGesturePayload(
        command: Command,
        request: GestureRequestInput
    ) throws -> GesturePayload {
        switch command {
        case .oneFingerTap:
            return .oneFingerTap(try decodeTouchTapGesturePayload(request))
        case .longPress:
            return .longPress(try decodeLongPressGesturePayload(request))
        case .swipe:
            return .swipe(try decodeSwipeGesturePayload(request))
        case .drag:
            return .drag(try decodeDragGesturePayload(request))
        case .pinch:
            return .pinch(try decodePinchGesturePayload(request))
        case .rotate:
            return .rotate(try decodeRotateGesturePayload(request))
        case .twoFingerTap:
            return .twoFingerTap(try decodeTwoFingerTapGesturePayload(request))
        case .drawPath:
            return .drawPath(try decodeDrawPathGesturePayload(request))
        case .drawBezier:
            return .drawBezier(try decodeDrawBezierGesturePayload(request))
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private struct GestureRequestInput {
        private let request: [String: Any]

        init(_ request: [String: Any]) {
            self.request = request
        }

        @ButtonHeistActor
        func elementTarget(in fence: TheFence) throws -> ElementTarget? {
            try fence.decodedElementTarget(request)
        }

        func number(_ key: String) throws -> Double? {
            try request.schemaNumber(key)
        }

        func requiredNumber(_ key: String) throws -> Double {
            try request.requiredSchemaNumber(key)
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
                throw SchemaValidationError(field: key, observed: nil, expected: "number > 0")
            }
            return value
        }

        func gestureDuration() throws -> Double? {
            try boundedPositiveNumber("duration", maximum: DecodeLimits.maxDrawGestureDurationSeconds)
        }

        func boundedPositiveNumber(_ key: String, maximum: Double) throws -> Double? {
            guard let value = try positiveNumber(key) else { return nil }
            guard value <= maximum else {
                throw SchemaValidationError(field: key, observed: value, expected: "number in 0...\(maximum)")
            }
            return value
        }

        func boundedPositiveInteger(_ key: String, minimum: Int, maximum: Int) throws -> Int? {
            guard let value = try request.schemaInteger(key) else { return nil }
            guard value >= minimum && value <= maximum else {
                throw SchemaValidationError(field: key, observed: value, expected: "integer in \(minimum)...\(maximum)")
            }
            return value
        }

        func unitPoint(_ key: String) throws -> UnitPoint? {
            try request.schemaUnitPoint(key)
        }

        func enumValue<E>(
            _ key: String,
            as type: E.Type,
            normalizedBy normalize: (String) -> String = { $0 }
        ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.schemaEnum(key, as: type, normalizedBy: normalize)
        }

        func requiredObjectArray(_ key: String) throws -> [GestureRequestObject] {
            try request.requiredSchemaDictionaryArray(key).map(GestureRequestObject.init)
        }
    }

    private struct GestureRequestObject {
        private let dictionary: [String: Any]

        fileprivate init(_ dictionary: [String: Any]) {
            self.dictionary = dictionary
        }

        func requiredNumber(_ key: String, field: String) throws -> Double {
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

    private func decodeTouchTapGesturePayload(_ request: GestureRequestInput) throws -> TouchTapGesturePayload {
        let payload = TouchTapGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            pointX: try request.number("x"),
            pointY: try request.number("y")
        )
        if payload.elementTarget == nil, payload.target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return payload
    }

    private func decodeLongPressGesturePayload(_ request: GestureRequestInput) throws -> LongPressGesturePayload {
        let payload = LongPressGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            pointX: try request.number("x"),
            pointY: try request.number("y"),
            duration: try request.gestureDuration() ?? 0.5
        )
        if payload.elementTarget == nil, payload.target.point == nil {
            throw FenceError.invalidRequest("Must specify element (heistId or matcher) or coordinates (x, y)")
        }
        return payload
    }

    private func decodeSwipeGesturePayload(_ request: GestureRequestInput) throws -> SwipeGesturePayload {
        let start = try request.unitPoint("start")
        let end = try request.unitPoint("end")
        let payload = SwipeGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            startX: try request.number("startX"),
            startY: try request.number("startY"),
            endX: try request.number("endX"),
            endY: try request.number("endY"),
            direction: try request.enumValue("direction", as: SwipeDirection.self) { $0.lowercased() },
            duration: try request.gestureDuration(),
            start: start,
            end: end
        )
        let target = payload.target
        if (target.start != nil) != (target.end != nil) {
            throw FenceError.invalidRequest("Unit-point swipe requires both start and end")
        }
        return payload
    }

    private func decodeDragGesturePayload(_ request: GestureRequestInput) throws -> DragGesturePayload {
        DragGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            startX: try request.number("startX"),
            startY: try request.number("startY"),
            endX: try request.requiredNumber("endX"),
            endY: try request.requiredNumber("endY"),
            duration: try request.gestureDuration()
        )
    }

    private func decodePinchGesturePayload(_ request: GestureRequestInput) throws -> PinchGesturePayload {
        PinchGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            scale: try request.requiredPositiveNumber("scale"),
            spread: try request.positiveNumber("spread"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeRotateGesturePayload(_ request: GestureRequestInput) throws -> RotateGesturePayload {
        RotateGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            angle: try request.requiredNumber("angle"),
            radius: try request.positiveNumber("radius"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeTwoFingerTapGesturePayload(_ request: GestureRequestInput) throws -> TwoFingerTapGesturePayload {
        TwoFingerTapGesturePayload(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            spread: try request.positiveNumber("spread")
        )
    }

    private func decodeDrawPathGesturePayload(_ request: GestureRequestInput) throws -> DrawPathGesturePayload {
        let pointsArray = try request.requiredObjectArray("points")
        try validateArrayCount(
            field: "points",
            count: pointsArray.count,
            min: 2,
            max: DecodeLimits.maxDrawPathPoints,
            note: "at least 2 points"
        )
        let points = try pointsArray.enumerated().map { index, point -> PathPoint in
            PathPoint(
                x: try point.requiredNumber("x", field: "points[\(index)].x"),
                y: try point.requiredNumber("y", field: "points[\(index)].y")
            )
        }
        let duration = try request.boundedPositiveNumber(
            "duration",
            maximum: DecodeLimits.maxDrawGestureDurationSeconds
        )
        return DrawPathGesturePayload(
            points: points,
            duration: duration,
            velocity: try request.positiveNumber("velocity")
        )
    }

    private func decodeDrawBezierGesturePayload(_ request: GestureRequestInput) throws -> DrawBezierGesturePayload {
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
            BezierSegment(
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
        let resolvedSamplesPerSegment = samplesPerSegment ?? 20
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
        return DrawBezierGesturePayload(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: samplesPerSegment,
            duration: duration,
            velocity: try request.positiveNumber("velocity")
        )
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
}

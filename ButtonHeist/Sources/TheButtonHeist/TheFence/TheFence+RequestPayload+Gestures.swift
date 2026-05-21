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

    private struct TouchTapGestureRequest {
        let elementTarget: ElementTarget?
        let pointX: Double?
        let pointY: Double?

        var target: TouchTapTarget {
            TouchTapTarget(elementTarget: elementTarget, pointX: pointX, pointY: pointY)
        }
    }

    private func decodeTouchTapTarget(_ request: GestureRequestInput) throws -> TouchTapTarget {
        let payload = TouchTapGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            pointX: try request.number("x"),
            pointY: try request.number("y")
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

    private func decodeLongPressTarget(_ request: GestureRequestInput) throws -> LongPressTarget {
        let payload = LongPressGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            pointX: try request.number("x"),
            pointY: try request.number("y"),
            duration: try request.gestureDuration() ?? 0.5
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

    private func decodeSwipeTarget(_ request: GestureRequestInput) throws -> SwipeTarget {
        let start = try request.unitPoint("start")
        let end = try request.unitPoint("end")
        let payload = SwipeGestureRequest(
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

    private func decodeDragTarget(_ request: GestureRequestInput) throws -> DragTarget {
        DragGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            startX: try request.number("startX"),
            startY: try request.number("startY"),
            endX: try request.requiredNumber("endX"),
            endY: try request.requiredNumber("endY"),
            duration: try request.gestureDuration()
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

    private func decodePinchTarget(_ request: GestureRequestInput) throws -> PinchTarget {
        PinchGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            scale: try request.requiredPositiveNumber("scale"),
            spread: try request.positiveNumber("spread"),
            duration: try request.gestureDuration()
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

    private func decodeRotateTarget(_ request: GestureRequestInput) throws -> RotateTarget {
        RotateGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            angle: try request.requiredNumber("angle"),
            radius: try request.positiveNumber("radius"),
            duration: try request.gestureDuration()
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

    private func decodeTwoFingerTapTarget(_ request: GestureRequestInput) throws -> TwoFingerTapTarget {
        TwoFingerTapGestureRequest(
            elementTarget: try request.elementTarget(in: self),
            centerX: try request.number("centerX"),
            centerY: try request.number("centerY"),
            spread: try request.positiveNumber("spread")
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

    private func decodeDrawPathTarget(_ request: GestureRequestInput) throws -> DrawPathTarget {
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
        return DrawPathGestureRequest(
            points: points,
            duration: duration,
            velocity: try request.positiveNumber("velocity")
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

    private func decodeDrawBezierTarget(_ request: GestureRequestInput) throws -> DrawBezierTarget {
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
        return DrawBezierGestureRequest(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: samplesPerSegment,
            duration: duration,
            velocity: try request.positiveNumber("velocity")
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
}

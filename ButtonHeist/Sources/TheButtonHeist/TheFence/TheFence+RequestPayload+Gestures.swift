import Foundation

import TheScore

extension TheFence {

    func decodeGestureRequestDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        try decodeGestureAction(command: command, request: GestureRequestInput(arguments))
    }

    private func decodeGestureAction(
        command: Command,
        request: GestureRequestInput
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .oneFingerTap:
            return decodedGestureAction(.oneFingerTap(try decodeTapTarget(request)))
        case .longPress:
            return decodedGestureAction(.longPress(try decodeLongPressTarget(request)))
        case .swipe:
            return decodedGestureAction(.swipe(try decodeSwipeTarget(request)))
        case .drag:
            return decodedGestureAction(.drag(try decodeDragTarget(request)))
        case .pinch:
            return decodedGestureAction(.pinch(try decodePinchTarget(request)))
        case .rotate:
            return decodedGestureAction(.rotate(try decodeRotateTarget(request)))
        case .twoFingerTap:
            return decodedGestureAction(.twoFingerTap(try decodeTwoFingerTapTarget(request)))
        case .drawPath:
            return decodedGestureAction(.drawPath(try decodeDrawPathTarget(request)))
        case .drawBezier:
            return decodedGestureAction(.drawBezier(try decodeDrawBezierTarget(request)))
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private func decodedGestureAction(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }

    private struct GestureRequestInput {
        private let request: any CommandArgumentReadable

        init(_ request: some CommandArgumentReadable) {
            self.request = request
        }

        @ButtonHeistActor
        func elementTarget(in fence: TheFence) throws -> ElementTarget? {
            try fence.decodedElementTarget(request)
        }

        func number(_ key: String) throws -> Double? {
            try request.schemaNumber(key)
        }

        func hasAny(_ keys: String...) -> Bool {
            keys.contains { request.argumentValues[$0] != nil }
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
                throw SchemaValidationError(field: key, observed: "missing", expected: "number > 0")
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
            as type: E.Type
        ) throws -> E? where E: CaseIterable & RawRepresentable, E.RawValue == String {
            try request.schemaEnum(key, as: type)
        }

        func requiredObjectArray(_ key: String) throws -> [GestureRequestObject] {
            try request.requiredSchemaObjectArray(key).map(GestureRequestObject.init)
        }
    }

    private struct GestureRequestObject {
        private let object: CommandArgumentObject

        fileprivate init(_ object: CommandArgumentObject) {
            self.object = object
        }

        func rejectUnknownKeys(_ allowedKeys: Set<String>, expected: String) throws {
            try object.rejectUnknownKeys(allowed: allowedKeys, expected: expected)
        }

        func requiredNumber(_ key: String, field: String) throws -> Double {
            do {
                guard let value = try object.schemaNumber(key) else {
                    throw SchemaValidationError(field: field, observed: "missing", expected: "number")
                }
                return value
            } catch let error as SchemaValidationError {
                throw SchemaValidationError(field: field, observed: error.observed, expected: error.expected)
            }
        }
    }

    private func decodeRequiredPointIntent(
        request: GestureRequestInput,
        elementTarget: ElementTarget?,
        xKey: String,
        yKey: String,
        field: String,
        missingMessage: String
    ) throws -> GesturePointSelection {
        let point = try decodeCoordinatePair(request: request, xKey: xKey, yKey: yKey, field: field)
        if elementTarget != nil, point != nil {
            throw mixedGestureShape(field: field, expected: "target object or coordinates")
        }
        if let elementTarget {
            return .element(elementTarget)
        }
        if let point {
            return .coordinate(ScreenPoint(x: point.x, y: point.y))
        }
        throw FenceError.invalidRequest(missingMessage)
    }

    private func decodeOptionalPointIntent(
        request: GestureRequestInput,
        elementTarget: ElementTarget?,
        xKey: String,
        yKey: String,
        field: String
    ) throws -> GesturePointSelection {
        let point = try decodeCoordinatePair(request: request, xKey: xKey, yKey: yKey, field: field)
        if elementTarget != nil, point != nil {
            throw mixedGestureShape(field: field, expected: "target object or coordinates")
        }
        if let elementTarget {
            return .element(elementTarget)
        }
        if let point {
            return .coordinate(ScreenPoint(x: point.x, y: point.y))
        }
        return .unspecified
    }

    private func decodeCoordinatePair(
        request: GestureRequestInput,
        xKey: String,
        yKey: String,
        field: String
    ) throws -> (x: Double, y: Double)? {
        let x = try request.number(xKey)
        let y = try request.number(yKey)
        guard (x != nil) == (y != nil) else {
            throw SchemaValidationError(
                field: field,
                observed: "partial coordinates",
                expected: "both \(xKey) and \(yKey), or neither"
            )
        }
        guard let x, let y else { return nil }
        return (x, y)
    }

    private func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }

    private func decodeTapTarget(_ request: GestureRequestInput) throws -> TapTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return TapTarget(selection: selection)
    }

    private func decodeLongPressTarget(_ request: GestureRequestInput) throws -> LongPressTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return LongPressTarget(selection: selection, duration: try request.gestureDuration() ?? 0.5)
    }

    private func decodeSwipeTarget(_ request: GestureRequestInput) throws -> SwipeTarget {
        let start = try request.unitPoint("start")
        let end = try request.unitPoint("end")
        if (start != nil) != (end != nil) {
            throw FenceError.invalidRequest("Unit-point swipe requires both start and end")
        }
        let elementTarget = try request.elementTarget(in: self)
        let direction = try request.enumValue("direction", as: SwipeDirection.self)
        let startPoint = try decodeCoordinatePair(request: request, xKey: "startX", yKey: "startY", field: "startX/startY")
        let endPoint = try decodeCoordinatePair(request: request, xKey: "endX", yKey: "endY", field: "endX/endY")
        if start != nil || end != nil, request.hasAny("startX", "startY", "endX", "endY") {
            throw mixedGestureShape(field: "start/end", expected: "unit points or absolute coordinates")
        }
        if start != nil || end != nil, direction != nil {
            throw mixedGestureShape(field: "start/end", expected: "unit points or direction defaults")
        }
        if let start, let end {
            guard let elementTarget else {
                throw FenceError.invalidRequest("Unit-point swipe requires target object")
            }
            return SwipeTarget(
                selection: .unitElement(elementTarget, start: start, end: end, direction: direction),
                duration: try request.gestureDuration()
            )
        }
        if elementTarget != nil, startPoint != nil {
            throw mixedGestureShape(field: "startX/startY", expected: "target object or absolute start coordinates")
        }
        if endPoint != nil, direction != nil {
            throw mixedGestureShape(field: "endX/endY", expected: "end coordinates or direction")
        }
        let startSelection: GesturePointSelection
        if let elementTarget {
            startSelection = .element(elementTarget)
        } else if let startPoint {
            startSelection = .coordinate(ScreenPoint(x: startPoint.x, y: startPoint.y))
        } else {
            throw FenceError.invalidRequest(
                "Swipe requires target object or start coordinates (startX, startY)"
            )
        }
        let endSelection: SwipeDestinationSelection
        if let direction {
            endSelection = .direction(direction)
        } else if let endPoint {
            endSelection = .coordinate(ScreenPoint(x: endPoint.x, y: endPoint.y))
        } else {
            throw FenceError.invalidRequest("Swipe requires end coordinates (endX, endY) or direction")
        }
        let selection = SwipeGestureSelection.point(
            start: startSelection,
            destination: endSelection
        )
        return SwipeTarget(selection: selection, duration: try request.gestureDuration())
    }

    private func decodeDragTarget(_ request: GestureRequestInput) throws -> DragTarget {
        let start = try decodeOptionalPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "startX",
            yKey: "startY",
            field: "startX/startY"
        )
        return DragTarget(
            start: start,
            end: ScreenPoint(
                x: try request.requiredNumber("endX"),
                y: try request.requiredNumber("endY")
            ),
            duration: try request.gestureDuration()
        )
    }

    private func decodePinchTarget(_ request: GestureRequestInput) throws -> PinchTarget {
        let scale = try request.requiredPositiveNumber("scale")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Pinch requires target object or center coordinates (centerX, centerY)"
        )
        return PinchTarget(
            center: center,
            scale: scale,
            spread: try request.positiveNumber("spread"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeRotateTarget(_ request: GestureRequestInput) throws -> RotateTarget {
        let angle = try request.requiredNumber("angle")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Rotate requires target object or center coordinates (centerX, centerY)"
        )
        return RotateTarget(
            center: center,
            angle: angle,
            radius: try request.positiveNumber("radius"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeTwoFingerTapTarget(_ request: GestureRequestInput) throws -> TwoFingerTapTarget {
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Two finger tap requires target object or center coordinates (centerX, centerY)"
        )
        return TwoFingerTapTarget(
            center: center,
            spread: try request.positiveNumber("spread")
        )
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

    private func validateDrawTiming(duration: Double?, velocity: Double?) throws {
        guard duration == nil || velocity == nil else {
            throw SchemaValidationError(
                field: "duration/velocity",
                observed: "both duration and velocity",
                expected: "duration or velocity"
            )
        }
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

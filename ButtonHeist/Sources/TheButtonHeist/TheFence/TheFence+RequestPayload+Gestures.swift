import Foundation

import TheScore

extension TheFence.GesturePayload {

    var clientMessage: ClientMessage {
        switch self {
        case .oneFingerTap(let payload):
            return .oneFingerTap(payload.target)
        case .longPress(let payload):
            return .longPress(payload.target)
        case .swipe(let payload):
            return .swipe(payload.target)
        case .drag(let payload):
            return .drag(payload.target)
        case .pinch(let payload):
            return .pinch(payload.target)
        case .rotate(let payload):
            return .rotate(payload.target)
        case .twoFingerTap(let payload):
            return .twoFingerTap(payload.target)
        case .drawPath(let payload):
            return .drawPath(payload.target)
        case .drawBezier(let payload):
            return .drawBezier(payload.target)
        }
    }
}

extension TheFence {

    func decodeGestureRequestPayload(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestPayload {
        let payload = try decodeGesturePayload(command: command, request: GestureRequestInput(arguments))
        return DecodedRequestPayload(
            payload: .gesture(payload),
            executableMessages: [payload.clientMessage]
        )
    }

    private func decodeGesturePayload(
        command: Command,
        request: GestureRequestInput
    ) throws -> GesturePayload {
        switch command {
        case .oneFingerTap:
            return .oneFingerTap(try decodeTapGesturePayload(request))
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
                    throw SchemaValidationError(field: field, observed: nil, expected: "number")
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

    private func decodeTapGesturePayload(_ request: GestureRequestInput) throws -> TapGesturePayload {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return TapGesturePayload(selection: selection)
    }

    private func decodeLongPressGesturePayload(_ request: GestureRequestInput) throws -> LongPressGesturePayload {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return LongPressGesturePayload(selection: selection, duration: try request.gestureDuration() ?? 0.5)
    }

    private func decodeSwipeGesturePayload(_ request: GestureRequestInput) throws -> SwipeGesturePayload {
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
            return SwipeGesturePayload(
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
        let payload = SwipeGesturePayload(selection: selection, duration: try request.gestureDuration())
        return payload
    }

    private func decodeDragGesturePayload(_ request: GestureRequestInput) throws -> DragGesturePayload {
        let start = try decodeOptionalPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "startX",
            yKey: "startY",
            field: "startX/startY"
        )
        return DragGesturePayload(
            start: start,
            endX: try request.requiredNumber("endX"),
            endY: try request.requiredNumber("endY"),
            duration: try request.gestureDuration()
        )
    }

    private func decodePinchGesturePayload(_ request: GestureRequestInput) throws -> PinchGesturePayload {
        let scale = try request.requiredPositiveNumber("scale")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Pinch requires target object or center coordinates (centerX, centerY)"
        )
        return PinchGesturePayload(
            center: center,
            scale: scale,
            spread: try request.positiveNumber("spread"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeRotateGesturePayload(_ request: GestureRequestInput) throws -> RotateGesturePayload {
        let angle = try request.requiredNumber("angle")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Rotate requires target object or center coordinates (centerX, centerY)"
        )
        return RotateGesturePayload(
            center: center,
            angle: angle,
            radius: try request.positiveNumber("radius"),
            duration: try request.gestureDuration()
        )
    }

    private func decodeTwoFingerTapGesturePayload(_ request: GestureRequestInput) throws -> TwoFingerTapGesturePayload {
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Two finger tap requires target object or center coordinates (centerX, centerY)"
        )
        return TwoFingerTapGesturePayload(
            center: center,
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
        return DrawPathGesturePayload(
            points: points,
            duration: duration,
            velocity: velocity
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
        return DrawBezierGesturePayload(
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

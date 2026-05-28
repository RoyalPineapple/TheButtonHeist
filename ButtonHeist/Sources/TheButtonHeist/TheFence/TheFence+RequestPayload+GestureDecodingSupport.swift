import Foundation

import TheScore

extension TheFence {

    struct GestureRequestInput {
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

    struct GestureRequestObject {
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

    func decodeRequiredPointIntent(
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

    func decodeOptionalPointIntent(
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

    func decodeCoordinatePair(
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

    func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }

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

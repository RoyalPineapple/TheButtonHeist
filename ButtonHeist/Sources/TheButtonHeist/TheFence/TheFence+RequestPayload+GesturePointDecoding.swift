import Foundation

import TheScore

extension TheFence.CommandArgumentEnvelope {
    func schemaUnitPoint(_ key: String) throws -> UnitPoint? {
        guard let value = argumentValues[key] else { return nil }
        guard case .object(let values) = value else {
            throw SchemaValidationError(
                field: field(key),
                observed: value.schemaObservedDescription,
                expected: "object with numeric x and y"
            )
        }
        let object = TheFence.CommandArgumentEnvelope(values: values, fieldPrefix: field(key))
        try object.rejectUnknownKeys(allowed: UnitPoint.fieldNames, expected: "valid unit point field")
        guard let x = try object.schemaNumber("x") else {
            throw SchemaValidationError(field: object.field("x"), observed: "missing", expected: "number")
        }
        guard let y = try object.schemaNumber("y") else {
            throw SchemaValidationError(field: object.field("y"), observed: "missing", expected: "number")
        }
        guard (0...1).contains(x) else {
            throw SchemaValidationError(field: object.field("x"), observed: x, expected: "number in 0...1")
        }
        guard (0...1).contains(y) else {
            throw SchemaValidationError(field: object.field("y"), observed: y, expected: "number in 0...1")
        }
        return UnitPoint(x: x, y: y)
    }
}

extension TheFence {

    func decodeRequiredPointIntent(
        request: CommandArgumentEnvelope,
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
            return .coordinate(point)
        }
        throw FenceError.invalidRequest(missingMessage)
    }

    func decodeCoordinatePair(
        request: CommandArgumentEnvelope,
        xKey: String,
        yKey: String,
        field: String
    ) throws -> ScreenPoint? {
        let x = try request.schemaNumber(xKey)
        let y = try request.schemaNumber(yKey)
        guard (x != nil) == (y != nil) else {
            throw SchemaValidationError(
                field: field,
                observed: "partial coordinates",
                expected: "both \(xKey) and \(yKey), or neither"
            )
        }
        guard let x, let y else { return nil }
        return ScreenPoint(x: x, y: y)
    }

    func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }
}

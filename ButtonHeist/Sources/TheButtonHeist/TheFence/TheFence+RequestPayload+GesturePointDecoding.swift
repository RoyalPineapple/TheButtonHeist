import Foundation
import ThePlans

import TheScore

extension TheFence.CommandArgumentEnvelope {
    @ButtonHeistActor
    func schemaGestureElementTarget(_ key: String) throws -> ElementTarget? {
        guard let object = try schemaDictionary(key) else { return nil }
        return try object.decodeElementTargetPayload()
    }

    func schemaScreenPoint(_ key: String) throws -> ScreenPoint? {
        guard let object = try schemaDictionary(key) else { return nil }
        try object.rejectUnknownKeys(allowed: Set(["x", "y"]), expected: "valid screen point field")
        return ScreenPoint(
            x: try object.requiredSchemaNumber("x"),
            y: try object.requiredSchemaNumber("y")
        )
    }

    func requiredScreenPoint(_ key: String) throws -> ScreenPoint {
        guard let point = try schemaScreenPoint(key) else {
            throw SchemaValidationError(field: field(key), observed: "missing", expected: "object")
        }
        return point
    }

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
    @ButtonHeistActor
    func decodePointSelection(
        request: CommandArgumentEnvelope,
        elementKey: String = "element",
        unitPointKey: String = "unitPoint",
        pointKey: String = "point"
    ) throws -> GesturePointSelection {
        let element = try request.schemaGestureElementTarget(elementKey)
        let unitPoint = try request.schemaUnitPoint(unitPointKey)
        let point = try request.schemaScreenPoint(pointKey)
        switch (element, unitPoint, point) {
        case (.some(let element), nil, nil):
            return .element(element)
        case (.some(let element), .some(let unitPoint), nil):
            return .elementUnitPoint(element, unitPoint)
        case (nil, nil, .some(let point)):
            return .coordinate(point)
        case (.some, _, .some), (nil, .some, .some):
            throw mixedGestureShape(field: "\(elementKey)/\(unitPointKey)/\(pointKey)", expected: "element, element with unitPoint, or point")
        case (nil, .some, nil):
            throw SchemaValidationError(field: unitPointKey, observed: "unit point without element", expected: "element with unitPoint")
        case (nil, nil, nil):
            throw FenceError.invalidRequest("Must specify element or point")
        }
    }

    func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }
}

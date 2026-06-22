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
        pointKey: String = "point"
    ) throws -> GesturePointSelection {
        let element = try request.schemaGestureElementTarget(elementKey)
        let point = try request.schemaScreenPoint(pointKey)
        switch (element, point) {
        case (.some(let element), nil):
            return .element(element)
        case (nil, .some(let point)):
            return .coordinate(point)
        case (.some, .some):
            throw mixedGestureShape(field: "\(elementKey)/\(pointKey)", expected: "element or point")
        case (nil, nil):
            throw FenceError.invalidRequest("Must specify element or point")
        }
    }

    func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }
}

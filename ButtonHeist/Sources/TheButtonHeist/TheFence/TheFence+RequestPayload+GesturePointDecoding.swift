import Foundation

import TheScore

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

import Foundation

import TheScore

extension TheFence {

    struct GestureCoordinatePair {
        let point: ScreenPoint?

        static func decode(
            request: GestureRequestInput,
            xKey: String,
            yKey: String,
            field: String
        ) throws -> GestureCoordinatePair {
            let x = try request.number(xKey)
            let y = try request.number(yKey)
            guard (x != nil) == (y != nil) else {
                throw SchemaValidationError(
                    field: field,
                    observed: "partial coordinates",
                    expected: "both \(xKey) and \(yKey), or neither"
                )
            }
            guard let x, let y else { return GestureCoordinatePair(point: nil) }
            return GestureCoordinatePair(point: ScreenPoint(x: x, y: y))
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
        let coordinate = try GestureCoordinatePair.decode(request: request, xKey: xKey, yKey: yKey, field: field)
        if elementTarget != nil, coordinate.point != nil {
            throw mixedGestureShape(field: field, expected: "target object or coordinates")
        }
        if let elementTarget {
            return .element(elementTarget)
        }
        if let point = coordinate.point {
            return .coordinate(point)
        }
        throw FenceError.invalidRequest(missingMessage)
    }

    func decodeCoordinatePair(
        request: GestureRequestInput,
        xKey: String,
        yKey: String,
        field: String
    ) throws -> ScreenPoint? {
        try GestureCoordinatePair.decode(request: request, xKey: xKey, yKey: yKey, field: field).point
    }

    func mixedGestureShape(field: String, expected: String) -> SchemaValidationError {
        SchemaValidationError(field: field, observed: "mixed gesture target shapes", expected: expected)
    }
}

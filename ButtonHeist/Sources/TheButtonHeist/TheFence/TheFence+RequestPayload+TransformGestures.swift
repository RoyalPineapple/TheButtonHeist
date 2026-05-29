import Foundation

import TheScore

extension TheFence {

    func decodePinchTarget(_ request: CommandArgumentEnvelope) throws -> PinchTarget {
        let scale = try request.requiredSchemaNumber("scale")
        let target = PinchTarget(
            center: try decodeRequiredPointIntent(
                request: request,
                elementTarget: try request.decodedElementTarget(),
                xKey: "centerX",
                yKey: "centerY",
                field: "centerX/centerY",
                missingMessage: "center requires an element target or center coordinates"
            ),
            scale: scale,
            spread: try request.schemaNumber("spread"),
            duration: try request.gestureDuration()
        )
        try validatePositiveGestureNumber(target.scale, field: "scale")
        try validatePositiveGestureNumber(target.spread, field: "spread")
        return target
    }

    func decodeRotateTarget(_ request: CommandArgumentEnvelope) throws -> RotateTarget {
        let angle = try request.requiredSchemaNumber("angle")
        let target = RotateTarget(
            center: try decodeRequiredPointIntent(
                request: request,
                elementTarget: try request.decodedElementTarget(),
                xKey: "centerX",
                yKey: "centerY",
                field: "centerX/centerY",
                missingMessage: "center requires an element target or center coordinates"
            ),
            angle: angle,
            radius: try request.schemaNumber("radius"),
            duration: try request.gestureDuration()
        )
        try validatePositiveGestureNumber(target.radius, field: "radius")
        return target
    }
}

import Foundation

import TheScore

extension TheFence {

    func decodePinchTarget(_ request: some CommandArgumentReadable) throws -> PinchTarget {
        let scale = try request.requiredNumber("scale")
        let target = PinchTarget(
            center: try decodeRequiredPointIntent(
                request: request,
                elementTarget: try request.elementTarget(),
                xKey: "centerX",
                yKey: "centerY",
                field: "centerX/centerY",
                missingMessage: "center requires an element target or center coordinates"
            ),
            scale: scale,
            spread: try request.number("spread"),
            duration: try request.gestureDuration()
        )
        try validatePositiveGestureNumber(target.scale, field: "scale")
        try validatePositiveGestureNumber(target.spread, field: "spread")
        return target
    }

    func decodeRotateTarget(_ request: some CommandArgumentReadable) throws -> RotateTarget {
        let angle = try request.requiredNumber("angle")
        let target = RotateTarget(
            center: try decodeRequiredPointIntent(
                request: request,
                elementTarget: try request.elementTarget(),
                xKey: "centerX",
                yKey: "centerY",
                field: "centerX/centerY",
                missingMessage: "center requires an element target or center coordinates"
            ),
            angle: angle,
            radius: try request.number("radius"),
            duration: try request.gestureDuration()
        )
        try validatePositiveGestureNumber(target.radius, field: "radius")
        return target
    }
}

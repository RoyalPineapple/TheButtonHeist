import Foundation

import TheScore

extension TheFence {

    func decodePinchTarget(_ request: some CommandArgumentReadable) throws -> PinchTarget {
        let scale = try request.requiredPositiveNumber("scale")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try decodedElementTarget(request),
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

    func decodeRotateTarget(_ request: some CommandArgumentReadable) throws -> RotateTarget {
        let angle = try request.requiredNumber("angle")
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try decodedElementTarget(request),
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
}

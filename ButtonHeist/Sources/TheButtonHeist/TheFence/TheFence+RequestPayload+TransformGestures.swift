import Foundation

import TheScore

extension TheFence {

    func decodePinchTarget(_ request: some CommandArgumentReadable) throws -> PinchTarget {
        let target = try request.inlineElementTargetArgument().decodeCommandPayload(PinchTarget.self)
        try validatePositiveGestureNumber(target.scale, field: "scale")
        try validatePositiveGestureNumber(target.spread, field: "spread")
        try validateGestureDuration(target.duration)
        return target
    }

    func decodeRotateTarget(_ request: some CommandArgumentReadable) throws -> RotateTarget {
        let target = try request.inlineElementTargetArgument().decodeCommandPayload(RotateTarget.self)
        try validatePositiveGestureNumber(target.radius, field: "radius")
        try validateGestureDuration(target.duration)
        return target
    }
}

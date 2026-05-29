import Foundation

import TheScore

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.decodedElementTarget(),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return TapTarget(selection: selection)
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.decodedElementTarget(),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return LongPressTarget(selection: selection, duration: try request.gestureDuration() ?? 0.5)
    }

    func decodeTwoFingerTapTarget(_ request: CommandArgumentEnvelope) throws -> TwoFingerTapTarget {
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.decodedElementTarget(),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "center requires an element target or center coordinates"
        )
        let target = TwoFingerTapTarget(center: center, spread: try request.schemaNumber("spread"))
        try validatePositiveGestureNumber(target.spread, field: "spread")
        return target
    }
}

import Foundation

import TheScore

extension TheFence {

    func decodeTapTarget(_ request: GestureRequestInput) throws -> TapTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return TapTarget(selection: selection)
    }

    func decodeLongPressTarget(_ request: GestureRequestInput) throws -> LongPressTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return LongPressTarget(selection: selection, duration: try request.gestureDuration() ?? 0.5)
    }

    func decodeTwoFingerTapTarget(_ request: GestureRequestInput) throws -> TwoFingerTapTarget {
        let center = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.elementTarget(in: self),
            xKey: "centerX",
            yKey: "centerY",
            field: "centerX/centerY",
            missingMessage: "Two finger tap requires target object or center coordinates (centerX, centerY)"
        )
        return TwoFingerTapTarget(
            center: center,
            spread: try request.positiveNumber("spread")
        )
    }
}

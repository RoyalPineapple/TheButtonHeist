import Foundation

import TheScore

extension TheFence {

    func decodeTapTarget(_ request: some CommandArgumentReadable) throws -> TapTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try decodedElementTarget(request),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return TapTarget(selection: selection)
    }

    func decodeLongPressTarget(_ request: some CommandArgumentReadable) throws -> LongPressTarget {
        let selection = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try decodedElementTarget(request),
            xKey: "x",
            yKey: "y",
            field: "x/y",
            missingMessage: "Must specify target object or coordinates (x, y)"
        )
        return LongPressTarget(selection: selection, duration: try request.gestureDuration() ?? 0.5)
    }

    func decodeTwoFingerTapTarget(_ request: some CommandArgumentReadable) throws -> TwoFingerTapTarget {
        let target = try request.inlineElementTargetArgument().decodeCommandPayload(TwoFingerTapTarget.self)
        try validatePositiveGestureNumber(target.spread, field: "spread")
        return target
    }
}

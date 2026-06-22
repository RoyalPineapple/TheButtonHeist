import Foundation
import ThePlans

import TheScore

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        let selection = try decodePointSelection(request: request)
        return TapTarget(selection: selection)
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        let selection = try decodePointSelection(request: request)
        return LongPressTarget(selection: selection, duration: try request.gestureDuration() ?? .longPressDefault)
    }

}

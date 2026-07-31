import Foundation
import ButtonHeistSupport

import TheScore

extension FenceError {
    init(_ connectionError: HandoffConnectionError) {
        self = .connectionFailure(ConnectionFailure(connectionError: connectionError))
    }

    init(_ sendFailure: DeviceSendFailure) {
        switch sendFailure {
        case .notConnected:
            self = .notConnected
        case .encodingFailed(let failure):
            self = .actionFailed("Failed to send request: \(failure.description)")
        case .transportFailed(let failure):
            self = .connectionFailure(ConnectionFailure(deviceTransportFailure: failure))
        }
    }
}

private extension ConnectionFailure {
    init(deviceTransportFailure failure: NetworkTransportFailure) {
        self.init(
            message: "Transport send failed: \(failure.description)",
            details: FailureDetails(code: .transportNetworkError)
        )
    }
}

import Foundation
import ButtonHeistSupport

import TheScore

extension FenceError {
    init(_ connectionError: HandoffConnectionError) {
        switch connectionError {
        case .connectionFailed(let message): self = .connectionFailed(message)
        case .disconnected(.sessionLocked(let message)): self = .sessionLocked(message)
        case .disconnected(let reason): self = .connectionFailure(ConnectionFailure(disconnectReason: reason))
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        case .ambiguousDeviceTarget(let filter, let matches): self = .noMatchingDevice(filter: filter, available: matches)
        }
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
        let details = FailureDetails(code: .transportNetworkError)
        self.init(
            message: "Transport send failed: \(failure.description)",
            failureCode: details.code,
            hint: details.hint
        )
    }
}

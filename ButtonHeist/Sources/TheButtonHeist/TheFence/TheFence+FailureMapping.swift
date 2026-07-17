import Foundation
import ButtonHeistSupport

import TheScore

extension FenceError {
    init(_ connectionError: HandoffConnectionError) {
        switch connectionError {
        case .connectionFailed(let message): self = .connectionFailed(message)
        case .discoveryBacklogOverflow:
            self = .connectionFailed(connectionError.diagnostic.cause)
        case .serverFailure(let serverError):
            let details = serverError.failureDetails
            self = .connectionFailure(ConnectionFailure(
                message: serverError.message.description,
                failureCode: details.code,
                hint: serverError.recoveryHint?.description ?? details.hint
            ))
        case .disconnected(.sessionLocked(let message)): self = .sessionLocked(message)
        case .disconnected(let reason): self = .connectionFailure(ConnectionFailure(disconnectReason: reason))
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        case .ambiguousDeviceTarget(let filter, let matches): self = .ambiguousDeviceTarget(filter: filter, matches: matches)
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
    init(handoffDiagnostic diagnostic: HandoffFailureDiagnostic) {
        self.init(
            message: HandoffFailureFormatter.message(for: diagnostic),
            failureCode: diagnostic.details.code,
            hint: diagnostic.hint
        )
    }

    init(deviceTransportFailure failure: NetworkTransportFailure) {
        let details = FailureDetails(code: .transportNetworkError)
        self.init(
            message: "Transport send failed: \(failure.description)",
            failureCode: details.code,
            hint: details.hint
        )
    }
}

#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheGetaway {

    enum BroadcastDeliveryFailure: Error, Sendable, Equatable, CustomStringConvertible {
        case sessionContractViolation(String)
        case responseEncodingFailed(ResponseEncodingFailure)
        case connectionUnavailable(clientId: Int?)
        case connectionClosed(clientId: Int)
        case sendFailed(clientId: Int, ServerSendFailure)

        var description: String {
            switch self {
            case .sessionContractViolation(let message):
                return "Session contract failure while broadcasting response envelope: \(message)"
            case .responseEncodingFailed(let failure):
                return failure.description
            case .connectionUnavailable(let clientId):
                if let clientId {
                    return "Connection failure while broadcasting response envelope to client \(clientId): transport is unavailable"
                }
                return "Connection failure while broadcasting response envelope: no transport is wired"
            case .connectionClosed(let clientId):
                return "Connection failure while broadcasting response envelope to client \(clientId): client is no longer connected"
            case .sendFailed(let clientId, let failure):
                return "Send failure while broadcasting response envelope to client \(clientId): \(failure.localizedDescription)"
            }
        }

        init(clientId: Int, sendFailure: ServerSendFailure) {
            switch sendFailure {
            case .clientNotFound:
                self = .connectionClosed(clientId: clientId)
            case .transportUnavailable:
                self = .connectionUnavailable(clientId: clientId)
            case .transportFailed, .payloadTooLarge, .sendBufferFull:
                self = .sendFailed(clientId: clientId, sendFailure)
            }
        }
    }

    /// Broadcast a server message to every authenticated client.
    ///
    /// Awaits the transport so two back-to-back `broadcastToAll` calls from
    /// the same caller deliver in FIFO order. The previous sync shape used
    /// fire-and-forget Tasks under the hood, which made no FIFO guarantee.
    @discardableResult
    func broadcastToAll(_ message: ServerMessage) async -> Result<Void, BroadcastDeliveryFailure> {
        guard !message.isScreenshot else {
            let failure = BroadcastDeliveryFailure.sessionContractViolation(
                "screenshots must be requested explicitly"
            )
            insideJobLogger.error("\(failure.description)")
            return .failure(failure)
        }
        let data: Data
        switch encodeEnvelope(message) {
        case .success(let envelopeData):
            data = envelopeData
        case .failure(let failure):
            logEncodingFailure(failure)
            return .failure(.responseEncodingFailed(failure))
        }
        guard transport != nil else {
            let failure = BroadcastDeliveryFailure.connectionUnavailable(clientId: nil)
            insideJobLogger.error("\(failure.description)")
            return .failure(failure)
        }
        var firstFailure: BroadcastDeliveryFailure?
        for clientId in await muscle.authenticatedClientIDs.sorted() {
            switch await muscle.sendData(data, toClient: clientId) {
            case .enqueued:
                continue
            case .failed(let sendFailure):
                let failure = BroadcastDeliveryFailure(clientId: clientId, sendFailure: sendFailure)
                insideJobLogger.error("\(failure.description)")
                if firstFailure == nil {
                    firstFailure = failure
                }
            }
        }
        if let firstFailure {
            return .failure(firstFailure)
        }
        return .success(())
    }
}

private extension ServerMessage {
    var isScreenshot: Bool {
        if case .screen = self { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

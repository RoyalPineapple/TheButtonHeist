#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum ResponseDeliveryResult: Sendable, Equatable, CustomStringConvertible {
    case delivered
    case refused(ResponseDeliveryFailure)
    case transportUnavailable(clientId: Int?)
    case failed(ResponseDeliveryFailure)

    var didDeliver: Bool {
        if case .delivered = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .delivered:
            return "Delivered response envelope"
        case .refused(let failure), .failed(let failure):
            return failure.description
        case .transportUnavailable(let clientId):
            if let clientId {
                return "Connection failure while delivering response envelope to client \(clientId): transport is unavailable"
            }
            return "Connection failure while delivering response envelope: no transport is wired"
        }
    }

    init(clientId: Int, sendFailure: ServerSendFailure) {
        switch sendFailure {
        case .clientNotFound:
            self = .failed(.connectionClosed(clientId: clientId))
        case .transportUnavailable:
            self = .transportUnavailable(clientId: clientId)
        case .transportFailed, .payloadTooLarge, .sendBufferFull:
            self = .failed(.sendFailed(clientId: clientId, sendFailure))
        }
    }
}

enum ResponseDeliveryFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case sessionContractViolation(String)
    case responseEncodingFailed(ResponseEncodingFailure)
    case connectionClosed(clientId: Int)
    case sendFailed(clientId: Int, ServerSendFailure)

    var description: String {
        switch self {
        case .sessionContractViolation(let message):
            return "Session contract failure while delivering response envelope: \(message)"
        case .responseEncodingFailed(let failure):
            return failure.description
        case .connectionClosed(let clientId):
            return "Connection failure while delivering response envelope to client \(clientId): client is no longer connected"
        case .sendFailed(let clientId, let failure):
            return "Send failure while delivering response envelope to client \(clientId): \(failure.localizedDescription)"
        }
    }
}

struct ResponseEncodingFailure: Error, Sendable, Equatable, CustomStringConvertible {
    let requestId: String?
    let underlyingDescription: String

    var description: String {
        if let requestId {
            return "Failed to encode response envelope for request \(requestId): \(underlyingDescription)"
        }
        return "Failed to encode response envelope: \(underlyingDescription)"
    }
}

enum ResponseEnvelopeDelivery {
    static func encodeEnvelope(
        _ message: ServerMessage,
        requestId: String? = nil
    ) -> Result<Data, ResponseEncodingFailure> {
        do {
            let envelopeData = try ResponseEnvelope(
                requestId: requestId,
                message: message
            ).encoded()
            return .success(envelopeData)
        } catch {
            return .failure(.init(requestId: requestId, underlyingDescription: String(describing: error)))
        }
    }

    static func sendMessage(
        _ message: ServerMessage,
        requestId: String? = nil,
        respond: @escaping (Data) -> Void
    ) -> ResponseDeliveryResult {
        switch encodeEnvelope(
            message,
            requestId: requestId
        ) {
        case .success(let data):
            insideJobLogger.debug("Sending \(data.count) bytes")
            respond(data)
            return .delivered
        case .failure(let failure):
            return .failed(.responseEncodingFailed(failure))
        }
    }
}

extension TheGetaway {

    typealias DeliveryResult = ResponseDeliveryResult
    typealias DeliveryFailure = ResponseDeliveryFailure

    // MARK: - Encode / Decode

    func encodeEnvelope(
        _ message: ServerMessage,
        requestId: String? = nil
    ) -> Result<Data, ResponseEncodingFailure> {
        ResponseEnvelopeDelivery.encodeEnvelope(message, requestId: requestId)
    }

    func logEncodingFailure(_ failure: ResponseEncodingFailure) {
        insideJobLogger.error("\(failure.description)")
    }

    func logDeliveryFailure(_ failure: DeliveryFailure) {
        insideJobLogger.error("\(failure.description)")
    }

    func logDeliveryResult(_ result: DeliveryResult) {
        switch result {
        case .delivered:
            break
        case .refused(let failure), .failed(let failure):
            logDeliveryFailure(failure)
        case .transportUnavailable:
            insideJobLogger.error("\(result.description)")
        }
    }

    @discardableResult
    func sendMessage(
        _ message: ServerMessage,
        requestId: String? = nil,
        respond: @escaping (Data) -> Void
    ) -> DeliveryResult {
        let result = ResponseEnvelopeDelivery.sendMessage(message, requestId: requestId, respond: respond)
        logDeliveryResult(result)
        return result
    }

    func sendEncodedData(_ data: Data, toClient clientId: Int) async -> DeliveryResult {
        switch await muscle.sendData(data, toClient: clientId) {
        case .enqueued:
            return .delivered
        case .failed(let sendFailure):
            return DeliveryResult(clientId: clientId, sendFailure: sendFailure)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheGetaway {

    // MARK: - Encode / Decode

    enum DeliveryResult: Sendable, Equatable, CustomStringConvertible {
        case delivered
        case refused(DeliveryFailure)
        case transportUnavailable(clientId: Int?)
        case failed(DeliveryFailure)

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

    enum DeliveryFailure: Error, Sendable, Equatable, CustomStringConvertible {
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

    struct RequestDecodeFailure: Error, Sendable, CustomStringConvertible {
        let underlyingDescription: String

        var description: String {
            "Failed to decode client message: \(underlyingDescription)"
        }

        var serverError: ServerError {
            ServerError(kind: .general, message: "Malformed message — could not decode")
        }
    }

    func encodeEnvelope(
        _ message: ServerMessage,
        requestId: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil
    ) -> Result<Data, ResponseEncodingFailure> {
        do {
            let envelopeData = try ResponseEnvelope(
                requestId: requestId,
                message: message,
                accessibilityTrace: accessibilityTrace
            ).encoded()
            return .success(envelopeData)
        } catch {
            return .failure(.init(requestId: requestId, underlyingDescription: String(describing: error)))
        }
    }

    func decodeRequest(_ data: Data) -> Result<RequestEnvelope, RequestDecodeFailure> {
        do {
            return .success(try RequestEnvelope.decoded(from: data))
        } catch {
            return .failure(.init(underlyingDescription: String(describing: error)))
        }
    }

    func logEncodingFailure(_ failure: ResponseEncodingFailure) {
        insideJobLogger.error("\(failure.description)")
    }

    func logDeliveryFailure(_ failure: DeliveryFailure) {
        insideJobLogger.error("\(failure.description)")
    }

    @discardableResult
    func sendMessage(
        _ message: ServerMessage,
        requestId: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        respond: @escaping (Data) -> Void
    ) -> DeliveryResult {
        switch encodeEnvelope(
            message,
            requestId: requestId,
            accessibilityTrace: accessibilityTrace
        ) {
        case .success(let data):
            insideJobLogger.debug("Sending \(data.count) bytes")
            respond(data)
            return .delivered
        case .failure(let failure):
            logEncodingFailure(failure)
            return .failed(.responseEncodingFailed(failure))
        }
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

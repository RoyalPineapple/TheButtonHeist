#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheGetaway {

    // MARK: - Encode / Decode

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

    @discardableResult
    func sendMessage(
        _ message: ServerMessage,
        requestId: String? = nil,
        accessibilityTrace: AccessibilityTrace? = nil,
        respond: @escaping (Data) -> Void
    ) -> Result<Void, ResponseEncodingFailure> {
        switch encodeEnvelope(
            message,
            requestId: requestId,
            accessibilityTrace: accessibilityTrace
        ) {
        case .success(let data):
            insideJobLogger.debug("Sending \(data.count) bytes")
            respond(data)
            return .success(())
        case .failure(let failure):
            logEncodingFailure(failure)
            return .failure(failure)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

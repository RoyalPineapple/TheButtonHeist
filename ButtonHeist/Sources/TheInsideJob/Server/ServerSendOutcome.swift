import ButtonHeistSupport
import Foundation

/// Synchronous outcome for handing bytes to a client socket.
enum ServerSendOutcome: Equatable, Sendable {
    case enqueued
    case failed(ServerSendFailure)

    var didEnqueue: Bool {
        if case .enqueued = self { return true }
        return false
    }
}

enum ServerSendFailure: Error, LocalizedError, Equatable, Sendable {
    case clientNotFound(Int)
    case transportUnavailable
    case transportFailed(clientId: Int, diagnostic: NetworkTransportFailure)
    case payloadTooLarge(byteCount: Int, maxBytes: Int)
    case sendBufferFull(pendingBytes: Int, byteCount: Int, maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .clientNotFound(let clientId):
            return "Client \(clientId) is no longer connected"
        case .transportUnavailable:
            return "Server transport is not available"
        case .transportFailed(let clientId, let diagnostic):
            return "Transport send to client \(clientId) failed: \(diagnostic.description)"
        case .payloadTooLarge(let byteCount, let maxBytes):
            return "Payload is too large to send (\(byteCount) bytes, max \(maxBytes))"
        case .sendBufferFull(let pendingBytes, let byteCount, let maxBytes):
            return "Send buffer is full (\(pendingBytes) bytes pending, \(byteCount) bytes requested, max \(maxBytes))"
        }
    }
}

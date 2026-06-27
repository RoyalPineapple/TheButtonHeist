import Foundation
import Network

/// Synchronous outcome for handing bytes to a client socket.
enum ServerSendOutcome: Equatable, Sendable {
    case enqueued
    case failed(ServerSendFailure)

    var didEnqueue: Bool {
        if case .enqueued = self { return true }
        return false
    }
}

struct ServerTransportFailure: Error, LocalizedError, Equatable, Sendable, CustomStringConvertible {
    enum Reason: Equatable, Sendable {
        case posix(code: Int)
        case dns(code: Int)
        case tls(status: Int)
        case wifiAware(code: Int)
        case unknown(String)
    }

    let reason: Reason
    let underlyingDescription: String

    init(_ error: NWError) {
        let reason = Self.reason(for: error)
        self.reason = reason
        self.underlyingDescription = "\(reason.description): \(error.localizedDescription)"
    }

    var description: String {
        underlyingDescription
    }

    var errorDescription: String? {
        underlyingDescription
    }

    var isEmpty: Bool {
        underlyingDescription.isEmpty
    }

    private static func reason(for error: NWError) -> Reason {
        switch error {
        case .posix(let code):
            return .posix(code: Int(code.rawValue))
        case .dns(let code):
            return .dns(code: Int(code))
        case .tls(let status):
            return .tls(status: Int(status))
        case .wifiAware(let code):
            return .wifiAware(code: Int(code))
        @unknown default:
            return .unknown(String(describing: error))
        }
    }
}

extension ServerTransportFailure.Reason: CustomStringConvertible {
    var description: String {
        switch self {
        case .posix(let code):
            return "posix(\(code))"
        case .dns(let code):
            return "dns(\(code))"
        case .tls(let status):
            return "tls(\(status))"
        case .wifiAware(let code):
            return "wifiAware(\(code))"
        case .unknown(let description):
            return "unknown(\(description))"
        }
    }
}

enum ServerSendFailure: Error, LocalizedError, Equatable, Sendable {
    case clientNotFound(Int)
    case transportUnavailable
    case transportFailed(clientId: Int, diagnostic: ServerTransportFailure)
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

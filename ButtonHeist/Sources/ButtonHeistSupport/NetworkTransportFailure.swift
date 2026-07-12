import Foundation
import Network

public struct NetworkTransportFailure: Error, LocalizedError, Equatable, Sendable, CustomStringConvertible {
    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case posix(code: Int)
        case dns(code: Int)
        case tls(status: Int)
        case wifiAware(code: Int)
        case unknown(String)

        public var description: String {
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

    public let reason: Reason
    public let underlyingDescription: String

    public init(_ error: NWError) {
        let reason = Self.reason(for: error)
        self.reason = reason
        self.underlyingDescription = "\(reason.description): \(error.localizedDescription)"
    }

    public var description: String {
        underlyingDescription
    }

    public var errorDescription: String? {
        underlyingDescription
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

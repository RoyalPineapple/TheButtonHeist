import Foundation
import TheScore

enum SocketReceiveBufferPolicy {
    enum Violation: Error, Equatable, LocalizedError, Sendable {
        case frameTooLarge(byteCount: Int, maxBytes: Int)

        var errorDescription: String? {
            switch self {
            case let .frameTooLarge(byteCount, maxBytes):
                return "received frame buffer exceeded \(maxBytes) bytes (\(byteCount) bytes)"
            }
        }
    }

    static let maxBufferedBytes = WireFrameLimits.clientToServerMaxBufferedBytes

    static func validate(_ framer: NewlineDelimitedFramer, appending content: Data?) throws {
        let contentByteCount = content?.count ?? 0
        let (byteCount, overflowed) = framer.pendingByteCount.addingReportingOverflow(contentByteCount)

        guard !overflowed, byteCount <= maxBufferedBytes else {
            throw Violation.frameTooLarge(
                byteCount: overflowed ? Int.max : byteCount,
                maxBytes: maxBufferedBytes
            )
        }
    }
}

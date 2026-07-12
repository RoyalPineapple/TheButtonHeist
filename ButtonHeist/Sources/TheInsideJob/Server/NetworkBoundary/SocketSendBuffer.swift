import TheScore

/// Per-client send-buffer accounting: reservations are admitted only while
/// total queued bytes stay within the configured high-water mark.
struct SocketSendBuffer: Equatable, Sendable {
    enum Rejection: Error, Equatable, Sendable {
        case payloadTooLarge(byteCount: Int, maxBytes: Int)
        case bufferFull(pendingBytes: Int, byteCount: Int, maxBytes: Int)

        var sendFailure: ServerSendFailure {
            switch self {
            case .payloadTooLarge(let byteCount, let maxBytes):
                return .payloadTooLarge(byteCount: byteCount, maxBytes: maxBytes)
            case .bufferFull(let pendingBytes, let byteCount, let maxBytes):
                return .sendBufferFull(
                    pendingBytes: pendingBytes,
                    byteCount: byteCount,
                    maxBytes: maxBytes
                )
            }
        }
    }

    static let defaultMaxPendingBytes = WireFrameLimits.serverToClientMaxPendingSendBytes

    let maxPendingBytes: Int
    private(set) var pendingBytes: Int

    init(maxPendingBytes: Int = Self.defaultMaxPendingBytes, pendingBytes: Int = 0) {
        self.maxPendingBytes = maxPendingBytes
        self.pendingBytes = pendingBytes
    }

    mutating func reserve(byteCount: Int) -> Rejection? {
        if byteCount > maxPendingBytes {
            return .payloadTooLarge(byteCount: byteCount, maxBytes: maxPendingBytes)
        }
        if pendingBytes + byteCount > maxPendingBytes {
            return .bufferFull(
                pendingBytes: pendingBytes,
                byteCount: byteCount,
                maxBytes: maxPendingBytes
            )
        }
        pendingBytes += byteCount
        return nil
    }

    mutating func complete(byteCount: Int) {
        pendingBytes = max(0, pendingBytes - byteCount)
    }
}

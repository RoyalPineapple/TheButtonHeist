import TheScore

/// Per-client send-buffer accounting: reservations are admitted only while
/// total queued bytes stay within the configured high-water mark.
struct SocketSendBuffer: Sendable {
    struct Reservation: Hashable, Sendable {
        fileprivate let id: UInt64
        let byteCount: Int
    }

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
    private var pendingReservations: Set<Reservation> = []
    private var nextReservationID: UInt64 = 0

    var pendingBytes: Int {
        pendingReservations.reduce(0) { $0 + $1.byteCount }
    }

    init(maxPendingBytes: Int = Self.defaultMaxPendingBytes) {
        self.maxPendingBytes = maxPendingBytes
    }

    mutating func reserve(byteCount: Int) -> Result<Reservation, Rejection> {
        if byteCount > maxPendingBytes {
            return .failure(.payloadTooLarge(byteCount: byteCount, maxBytes: maxPendingBytes))
        }
        if pendingBytes + byteCount > maxPendingBytes {
            return .failure(.bufferFull(
                pendingBytes: pendingBytes,
                byteCount: byteCount,
                maxBytes: maxPendingBytes
            ))
        }
        nextReservationID += 1
        let reservation = Reservation(id: nextReservationID, byteCount: byteCount)
        pendingReservations.insert(reservation)
        return .success(reservation)
    }

    mutating func complete(_ reservation: Reservation) -> Bool {
        pendingReservations.remove(reservation) != nil
    }
}

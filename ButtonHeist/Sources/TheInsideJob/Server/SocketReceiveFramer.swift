import Foundation
import TheScore

/// Newline-delimited receive framing invariant: after a successful append,
/// `pendingData` contains only bytes after the final newline and never exceeds `maxBufferedBytes`,
/// while complete non-empty frames are emitted in arrival order. Failed appends leave `pendingData`
/// unchanged so callers can own the disconnect/recovery policy.
struct SocketReceiveFramer: Equatable, Sendable {
    enum FramingError: Error, Equatable, LocalizedError, Sendable {
        case frameTooLarge(byteCount: Int, maxBytes: Int)

        var errorDescription: String? {
            switch self {
            case let .frameTooLarge(byteCount, maxBytes):
                return "received frame buffer exceeded \(maxBytes) bytes (\(byteCount) bytes)"
            }
        }
    }

    static let defaultMaxBufferedBytes = WireFrameLimits.clientToServerMaxBufferedBytes

    let maxBufferedBytes: Int
    private(set) var pendingData: Data

    init(maxBufferedBytes: Int = Self.defaultMaxBufferedBytes, pendingData: Data = Data()) {
        self.maxBufferedBytes = maxBufferedBytes
        self.pendingData = pendingData
    }

    mutating func append(_ content: Data?) throws -> [Data] {
        var candidate = pendingData
        if let content {
            candidate.append(content)
        }

        guard candidate.count <= maxBufferedBytes else {
            throw FramingError.frameTooLarge(byteCount: candidate.count, maxBytes: maxBufferedBytes)
        }

        var frames: [Data] = []
        while let newlineIndex = candidate.firstIndex(of: WireFrameLimits.newlineDelimiterByte) {
            let frame = Data(candidate.prefix(upTo: newlineIndex))
            if !frame.isEmpty {
                frames.append(frame)
            }
            candidate = Data(candidate.suffix(from: candidate.index(after: newlineIndex)))
        }

        pendingData = candidate
        return frames
    }
}

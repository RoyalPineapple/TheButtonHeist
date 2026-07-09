import Foundation
import Network

enum DeviceConnectionEventStream {
    nonisolated static let bufferLimit = 512

    struct EventStream {
        let events: AsyncStream<DeviceConnectionEvent>
        let continuation: AsyncStream<DeviceConnectionEvent>.Continuation
    }

    nonisolated static func makeStream() -> EventStream {
        let stream = AsyncStream<DeviceConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(bufferLimit)
        )
        return EventStream(events: stream.stream, continuation: stream.continuation)
    }

    nonisolated static func yield(
        _ event: DeviceConnectionEvent,
        to continuation: AsyncStream<DeviceConnectionEvent>.Continuation,
        onOverflow: @escaping @Sendable () -> Void
    ) {
        switch continuation.yield(event) {
        case .enqueued, .terminated:
            return
        case .dropped:
            continuation.finish()
            onOverflow()
        @unknown default:
            continuation.finish()
            onOverflow()
        }
    }
}

extension DeviceConnection {
    /// Internal for testing and overflow handling from NW callbacks.
    func handleEventStreamOverflow(connection: NWConnection) {
        handleEventStreamOverflow(connection: connection, sessionID: nil)
    }

    func handleEventStreamOverflow(connection: NWConnection, sessionID: UUID?) {
        guard isCurrentSession(sessionID, connection: connection) else { return }
        deviceConnectionLogger.error("Connection event backlog exceeded \(DeviceConnectionEventStream.bufferLimit), disconnecting")
        disconnect()
        onEvent?(.disconnected(.eventBacklogOverflow(maxEvents: DeviceConnectionEventStream.bufferLimit)))
    }
}

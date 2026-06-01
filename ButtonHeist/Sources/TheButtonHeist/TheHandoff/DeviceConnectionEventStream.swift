import Foundation
import Network

enum DeviceConnectionEventStream {
    nonisolated static let bufferLimit = 512

    nonisolated static func makeStream() -> (
        AsyncStream<DeviceConnectionEvent>,
        AsyncStream<DeviceConnectionEvent>.Continuation
    ) {
        AsyncStream<DeviceConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(bufferLimit)
        )
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
        guard let current = currentConnection, current === connection else { return }
        deviceConnectionLogger.error("Connection event backlog exceeded \(DeviceConnectionEventStream.bufferLimit), disconnecting")
        disconnect()
        onEvent?(.disconnected(.eventBacklogOverflow(maxEvents: DeviceConnectionEventStream.bufferLimit)))
    }
}

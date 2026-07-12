import Foundation
import os.log

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.transport))

/// Ordered transport event stream with fail-closed backlog handling.
final class TransportEventStream: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    nonisolated let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let callbackTasks = TaskTracker()
    private let bufferLimit: Int

    init(bufferLimit: Int) {
        self.bufferLimit = bufferLimit
        let eventStream = Self.makeEventStream(bufferLimit: bufferLimit)
        self.events = eventStream.events
        self.continuation = eventStream.continuation
    }

    func makeCallbacks(
        overflowHandler: @escaping @MainActor @Sendable (_ maxEvents: Int) async -> Void
    ) -> SocketServerCallbacks {
        let continuation = continuation
        let callbackTasks = callbackTasks
        let bufferLimit = bufferLimit
        let onOverflow: @Sendable () -> Void = {
            logger.error("Transport event backlog exceeded \(bufferLimit), stopping server")
            let task = Task { @MainActor in
                await overflowHandler(bufferLimit)
            }
            callbackTasks.record(task)
        }
        return SocketServerCallbacks(
            onClientConnected: { clientId, remoteAddress in
                Self.yieldEvent(
                    .clientConnected(clientId: clientId, remoteAddress: remoteAddress),
                    to: continuation,
                    onOverflow: onOverflow
                )
            },
            onClientDisconnected: { clientId in
                Self.yieldEvent(.clientDisconnected(clientId: clientId), to: continuation, onOverflow: onOverflow)
            },
            onDataReceived: { clientId, data, respond in
                Self.yieldEvent(
                    .dataReceived(
                        clientId: clientId,
                        data: data,
                        respond: { response in respond(response) }
                    ),
                    to: continuation,
                    onOverflow: onOverflow
                )
            }
        )
    }

    func finish() {
        callbackTasks.cancelAll()
        continuation.finish()
    }

    struct EventStream {
        let events: AsyncStream<TransportEvent>
        let continuation: AsyncStream<TransportEvent>.Continuation
    }

    nonisolated static func makeEventStream(bufferLimit: Int) -> EventStream {
        let stream = AsyncStream<TransportEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(bufferLimit)
        )
        return EventStream(events: stream.stream, continuation: stream.continuation)
    }

    nonisolated static func yieldEvent(
        _ event: TransportEvent,
        to continuation: AsyncStream<TransportEvent>.Continuation,
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

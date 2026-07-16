import Foundation
import os

import TheScore

private let logger = ButtonHeistLog.logger(.handoff(.transport))

/// Ordered transport delivery with one reserved terminal-overflow slot.
final class TransportEventStream: Sendable {
    struct AsyncIterator: AsyncIteratorProtocol {
        private var base: AsyncStream<TransportEvent>.AsyncIterator
        private let buffer: TransportEventBuffer

        fileprivate init(
            base: AsyncStream<TransportEvent>.AsyncIterator,
            buffer: TransportEventBuffer
        ) {
            self.base = base
            self.buffer = buffer
        }

        mutating func next() async -> TransportEvent? {
            guard let event = await base.next() else { return nil }
            if event.countsAgainstBacklogLimit {
                buffer.consume()
            }
            return event
        }
    }

    struct Events: AsyncSequence, Sendable {
        private let base: AsyncStream<TransportEvent>
        private let buffer: TransportEventBuffer

        fileprivate init(base: AsyncStream<TransportEvent>, buffer: TransportEventBuffer) {
            self.base = base
            self.buffer = buffer
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(base: base.makeAsyncIterator(), buffer: buffer)
        }
    }

    nonisolated let events: Events

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let buffer: TransportEventBuffer
    private let bufferLimit: Int

    init(bufferLimit: Int) {
        self.bufferLimit = bufferLimit
        let buffer = TransportEventBuffer(limit: bufferLimit)
        let stream = AsyncStream<TransportEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(bufferLimit + 1)
        )
        self.buffer = buffer
        self.events = Events(base: stream.stream, buffer: buffer)
        self.continuation = stream.continuation
    }

    func makeCallbacks() -> SocketServerCallbacks {
        SocketServerCallbacks(
            onClientConnected: { [weak self] clientId, remoteAddress in
                self?.yield(.clientConnected(clientId: clientId, remoteAddress: remoteAddress))
            },
            onClientDisconnected: { [weak self] clientId in
                self?.yield(.clientDisconnected(clientId: clientId))
            },
            onDataReceived: { [weak self] clientId, data, respond in
                self?.yield(.dataReceived(clientId: clientId, data: data, respond: respond))
            }
        )
    }

    private func yield(_ event: TransportEvent) {
        guard buffer.reserve() else {
            guard buffer.beginOverflow() else { return }
            logger.error("Transport event backlog exceeded \(self.bufferLimit), stopping server")
            _ = continuation.yield(.backlogOverflow(maxEvents: self.bufferLimit))
            continuation.finish()
            return
        }

        switch continuation.yield(event) {
        case .enqueued, .dropped:
            return
        case .terminated:
            buffer.consume()
        @unknown default:
            buffer.consume()
        }
    }
}

private final class TransportEventBuffer: Sendable {
    private struct State {
        var bufferedEvents = 0
        var overflowed = false
    }

    private let limit: Int
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    init(limit: Int) {
        self.limit = limit
    }

    func reserve() -> Bool {
        state.withLock { state in
            guard !state.overflowed, state.bufferedEvents < limit else { return false }
            state.bufferedEvents += 1
            return true
        }
    }

    func consume() {
        state.withLock { state in
            state.bufferedEvents -= 1
        }
    }

    func beginOverflow() -> Bool {
        state.withLock { state in
            guard !state.overflowed else { return false }
            state.overflowed = true
            return true
        }
    }
}

private extension TransportEvent {
    var countsAgainstBacklogLimit: Bool {
        if case .backlogOverflow = self { return false }
        return true
    }
}

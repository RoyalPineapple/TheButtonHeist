#if canImport(UIKit)
#if DEBUG
import Foundation

struct ClientTransportRequest: Sendable {
    let clientId: Int
    let data: Data
    let respond: SocketResponseHandler
}

/// One ordered frame stream for one connected client.
///
/// Admission and execution share this per-client order. A slow request blocks
/// only later frames from the same client, while transport lifecycle and other
/// clients continue independently.
@MainActor
final class ClientRequestPipeline {
    static let maximumQueuedRequests = 512

    enum EnqueueResult: Equatable {
        case enqueued
        case stopped
        case overflowed
    }

    private enum Phase {
        case accepting(
            continuation: AsyncStream<ClientTransportRequest>.Continuation,
            consumer: Task<Void, Never>
        )
        case stopped
    }

    private var phase: Phase = .stopped

    init(
        execute: @escaping @MainActor @Sendable (ClientTransportRequest) async -> Void
    ) {
        let stream = AsyncStream<ClientTransportRequest>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.maximumQueuedRequests)
        )
        let consumer = Task { @MainActor in
            for await request in stream.stream {
                guard !Task.isCancelled else { return }
                await execute(request)
            }
        }
        phase = .accepting(continuation: stream.continuation, consumer: consumer)
    }

    func enqueue(_ request: ClientTransportRequest) -> EnqueueResult {
        guard case .accepting(let continuation, _) = phase else {
            return .stopped
        }

        switch continuation.yield(request) {
        case .enqueued:
            return .enqueued
        case .terminated:
            return .stopped
        case .dropped:
            _ = stop()
            return .overflowed
        @unknown default:
            _ = stop()
            return .overflowed
        }
    }

    /// Stops admission immediately and returns the cancelled consumer so tests
    /// and lifecycle owners may await terminal completion when needed.
    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard case .accepting(let continuation, let consumer) = phase else {
            return nil
        }
        phase = .stopped
        continuation.finish()
        consumer.cancel()
        return consumer
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

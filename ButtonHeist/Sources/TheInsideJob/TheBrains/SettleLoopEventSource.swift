#if canImport(UIKit)
#if DEBUG
import Foundation

enum SettleLoopEvent: Sendable {
    case heartbeat(TheTripwire.HeartbeatWaitOutcome)
    case uikitIdle
}

/// Delivers one requested display heartbeat at a time alongside UIKit-idle edges.
@MainActor
final class SettleLoopEventSource {
    // MARK: - Properties

    let events: AsyncStream<SettleLoopEvent>
    private(set) var continuation: AsyncStream<SettleLoopEvent>.Continuation
    private var heartbeatTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        (events, continuation) = AsyncStream<SettleLoopEvent>.makeStream()
    }

    // MARK: - Heartbeat Observation

    func requestHeartbeat(
        _ operation: @escaping @MainActor () async -> TheTripwire.HeartbeatWaitOutcome
    ) {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { @MainActor in
            let heartbeat = await operation()
            guard !Task.isCancelled else { return }
            continuation.yield(.heartbeat(heartbeat))
        }
    }

    func consumeHeartbeat() {
        heartbeatTask = nil
    }

    func cancelHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    func cancelHeartbeatAndWait() async {
        let task = heartbeatTask
        heartbeatTask = nil
        task?.cancel()
        await task?.value
    }

    func cancel() {
        cancelHeartbeat()
        continuation.finish()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

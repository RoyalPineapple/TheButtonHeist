#if canImport(UIKit)
#if DEBUG
import Foundation

enum SettleLoopEvent: Sendable {
    case tick(TheTripwire.TickWaitOutcome)
    case uikitIdle
}

/// Delivers one requested display heartbeat at a time alongside UIKit-idle edges.
@MainActor
final class SettleLoopEventSource {
    // MARK: - Properties

    let events: AsyncStream<SettleLoopEvent>
    private(set) var continuation: AsyncStream<SettleLoopEvent>.Continuation
    private var tickTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        (events, continuation) = AsyncStream<SettleLoopEvent>.makeStream()
    }

    // MARK: - Heartbeat Observation

    func requestTick(
        _ operation: @escaping @MainActor () async -> TheTripwire.TickWaitOutcome
    ) {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor in
            let tick = await operation()
            guard !Task.isCancelled else { return }
            continuation.yield(.tick(tick))
        }
    }

    func consumeTick() {
        tickTask = nil
    }

    func cancelTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    func cancelTickAndWait() async {
        let task = tickTask
        tickTask = nil
        task?.cancel()
        await task?.value
    }

    func cancel() {
        cancelTick()
        continuation.finish()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

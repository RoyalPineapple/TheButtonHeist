#if canImport(UIKit)
#if DEBUG
import Foundation

/// Delivers one requested display tick at a time.
///
/// The tick is the settle loop's only clock, so this source has exactly one
/// event shape. Nothing else may yield into it.
@MainActor
final class SettleLoopEventSource {
    // MARK: - Properties

    let events: AsyncStream<TheTripwire.TickWaitOutcome>
    private(set) var continuation: AsyncStream<TheTripwire.TickWaitOutcome>.Continuation
    private var tickTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        (events, continuation) = AsyncStream<TheTripwire.TickWaitOutcome>.makeStream()
    }

    // MARK: - Tick Observation

    func requestTick(
        _ operation: @escaping @MainActor () async -> TheTripwire.TickWaitOutcome
    ) {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor in
            let tick = await operation()
            guard !Task.isCancelled else { return }
            continuation.yield(tick)
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

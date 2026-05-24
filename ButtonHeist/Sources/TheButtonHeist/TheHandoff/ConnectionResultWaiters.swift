import Foundation

/// Invariant: resolving, cancelling, or timing out one waiter cannot affect a different connection attempt.
@ButtonHeistActor
final class ConnectionResultWaiters {
    private typealias Waiter = (attemptID: UUID, continuation: CheckedContinuation<Void, Error>)
    private var waiters: [UUID: Waiter] = [:]

    func register(id: UUID, attemptID: UUID, continuation: CheckedContinuation<Void, Error>) {
        assert(waiters[id] == nil, "ConnectionResultWaiters registered duplicate waiter id")
        waiters[id] = (attemptID: attemptID, continuation: continuation)
    }

    func cancel(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }

    func fail(id: UUID, attemptID: UUID, with error: Error) {
        guard let waiter = waiters[id], waiter.attemptID == attemptID else { return }
        waiters[id] = nil
        waiter.continuation.resume(throwing: error)
    }

    func resolve(attemptID: UUID, with result: Result<Void, Error>) {
        let waiterIDs = waiters.compactMap { $0.value.attemptID == attemptID ? $0.key : nil }
        for id in waiterIDs {
            guard let waiter = waiters.removeValue(forKey: id) else { continue }
            waiter.continuation.resume(with: result)
        }
    }
}

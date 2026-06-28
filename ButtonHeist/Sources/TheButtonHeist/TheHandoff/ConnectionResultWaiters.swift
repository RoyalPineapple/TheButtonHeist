import Foundation

enum HandoffConnectionAttemptResult: Equatable {
    case connected
    case failed(HandoffConnectionError)
}

/// Invariant: resolving, cancelling, or timing out one waiter cannot affect a different connection attempt.
@ButtonHeistActor
final class ConnectionResultWaiters {
    private struct Waiter {
        let attemptID: UUID
        let continuation: CheckedContinuation<Void, Error>

        func resolve(with result: HandoffConnectionAttemptResult) {
            switch result {
            case .connected:
                continuation.resume(returning: ())
            case .failed(let failure):
                continuation.resume(throwing: failure)
            }
        }

        func cancel() {
            continuation.resume(throwing: CancellationError())
        }
    }

    private var waiters: [UUID: Waiter] = [:]

    func register(id: UUID, attemptID: UUID, continuation: CheckedContinuation<Void, Error>) {
        assert(waiters[id] == nil, "ConnectionResultWaiters registered duplicate waiter id")
        waiters[id] = Waiter(attemptID: attemptID, continuation: continuation)
    }

    func cancel(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.cancel()
    }

    func fail(id: UUID, attemptID: UUID, with failure: HandoffConnectionError) {
        guard let waiter = waiters[id], waiter.attemptID == attemptID else { return }
        waiters[id] = nil
        waiter.resolve(with: .failed(failure))
    }

    func resolve(attemptID: UUID, with result: HandoffConnectionAttemptResult) {
        let waiterIDs = waiters.compactMap { $0.value.attemptID == attemptID ? $0.key : nil }
        for id in waiterIDs {
            guard let waiter = waiters.removeValue(forKey: id) else { continue }
            waiter.resolve(with: result)
        }
    }
}

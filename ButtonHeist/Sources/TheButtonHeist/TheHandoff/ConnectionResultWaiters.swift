import Foundation
import ButtonHeistSupport

enum HandoffConnectionAttemptResult: Equatable {
    case connected
    case failed(HandoffConnectionError)
}

/// Invariant: resolving, cancelling, or timing out one waiter cannot affect a different connection attempt.
@ButtonHeistActor
final class ConnectionResultWaiters {
    private struct Waiter {
        let attemptID: UUID
        let completion: TimedOneShot<Result<Void, Error>>

        func resolve(with result: HandoffConnectionAttemptResult) {
            switch result {
            case .connected:
                completion.resolve(returning: .success(()))
            case .failed(let failure):
                completion.resolve(returning: .failure(failure))
            }
        }

        func cancel() {
            completion.resolve(returning: .failure(CancellationError()))
        }
    }

    private var waiters: [UUID: Waiter] = [:]

    func register(id: UUID, attemptID: UUID, completion: TimedOneShot<Result<Void, Error>>) {
        assert(waiters[id] == nil, "ConnectionResultWaiters registered duplicate waiter id")
        waiters[id] = Waiter(attemptID: attemptID, completion: completion)
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

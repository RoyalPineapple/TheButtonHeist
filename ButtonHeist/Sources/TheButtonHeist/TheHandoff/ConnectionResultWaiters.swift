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

    private var waiters = WaiterStore<UUID, Waiter>()

    func register(id: UUID, attemptID: UUID, completion: TimedOneShot<Result<Void, Error>>) {
        waiters.insert(Waiter(attemptID: attemptID, completion: completion), for: id)
    }

    func cancel(id: UUID) {
        guard let waiter = waiters.remove(id) else { return }
        waiter.cancel()
    }

    func fail(id: UUID, attemptID: UUID, with failure: HandoffConnectionError) {
        let matchingWaiters = waiters.removeAll { key, waiter in
            key == id && waiter.attemptID == attemptID
        }
        guard let waiter = matchingWaiters.first?.waiter else { return }
        waiter.resolve(with: .failed(failure))
    }

    func resolve(attemptID: UUID, with result: HandoffConnectionAttemptResult) {
        let matchingWaiters = waiters.removeAll { _, waiter in waiter.attemptID == attemptID }
        for (_, waiter) in matchingWaiters {
            waiter.resolve(with: result)
        }
    }
}

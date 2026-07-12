import Foundation
import ButtonHeistSupport

/// Invariant: resolving, cancelling, or timing out one waiter cannot affect a different connection attempt.
@ButtonHeistActor
final class ConnectionResultWaiters {
    private struct Waiter {
        let attemptID: UUID
        let completion: TimedOneShot<Result<Void, Error>>

        func resolve(with result: Result<Void, Error>) {
            completion.resolve(returning: result)
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
        waiter.resolve(with: .failure(failure))
    }

    func resolve(_ transition: HandoffConnectionLifecycleTransition) {
        guard let completion = transition.waiterCompletion else { return }
        let matchingWaiters = waiters.removeAll { _, waiter in waiter.attemptID == completion.attemptID }
        for removal in matchingWaiters {
            removal.waiter.resolve(with: completion.result)
        }
    }
}

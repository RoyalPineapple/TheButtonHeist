import os

package struct OneShotContinuation<Value: Sendable>: Sendable {
    private enum State {
        case pending
        case registered(CheckedContinuation<Value, Never>)
        case resumed
    }

    private let lock = OSAllocatedUnfairLock(initialState: State.pending)

    package init() {}

    package func register(_ continuation: CheckedContinuation<Value, Never>) -> Bool {
        lock.withLock { state -> Bool in
            switch state {
            case .pending:
                state = .registered(continuation)
                return true
            case .registered:
                preconditionFailure("One-shot continuation registered twice")
            case .resumed:
                return false
            }
        }
    }

    package func resume(returning value: Value) {
        let continuationToResume = lock.withLock { state -> CheckedContinuation<Value, Never>? in
            switch state {
            case .pending:
                state = .resumed
                return nil
            case .registered(let continuation):
                state = .resumed
                return continuation
            case .resumed:
                return nil
            }
        }
        continuationToResume?.resume(returning: value)
    }
}

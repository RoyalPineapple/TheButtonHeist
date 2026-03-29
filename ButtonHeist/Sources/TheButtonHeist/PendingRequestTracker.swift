import Foundation
import os

/// A generic tracker that manages pending request-response pairs with timeout support.
///
/// Each pending request is identified by a `requestId` string. Callers await a response
/// via `wait(requestId:timeout:)`, and the corresponding response arrives later via
/// `resolve(requestId:result:)`. If no response arrives within the timeout, the
/// continuation resumes with `ActionError.timeout`.
///
/// This type replaces the three hand-rolled `pending*Requests` dictionaries and the
/// shared `waitForResponse<T>` method that previously lived in `TheFence`.
@ButtonHeistActor
final class PendingRequestTracker<T: Sendable> {
    private var pending: [String: @Sendable (Result<T, Error>) -> Void] = [:]

    var pendingCount: Int { pending.count }

    /// Register a pending request and wait for its response or timeout.
    ///
    /// The caller is suspended until either `resolve(requestId:result:)` is called
    /// with a matching `requestId`, or `timeout` seconds elapse. Double-resume is
    /// prevented by an `OSAllocatedUnfairLock<Bool>` guard.
    func wait(requestId: String, timeout: TimeInterval) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let didResume = OSAllocatedUnfairLock(initialState: false)

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                let shouldResume = didResume.withLock { flag -> Bool in
                    guard !flag else { return false }
                    flag = true
                    return true
                }
                if shouldResume {
                    self.pending.removeValue(forKey: requestId)
                    continuation.resume(throwing: TheFence.ActionError.timeout)
                }
            }

            pending[requestId] = { result in
                let shouldResume = didResume.withLock { flag -> Bool in
                    guard !flag else { return false }
                    flag = true
                    return true
                }
                if shouldResume {
                    timeoutTask.cancel()
                    continuation.resume(with: result)
                }
            }
        }
    }

    /// Deliver a result for the given `requestId`, resuming the waiting continuation.
    ///
    /// If no pending request matches (e.g., it already timed out), this is a no-op.
    func resolve(requestId: String, result: Result<T, Error>) {
        if let callback = pending.removeValue(forKey: requestId) {
            callback(result)
        }
    }

    /// Cancel all pending requests by resuming each with the given error.
    func cancelAll(error: Error) {
        let callbacks = pending
        pending.removeAll()
        for (_, callback) in callbacks {
            callback(.failure(error))
        }
    }
}

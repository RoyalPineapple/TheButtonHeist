import Foundation
import os

/// A generic tracker that manages pending request-response pairs with timeout support.
///
/// Each pending request is identified by a `requestId` string. Callers await a response
/// via `wait(requestId:timeout:)`, and the corresponding response arrives later via
/// `resolve(requestId:result:)`. If no response arrives within the timeout, the
/// continuation resumes with `FenceError.actionTimeout`.
enum PendingRequestTrackerError: Error, Equatable, LocalizedError {
    case duplicateRequestId(String)

    var errorDescription: String? {
        switch self {
        case .duplicateRequestId(let requestId):
            return "Request ID '\(requestId)' already has a pending waiter"
        }
    }
}

/// **Ownership.** Request correlation, owned by `TheFence.PendingRequestTrackers`
/// (one tracker per response type). Key: `requestId: String`. Lifetime: from
/// `wait()` registration until `resolve()`, timeout, or cancellation.
/// Invalidation: the entry is removed on each of those paths (owner-scoped
/// removal is idempotent across orderings). Holds only the awaiting
/// continuation — never caches a delivered result, so it cannot be derived from
/// any receipt. See `docs/DATA-OWNERSHIP.md`.
@ButtonHeistActor
final class PendingRequestTracker<T: Sendable> {
    private struct PendingRequest: Sendable {
        let owner: UUID
        let callback: @Sendable (Result<T, Error>) -> Void
    }

    private var pending: [String: PendingRequest] = [:]

    /// Register a pending request and wait for its response or timeout.
    ///
    /// The caller is suspended until either `resolve(requestId:result:)` is called
    /// with a matching `requestId`, or `timeout` seconds elapse. Double-resume is
    /// prevented by an `OSAllocatedUnfairLock<Bool>` guard. A duplicate
    /// `requestId` fails immediately without replacing the existing waiter.
    func wait(
        requestId: String,
        timeout: TimeInterval,
        afterRegister: (() -> Void)? = nil
    ) async throws -> T {
        let owner = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard pending[requestId] == nil else {
                    continuation.resume(throwing: PendingRequestTrackerError.duplicateRequestId(requestId))
                    return
                }

                let didResume = OSAllocatedUnfairLock(initialState: false)

                let timeoutTask = Task {
                    guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
                    if let callback = self.removePendingRequest(requestId: requestId, owner: owner) {
                        callback(.failure(FenceError.actionTimeout))
                    }
                }

                pending[requestId] = PendingRequest(owner: owner) { result in
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
                afterRegister?()
            }
        } onCancel: {
            // Safe in every ordering: if the entry was never registered (early
            // Task.isCancelled path, duplicate rejection) or was already removed
            // by a normal resolve/timeout, owner-scoped removal finds no match
            // and no-ops.
            Task { @ButtonHeistActor [weak self] in
                if let callback = self?.removePendingRequest(requestId: requestId, owner: owner) {
                    callback(.failure(CancellationError()))
                }
            }
        }
    }

    /// Deliver a result for the given `requestId`, resuming the waiting continuation.
    ///
    /// If no pending request matches (e.g., it already timed out), this is a no-op.
    func resolve(requestId: String, result: Result<T, Error>) {
        if let request = pending.removeValue(forKey: requestId) {
            request.callback(result)
        }
    }

    /// Cancel all pending requests by resuming each with the given error.
    func cancelAll(error: Error) {
        let requests = pending
        pending.removeAll()
        for (_, request) in requests {
            request.callback(.failure(error))
        }
    }

    private func removePendingRequest(
        requestId: String,
        owner: UUID
    ) -> (@Sendable (Result<T, Error>) -> Void)? {
        guard let request = pending[requestId], request.owner == owner else { return nil }
        pending.removeValue(forKey: requestId)
        return request.callback
    }
}

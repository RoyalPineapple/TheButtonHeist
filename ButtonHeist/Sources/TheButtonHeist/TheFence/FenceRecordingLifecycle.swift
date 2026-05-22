import Foundation
import os

import TheScore

struct RecordingSnapshot {
    let isRecording: Bool
    let isWaitingForCompletion: Bool
}

private struct RecordingPendingWait<Value: Sendable>: Sendable {
    let owner: UUID
    let callback: @Sendable (Result<Value, Error>) -> Void
}

@ButtonHeistActor
private final class RecordingWait<Value: Sendable> {
    private var pending: RecordingPendingWait<Value>?

    func wait(
        timeout: TimeInterval,
        afterRegister: (() -> Void)? = nil
    ) async throws -> Value {
        let owner = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                guard pending == nil else {
                    continuation.resume(
                        throwing: FenceError.invalidRequest("Recording wait already registered")
                    )
                    return
                }

                let didResume = OSAllocatedUnfairLock(initialState: false)
                let timeoutTask = Task {
                    guard await Task.cancellableSleep(for: .seconds(timeout)) else { return }
                    if let callback = self.removePending(owner: owner) {
                        callback(.failure(FenceError.actionTimeout))
                    }
                }

                pending = RecordingPendingWait(owner: owner) { result in
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
            Task { @ButtonHeistActor [weak self] in
                if let callback = self?.removePending(owner: owner) {
                    callback(.failure(CancellationError()))
                }
            }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        guard let pending else { return }
        self.pending = nil
        pending.callback(result)
    }

    func cancel(error: Error) {
        resolve(.failure(error))
    }

    private func removePending(owner: UUID) -> (@Sendable (Result<Value, Error>) -> Void)? {
        guard let pending, pending.owner == owner else { return nil }
        self.pending = nil
        return pending.callback
    }
}

private enum RecordingLifecycle {
    case idle
    case starting(wait: RecordingWait<Void>)
    case recording
    case completing(wait: RecordingWait<RecordingPayload>, serverRecording: Bool)
}

/// Owns the Fence recording state machine and pending recording waits.
@ButtonHeistActor
final class FenceRecordingLifecycle {
    private var lifecycle: RecordingLifecycle = .idle

    var snapshot: RecordingSnapshot {
        RecordingSnapshot(
            isRecording: isRecording,
            isWaitingForCompletion: isWaitingForCompletion
        )
    }

    var isRecording: Bool {
        switch lifecycle {
        case .recording:
            return true
        case .completing(_, let serverRecording):
            return serverRecording
        case .idle, .starting:
            return false
        }
    }

    private var isWaitingForCompletion: Bool {
        if case .completing = lifecycle {
            return true
        }
        return false
    }

    /// Cancels any active wait and returns to idle; safe to call after a prior cancel.
    func reset() {
        cancelAll(error: CancellationError())
        lifecycle = .idle
    }

    func cancelAll(error: Error) {
        switch lifecycle {
        case .starting(let wait):
            wait.cancel(error: error)
        case .completing(let wait, _):
            wait.cancel(error: error)
        case .idle, .recording:
            break
        }
    }

    func waitForStartAcknowledgement(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws {
        let wait = try beginStartWait()
        defer { finishStartWait(wait) }
        try await wait.wait(timeout: timeout, afterRegister: afterRegister)
    }

    func waitForCompletion(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws -> RecordingPayload {
        let wait = try beginCompletionWait()
        defer { finishCompletionWait(wait) }
        return try await wait.wait(timeout: timeout, afterRegister: afterRegister)
    }

    func resolveActiveStart(_ result: Result<Void, Error>) {
        guard case .starting(let wait) = lifecycle else { return }
        wait.resolve(result)
    }

    func resolveActiveCompletion(_ result: Result<RecordingPayload, Error>) {
        guard case .completing(let wait, _) = lifecycle else { return }
        wait.resolve(result)
    }

    func handleEvent(_ event: RecordingEvent) {
        switch event {
        case .started:
            if case .starting(let wait) = lifecycle {
                lifecycle = .recording
                wait.resolve(.success(()))
            } else if case .completing(let wait, _) = lifecycle {
                lifecycle = .completing(wait: wait, serverRecording: true)
            } else {
                lifecycle = .recording
            }
        case .stopped:
            if case .completing(let wait, _) = lifecycle {
                lifecycle = .completing(wait: wait, serverRecording: false)
            } else {
                lifecycle = .idle
            }
        case .completed(let payload):
            let wait: RecordingWait<RecordingPayload>?
            if case .completing(let activeWait, _) = lifecycle {
                wait = activeWait
            } else {
                wait = nil
            }
            lifecycle = .idle
            wait?.resolve(.success(payload))
        case .failed(let message):
            let error = FenceError.actionFailed("Recording failed: \(message)")
            switch lifecycle {
            case .starting(let wait):
                lifecycle = .idle
                wait.resolve(.failure(error))
            case .completing(let wait, _):
                lifecycle = .idle
                wait.resolve(.failure(error))
            case .idle, .recording:
                lifecycle = .idle
            }
        }
    }

    private func beginStartWait() throws -> RecordingWait<Void> {
        guard case .idle = lifecycle else {
            throw startRecordingConflictError
        }
        let wait = RecordingWait<Void>()
        lifecycle = .starting(wait: wait)
        return wait
    }

    private func finishStartWait(_ wait: RecordingWait<Void>) {
        guard case .starting(let activeWait) = lifecycle, activeWait === wait else { return }
        lifecycle = .idle
    }

    private func beginCompletionWait() throws -> RecordingWait<RecordingPayload> {
        let wait = RecordingWait<RecordingPayload>()
        switch lifecycle {
        case .idle:
            lifecycle = .completing(wait: wait, serverRecording: false)
        case .recording:
            lifecycle = .completing(wait: wait, serverRecording: true)
        case .starting, .completing:
            throw FenceError.invalidRequest("stop_recording already waiting for completion")
        }
        return wait
    }

    private func finishCompletionWait(_ wait: RecordingWait<RecordingPayload>) {
        guard case .completing(let activeWait, _) = lifecycle, activeWait === wait else { return }
        lifecycle = .idle
    }

    private var startRecordingConflictError: FenceError {
        switch lifecycle {
        case .idle:
            return .invalidRequest("Recording state changed while starting")
        case .starting:
            return .invalidRequest("start_recording already waiting for acknowledgement")
        case .recording:
            return .invalidRequest("Recording already in progress — use stop_recording first")
        case .completing:
            return .invalidRequest("stop_recording already waiting for completion")
        }
    }
}

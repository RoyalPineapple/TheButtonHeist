import Foundation
import os

import TheScore

private struct RecordingPendingWait<Value: Sendable>: Sendable {
    let owner: UUID
    let callback: @Sendable (Result<Value, Error>) -> Void
}

extension TheFence {

    // MARK: - Recording State

    @ButtonHeistActor
    final class RecordingWait<Value: Sendable> {
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

    enum RecordingLifecycle {
        case idle
        case starting(wait: RecordingWait<Void>)
        case recording
        case completing(wait: RecordingWait<RecordingPayload>, serverRecording: Bool)
    }

    struct RecordingCoordinator {
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

        mutating func reset() {
            lifecycle = .idle
        }

        @ButtonHeistActor
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

        mutating func beginStartWait() throws -> RecordingWait<Void> {
            guard case .idle = lifecycle else {
                throw startRecordingConflictError
            }
            let wait = RecordingWait<Void>()
            lifecycle = .starting(wait: wait)
            return wait
        }

        mutating func finishStartWait(_ wait: RecordingWait<Void>) {
            guard case .starting(let activeWait) = lifecycle, activeWait === wait else { return }
            lifecycle = .idle
        }

        mutating func beginCompletionWait() throws -> RecordingWait<RecordingPayload> {
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

        mutating func finishCompletionWait(_ wait: RecordingWait<RecordingPayload>) {
            guard case .completing(let activeWait, _) = lifecycle, activeWait === wait else { return }
            lifecycle = .idle
        }

        @ButtonHeistActor
        func resolveActiveCompletion(_ result: Result<RecordingPayload, Error>) {
            guard case .completing(let wait, _) = lifecycle else { return }
            wait.resolve(result)
        }

        @ButtonHeistActor
        mutating func handleEvent(_ event: RecordingEvent) {
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

    // MARK: - Command Execution State

    /// Last completed action, if any. Session display state derives from the
    /// active case instead of sibling cached projections.
    enum LastAction {
        case none
        case completed(result: ActionResult, latencyMs: Int)

        var sessionPayload: SessionLastActionPayload? {
            guard case .completed(let result, let latencyMs) = self else { return nil }
            return SessionLastActionPayload(
                method: result.method,
                success: result.success,
                message: result.message,
                latencyMs: latencyMs
            )
        }

        var latencyMsForReplacement: Int {
            guard case .completed(_, let latencyMs) = self else { return 0 }
            return latencyMs
        }
    }

    /// Owns command-execution state derived from dispatched action responses.
    struct CommandExecutionState {
        private(set) var lastAction: LastAction = .none

        mutating func noteDispatchedResponse(_ response: FenceResponse, latencyMs: Int) {
            guard let result = response.actionResult else { return }
            lastAction = .completed(result: result, latencyMs: latencyMs)
        }

        mutating func completeAction(_ result: ActionResult) {
            lastAction = .completed(result: result, latencyMs: lastAction.latencyMsForReplacement)
        }

        mutating func reset() {
            lastAction = .none
        }
    }
}

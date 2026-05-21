import Foundation

import TheScore

extension TheFence {

    // Recording responses do not carry request IDs. The recording lifecycle
    // carries the active start/completion wait so disconnect handling can fail
    // it immediately instead of letting the caller time out.
    public func waitForRecording(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        try await waitForRecording(timeout: timeout, afterRegister: nil)
    }

    func stopRecordingAndWait(timeout: TimeInterval = 120.0) async throws -> RecordingPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        return try await waitForRecording(timeout: timeout) {
            let outcome = self.handoff.send(.stopRecording, requestId: nil)
            if case .failed(let failure) = outcome {
                self.recording.resolveActiveCompletion(.failure(FenceError(failure)))
            }
        }
    }

    func startRecordingAndWait(config: RecordingConfig, timeout: TimeInterval = Timeouts.actionSeconds) async throws {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }
        let wait = try recording.beginStartWait()
        defer { recording.finishStartWait(wait) }

        var didSendStart = false
        do {
            try await wait.wait(timeout: timeout) {
                let outcome = self.handoff.send(.startRecording(config), requestId: nil)
                switch outcome {
                case .enqueued:
                    didSendStart = true
                case .failed(let failure):
                    wait.resolve(.failure(FenceError(failure)))
                }
            }
        } catch {
            if didSendStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    /// Run a recording from start to completion as a single async unit.
    ///
    /// Sends `start_recording`, waits for the server acknowledgement, then
    /// awaits the resulting `RecordingPayload`. On any error path after the
    /// start request is sent, sends `stop_recording` so the iOS-side recording
    /// is not stranded. Stop cleanup is secondary: if it fails, the original
    /// error still propagates.
    public func recordToCompletion(
        config: RecordingConfig,
        timeout: TimeInterval
    ) async throws -> RecordingPayload {
        guard handoff.isConnected else { throw FenceError.notConnected }
        guard !isRecording else {
            throw FenceError.invalidRequest("Recording already in progress — use stop_recording first")
        }

        // Cancellation that arrived before we could send the start request: do
        // nothing to clean up server-side, since nothing was started.
        try Task.checkCancellation()

        var didStart = false
        do {
            try await startRecordingAndWait(config: config, timeout: timeout)
            didStart = true
            return try await waitForRecording(timeout: timeout)
        } catch let error as CancellationError {
            if didStart {
                cleanUpServerRecording()
            }
            throw error
        } catch {
            if didStart {
                cleanUpServerRecording()
            }
            throw error
        }
    }

    /// Best-effort drain of an in-flight server-side recording. Used as the
    /// cleanup branch of `recordToCompletion` — failures are intentionally
    /// swallowed so the caller's original error still surfaces.
    private func cleanUpServerRecording() {
        guard handoff.isConnected else { return }
        handoff.send(.stopRecording, requestId: nil)
    }

    /// Internal overload exposing `afterRegister` for test injection. The hook
    /// fires synchronously after the recording callback is registered, letting
    /// tests deliver a payload deterministically without sleeping.
    func waitForRecording(
        timeout: TimeInterval,
        afterRegister: (() -> Void)?
    ) async throws -> RecordingPayload {
        let wait = try recording.beginCompletionWait()
        defer { recording.finishCompletionWait(wait) }
        return try await wait.wait(timeout: timeout, afterRegister: afterRegister)
    }
}

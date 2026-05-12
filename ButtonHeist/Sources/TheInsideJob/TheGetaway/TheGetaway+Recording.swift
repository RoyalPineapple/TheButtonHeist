#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheGetaway {

    // MARK: - Recording Lifecycle

    enum RecordingPhase {
        case idle
        /// Transient sentinel between accepting a `start_recording` request
        /// and the `TheStakeout` instance reaching `.recording`. Prevents a
        /// second `start_recording` from interleaving on the actor during
        /// the awaits inside `handleStartRecording` and orphaning a stakeout.
        case starting
        case recording(stakeout: TheStakeout)
    }

    /// Three-state lifecycle for the latest recording's outcome:
    /// `.none` (no completion to report), `.succeeded` (payload waiting for a
    /// `stop_recording` pickup), or `.failed` (error to surface). Replaces the
    /// triply-nullable `Result<RecordingPayload, Error>?` so the "no recording
    /// yet" state is structurally distinct from success/failure.
    enum RecordingOutcome {
        case none
        case succeeded(RecordingPayload)
        case failed(Error)

        init(result: Result<RecordingPayload, Error>) {
            switch result {
            case .success(let payload): self = .succeeded(payload)
            case .failure(let error): self = .failed(error)
            }
        }
    }

    func handleStartRecording(_ config: RecordingConfig, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        switch recordingPhase {
        case .recording:
            sendMessage(.error(ServerError(kind: .recording, message: "Recording already in progress")), requestId: requestId, respond: respond)
            return
        case .starting:
            sendMessage(.error(ServerError(kind: .recording, message: "Recording start already in progress")), requestId: requestId, respond: respond)
            return
        case .idle:
            break
        }

        // Claim the phase synchronously before the first await so a second
        // start_recording landing on the actor sees `.starting` and is rejected.
        recordingPhase = .starting
        completedRecording = .none

        // Wrap the entire startup pipeline in do-catch so the .starting claim is
        // always rolled back on any thrown error — including any future throwing
        // await inserted between the claim and `startRecording`.
        do {
            // captureFrame closure — MainActor-bound. Held by the actor as a let,
            // so it must be set at init.
            let brains = self.brains
            let recorder = TheStakeout(captureFrame: { @MainActor [brains] in
                brains.captureScreenForRecording()
            })
            // The completion handler signature is sync (@MainActor @Sendable).
            // `deliverRecordingResult` is async because it awaits the two
            // outbound broadcasts in FIFO order. Spawn a tracked Task to
            // bridge: there is only one recording-complete event per
            // session, so unlike the broadcast pipeline there is no FIFO
            // contention to lose between handler invocations. The handle is
            // stored on TheGetaway so `tearDown` cancels it on shutdown.
            await recorder.setOnRecordingComplete { [weak self] result in
                guard let self else { return }
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.deliverRecordingResult(result)
                }
                self.trackRecordingTask(task)
            }

            // Capture screen metrics on MainActor (we are the MainActor here) and pass
            // the value into the actor — TheStakeout is actor-isolated and can't read
            // MainActor-bound APIs directly.
            let screen = ScreenMetrics.current
            let screenInfo = TheStakeout.ScreenInfo(bounds: screen.bounds, scale: screen.scale)

            try await recorder.startRecording(config: config, screen: screenInfo)
            recordingPhase = .recording(stakeout: recorder)
            brains.stakeout = recorder
            sendMessage(.recordingStarted, requestId: requestId, respond: respond)
        } catch {
            // Roll back the claim so the next start_recording can proceed.
            recordingPhase = .idle
            sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
        }
    }

    /// Internal-for-tests entry point used by `onRecordingComplete`. Either
    /// returns the payload to a pending `stop_recording` waiter, or — when
    /// the stop was triggered by the server itself (max duration,
    /// file-size cap, inactivity) — broadcasts `.recording(payload)` so
    /// the originating `start_recording` caller, who is parked on
    /// `waitForRecording`, can pick it up. Without that broadcast a
    /// `start_recording --max-duration N` hangs until its 35s wait times
    /// out and the payload sits server-side until a later `stop_recording`
    /// drains `completedRecording`.
    func deliverRecordingResult(_ result: Result<RecordingPayload, Error>) async {
        recordingPhase = .idle
        brains.stakeout = nil
        completedRecording = RecordingOutcome(result: result)

        if let pending = pendingRecordingResponse {
            pendingRecordingResponse = nil
            switch result {
            case .success(let payload):
                sendMessage(.recording(payload), requestId: pending.requestId, respond: pending.respond)
            case .failure(let error):
                let serverError = ServerError(kind: .recording, message: error.localizedDescription)
                sendMessage(.error(serverError), requestId: pending.requestId, respond: pending.respond)
            }
            return
        }

        switch result {
        case .success(let payload):
            await broadcastToAll(.recording(payload))
            await broadcastToAll(.recordingStopped)
        case .failure(let error):
            await broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
        }
    }

    func handleStopRecording(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        switch completedRecording {
        case .succeeded(let payload):
            completedRecording = .none
            sendMessage(.recording(payload), requestId: requestId, respond: respond)
            return
        case .failed(let error):
            completedRecording = .none
            sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
            return
        case .none:
            break
        }

        guard let stakeout else {
            sendMessage(.error(ServerError(kind: .recording, message: "No recording in progress")), requestId: requestId, respond: respond)
            return
        }

        guard pendingRecordingResponse == nil else {
            sendMessage(.error(ServerError(kind: .recording, message: "Recording stop already in progress")), requestId: requestId, respond: respond)
            return
        }

        pendingRecordingResponse = (requestId: requestId, respond: respond)
        if await stakeout.isRecording {
            await stakeout.stopRecording(reason: .manual)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

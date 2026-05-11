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
        completedRecording = nil

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
            await recorder.setOnRecordingComplete { [weak self] result in
                self?.deliverRecordingResult(result)
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
    func deliverRecordingResult(_ result: Result<RecordingPayload, Error>) {
        recordingPhase = .idle
        brains.stakeout = nil
        completedRecording = result

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
            broadcastToAll(.recording(payload))
            broadcastToAll(.recordingStopped)
        case .failure(let error):
            broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
        }
    }

    func handleStopRecording(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        if let completedRecording {
            self.completedRecording = nil
            switch completedRecording {
            case .success(let payload):
                sendMessage(.recording(payload), requestId: requestId, respond: respond)
            case .failure(let error):
                sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
            }
            return
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

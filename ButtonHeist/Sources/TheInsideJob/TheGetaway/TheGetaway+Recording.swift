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

    func handleStartRecording(_ config: RecordingConfig, clientId: Int? = nil, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
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
        // Record the originator so an auto-finish payload can be routed back
        // to this client (instead of broadcast) and so a mid-recording
        // disconnect can invalidate the cache without leaking to a future
        // client.
        recordingOriginatorClientId = clientId

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
            recordingOriginatorClientId = nil
            sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
        }
    }

    /// Internal-for-tests entry point used by `onRecordingComplete`.
    ///
    /// Routing rules:
    /// - If a `stop_recording` waiter is parked and the waiter's transport is
    ///   still alive, deliver the payload to it directly.
    /// - Otherwise (auto-finish: max duration, file-size cap, inactivity), if
    ///   the originating `start_recording` client is still authenticated,
    ///   deliver `.recording(payload)` to that client only and notify other
    ///   authenticated clients with `.recordingStopped`. This avoids the
    ///   privacy-leak shape of broadcasting the video to every authenticated
    ///   client while still resolving the originator's parked
    ///   `waitForRecording`.
    /// - Otherwise (originator gone, no waiter), broadcast `.recordingStopped`
    ///   only and cache the payload in `completedRecording` for a later
    ///   `stop_recording` pickup. The cache is invalidated on session release
    ///   so it can't leak across drivers.
    func deliverRecordingResult(_ result: Result<RecordingPayload, Error>) async {
        recordingPhase = .idle
        brains.stakeout = nil
        let originator = recordingOriginatorClientId

        // Pending stop waiter wins — that's the request the originator (or
        // another driver-session client) is parked on right now.
        if let pending = pendingRecordingResponse {
            pendingRecordingResponse = nil
            recordingOriginatorClientId = nil
            completedRecording = .none
            switch result {
            case .success(let payload):
                sendMessage(.recording(payload), requestId: pending.requestId, respond: pending.respond)
            case .failure(let error):
                let serverError = ServerError(kind: .recording, message: error.localizedDescription)
                sendMessage(.error(serverError), requestId: pending.requestId, respond: pending.respond)
            }
            return
        }

        // Auto-finish path. Cache the outcome first so a later `stop_recording`
        // can still pick it up if the targeted delivery below cannot find an
        // active client.
        completedRecording = RecordingOutcome(result: result)

        switch result {
        case .success(let payload):
            let authenticated = await muscle.authenticatedClientIDs
            if let originator, authenticated.contains(originator),
               let payloadData = encodeEnvelope(.recording(payload)) {
                // Targeted delivery to the start_recording originator. They
                // are parked on `waitForRecording` and need the payload — but
                // every other client gets the lightweight `.recordingStopped`
                // notification, per the wire-protocol contract.
                //
                // Clear the cache ONLY after `sendData` confirms it handed the
                // payload to a live transport closure. If the transport was
                // torn down between the authenticated-set read and the send,
                // `sendData` returns false and we keep the cached payload so a
                // subsequent `stop_recording` (or `tearDown`) can still resolve
                // it — never drop a recording into the void.
                let delivered = await muscle.sendData(payloadData, toClient: originator)
                if delivered {
                    completedRecording = .none
                    recordingOriginatorClientId = nil
                }
                if let stoppedData = encodeEnvelope(.recordingStopped) {
                    for otherClient in authenticated where otherClient != originator {
                        await muscle.sendData(stoppedData, toClient: otherClient)
                    }
                }
            } else {
                // Originator is gone (or never recorded). Notify everyone the
                // recording finished; the payload sits in `completedRecording`
                // for the next `stop_recording` pickup. Clear the originator
                // since no live client is parked on its delivery.
                recordingOriginatorClientId = nil
                await broadcastToAll(.recordingStopped)
            }
        case .failure(let error):
            recordingOriginatorClientId = nil
            await broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
        }
    }

    func handleStopRecording(clientId: Int? = nil, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        switch completedRecording {
        case .succeeded(let payload):
            completedRecording = .none
            recordingOriginatorClientId = nil
            sendMessage(.recording(payload), requestId: requestId, respond: respond)
            return
        case .failed(let error):
            completedRecording = .none
            recordingOriginatorClientId = nil
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

        // Rebind the originator to whoever issued this `stop_recording`. If
        // client A started the recording and disconnected, the originator was
        // already cleared on disconnect; this lets client B's stop request
        // own the in-flight payload routing.
        if let clientId {
            // All authenticated clients in an active session are trusted peers
            // (the cooperative co-driver model from #314); rebinding the
            // originator on stop_recording here matches that contract, not the
            // stricter "originator-only" identity model.
            recordingOriginatorClientId = clientId
        }
        pendingRecordingResponse = (requestId: requestId, respond: respond)
        if await stakeout.isRecording {
            await stakeout.stopRecording(reason: .manual)
        }
    }

    // MARK: - Lifecycle Invalidation

    /// Invalidate recording state when a client disconnects.
    ///
    /// If the disconnecting client is the originator of an in-flight or
    /// just-completed recording, clear any cached payload (so a future client
    /// can't pick it up) and tear down any pending `stop_recording` waiter
    /// (so the next legitimate stop isn't blocked by "Recording stop already
    /// in progress"). Recordings in flight keep running on the stakeout —
    /// the on-complete handler will see the cleared originator and fall back
    /// to the cache-and-broadcast path.
    func invalidateRecordingForDisconnect(clientId: Int) {
        guard clientId == recordingOriginatorClientId else { return }
        recordingOriginatorClientId = nil
        pendingRecordingResponse = nil
        completedRecording = .none
    }

    /// Invalidate recording state when the driver session releases (timeout
    /// or all-clients-disconnected drain). A future driver claiming the
    /// session must not see a recording the previous driver started.
    func invalidateRecordingForSessionRelease() {
        recordingOriginatorClientId = nil
        pendingRecordingResponse = nil
        completedRecording = .none
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheGetaway {

    // MARK: - Recording Lifecycle

    struct RecordingWaiter {
        let requestId: String?
        let ownerClientId: Int?
        let respond: (Data) -> Void
    }

    enum RecordingCachePolicy {
        case anySessionClient
        case originatorOnly(Int)

        func allows(clientId: Int?) -> Bool {
            switch self {
            case .anySessionClient:
                return true
            case .originatorOnly(let owner):
                return clientId == owner
            }
        }
    }

    struct CompletedRecordingRoute {
        let outcome: RecordingOutcome
        let cachePolicy: RecordingCachePolicy
    }

    enum RecordingInvalidationReason {
        case originatorDisconnected
        case sessionReleased

        var message: String {
            switch self {
            case .originatorDisconnected:
                return "Recording owner disconnected"
            case .sessionReleased:
                return "Recording session released"
            }
        }
    }

    enum RecordingRouteState {
        case idle
        case starting(ownerClientId: Int?)
        case recording(stakeout: TheStakeout, ownerClientId: Int?)
        case stopping(stakeout: TheStakeout, waiter: RecordingWaiter)
        case completed(CompletedRecordingRoute)
        case invalidated(stakeout: TheStakeout?, reason: RecordingInvalidationReason)

        var activeStakeout: TheStakeout? {
            switch self {
            case .recording(let stakeout, _), .stopping(let stakeout, _), .invalidated(let stakeout?, _):
                return stakeout
            case .idle, .starting, .completed, .invalidated(nil, _):
                return nil
            }
        }

        var phase: RecordingPhase {
            switch self {
            case .idle, .completed, .invalidated(nil, _):
                return .idle
            case .starting:
                return .starting
            case .recording(let stakeout, _), .stopping(let stakeout, _), .invalidated(let stakeout?, _):
                return .recording(stakeout: stakeout)
            }
        }

        var ownerClientId: Int? {
            switch self {
            case .starting(let owner), .recording(_, let owner):
                return owner
            case .stopping(_, let waiter):
                return waiter.ownerClientId
            case .completed(let completion):
                if case .originatorOnly(let owner) = completion.cachePolicy {
                    return owner
                }
                return nil
            case .idle, .invalidated:
                return nil
            }
        }
    }

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
        switch recordingRouteState {
        case .recording, .stopping, .invalidated:
            sendMessage(.error(ServerError(kind: .recording, message: "Recording already in progress")), requestId: requestId, respond: respond)
            return
        case .starting:
            sendMessage(.error(ServerError(kind: .recording, message: "Recording start already in progress")), requestId: requestId, respond: respond)
            return
        case .idle, .completed:
            break
        }

        // Claim the phase synchronously before the first await so a second
        // start_recording landing on the actor sees `.starting` and is rejected.
        recordingRouteState = .starting(ownerClientId: clientId)

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
            guard case .starting(let owner) = recordingRouteState, owner == clientId else {
                let reason = recordingInvalidationReason ?? .sessionReleased
                recordingRouteState = .invalidated(stakeout: recorder, reason: reason)
                if await recorder.isRecording {
                    await recorder.stopRecording(reason: .manual)
                }
                sendMessage(.error(ServerError(kind: .recording, message: reason.message)), requestId: requestId, respond: respond)
                return
            }
            recordingRouteState = .recording(stakeout: recorder, ownerClientId: clientId)
            brains.stakeout = recorder
            sendMessage(.recordingStarted, requestId: requestId, respond: respond)
        } catch {
            // Roll back the claim so the next start_recording can proceed.
            recordingRouteState = .idle
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
    /// - Otherwise, broadcast `.recordingStopped` only and cache according to
    ///   the route state's policy. Anonymous completions remain available to
    ///   the active session; originator-owned completions are originator-only
    ///   and disconnect/session invalidation clears them before a different
    ///   client can pick up the payload.
    func deliverRecordingResult(_ result: Result<RecordingPayload, Error>) async {
        let state = recordingRouteState
        switch state {
        case .recording, .stopping, .invalidated:
            break
        case .idle, .starting, .completed:
            return
        }
        brains.stakeout = nil
        let owner = state.ownerClientId

        // Pending stop waiter wins — that's the request the originator (or
        // another driver-session client) is parked on right now.
        if case .stopping(_, let pending) = state {
            recordingRouteState = .idle
            switch result {
            case .success(let payload):
                sendMessage(.recording(payload), requestId: pending.requestId, respond: pending.respond)
            case .failure(let error):
                let serverError = ServerError(kind: .recording, message: error.localizedDescription)
                sendMessage(.error(serverError), requestId: pending.requestId, respond: pending.respond)
            }
            return
        }

        if case .invalidated = state {
            recordingRouteState = .idle
            switch result {
            case .success:
                await broadcastToAll(.recordingStopped)
            case .failure(let error):
                await broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
            }
            return
        }

        // Auto-finish path. Cache the outcome first so a later `stop_recording`
        // can still pick it up if the targeted delivery below cannot find an
        // active client.
        let cachePolicy: RecordingCachePolicy = owner.map(RecordingCachePolicy.originatorOnly) ?? .anySessionClient
        recordingRouteState = .completed(CompletedRecordingRoute(
            outcome: RecordingOutcome(result: result),
            cachePolicy: cachePolicy
        ))

        switch result {
        case .success(let payload):
            let authenticated = await muscle.authenticatedClientIDs
            if let owner, authenticated.contains(owner),
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
                let delivered = await muscle.sendData(payloadData, toClient: owner)
                if delivered {
                    recordingRouteState = .idle
                }
                if let stoppedData = encodeEnvelope(.recordingStopped) {
                    for otherClient in authenticated where otherClient != owner {
                        await muscle.sendData(stoppedData, toClient: otherClient)
                    }
                }
            } else {
                // Originator is gone (or never recorded). Notify everyone the
                // recording finished. Anonymous recordings remain cacheable
                // for a later `stop_recording`; originator-owned recordings
                // remain originator-only and will be dropped if that owner
                // disconnects.
                await broadcastToAll(.recordingStopped)
            }
        case .failure(let error):
            await broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
        }
    }

    func handleStopRecording(clientId: Int? = nil, requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        switch recordingRouteState {
        case .completed(let completion):
            guard completion.cachePolicy.allows(clientId: clientId) else {
                sendMessage(.error(ServerError(kind: .recording, message: "No recording in progress")), requestId: requestId, respond: respond)
                return
            }
            recordingRouteState = .idle
            switch completion.outcome {
            case .succeeded(let payload):
                sendMessage(.recording(payload), requestId: requestId, respond: respond)
            case .failed(let error):
                sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
            case .none:
                sendMessage(.error(ServerError(kind: .recording, message: "No recording in progress")), requestId: requestId, respond: respond)
            }
            return
        case .recording(let stakeout, _):
            let waiter = RecordingWaiter(requestId: requestId, ownerClientId: clientId, respond: respond)
            recordingRouteState = .stopping(stakeout: stakeout, waiter: waiter)
            if await stakeout.isRecording {
                await stakeout.stopRecording(reason: .manual)
            }
        case .stopping:
            sendMessage(.error(ServerError(kind: .recording, message: "Recording stop already in progress")), requestId: requestId, respond: respond)
        case .idle, .starting, .invalidated:
            sendMessage(.error(ServerError(kind: .recording, message: "No recording in progress")), requestId: requestId, respond: respond)
        }
    }

    // MARK: - Lifecycle Invalidation

    /// Invalidate recording state when a client disconnects.
    ///
    /// If the disconnecting client owns an in-flight or just-completed route,
    /// clear the cache or mark the active stakeout invalidated. The stakeout
    /// may still finish asynchronously, but its completion is discarded rather
    /// than cached for another client.
    func invalidateRecordingForDisconnect(clientId: Int) {
        switch recordingRouteState {
        case .starting(let owner?) where owner == clientId:
            recordingRouteState = .invalidated(stakeout: nil, reason: .originatorDisconnected)
        case .recording(let stakeout, let owner?) where owner == clientId:
            recordingRouteState = .invalidated(stakeout: stakeout, reason: .originatorDisconnected)
        case .stopping(let stakeout, let waiter) where waiter.ownerClientId == clientId:
            recordingRouteState = .invalidated(stakeout: stakeout, reason: .originatorDisconnected)
        case .completed(let completion):
            if case .originatorOnly(let owner) = completion.cachePolicy, owner == clientId {
                recordingRouteState = .idle
            }
        case .idle, .starting, .recording, .stopping, .invalidated:
            break
        }
    }

    /// Invalidate recording state when the driver session releases (timeout
    /// or all-clients-disconnected drain). A future driver claiming the
    /// session must not see a recording the previous driver started.
    func invalidateRecordingForSessionRelease() {
        switch recordingRouteState {
        case .recording(let stakeout, _), .stopping(let stakeout, _), .invalidated(let stakeout?, _):
            recordingRouteState = .invalidated(stakeout: stakeout, reason: .sessionReleased)
        case .starting:
            recordingRouteState = .invalidated(stakeout: nil, reason: .sessionReleased)
        case .idle, .completed, .invalidated(nil, _):
            // Completed routes have no pending async stakeout work; release can clear them immediately.
            recordingRouteState = .idle
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

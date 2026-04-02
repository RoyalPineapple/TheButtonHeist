#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Screen Request Handler

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard let (image, bounds) = bagman.captureScreen() else {
            sendMessage(.error("Could not access app window"), requestId: requestId, respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screen as PNG"), requestId: requestId, respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        sendMessage(.screen(payload), requestId: requestId, respond: respond)
        insideJobLogger.debug("Screen sent: \(pngData.count) bytes")
    }

    func broadcastScreen() {
        guard muscle.hasSubscribers else { return }
        guard let (image, bounds) = bagman.captureScreen(),
              let pngData = image.pngData() else { return }

        let screenPayload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        broadcastToSubscribed(.screen(screenPayload))
    }

    // MARK: - Screen Recording

    func handleStartRecording(_ config: RecordingConfig, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        if case .recording = recordingState {
            sendMessage(.recordingError("Recording already in progress"), requestId: requestId, respond: respond)
            return
        }

        let recorder = TheStakeout()
        recorder.captureFrame = { [weak self] in
            self?.bagman.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            switch result {
            case .success(let payload):
                self?.broadcastToAll(.recording(payload))
            case .failure(let error):
                self?.broadcastToAll(.recordingError(error.localizedDescription))
            }
            self?.recordingState = .idle
            self?.bagman.stakeout = nil
        }

        do {
            try recorder.startRecording(config: config)
            recordingState = .recording(stakeout: recorder)
            bagman.stakeout = recorder
            sendMessage(.recordingStarted, requestId: requestId, respond: respond)
        } catch {
            sendMessage(.recordingError(error.localizedDescription), requestId: requestId, respond: respond)
        }
    }

    func handleStopRecording(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        guard let stakeout else {
            sendMessage(.recordingError("No recording in progress"), requestId: requestId, respond: respond)
            return
        }
        if stakeout.state == .recording {
            stakeout.stopRecording(reason: .manual)
        }
        sendMessage(.recordingStopped, requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

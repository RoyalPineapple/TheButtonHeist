#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheInsideJob {

    // MARK: - Screen Request Handler

    func handleScreen(respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard let (image, bounds) = bagman.captureScreen() else {
            sendMessage(.error("Could not access app window"), respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screen as PNG"), respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        sendMessage(.screen(payload), respond: respond)
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

        if let data = try? JSONEncoder().encode(ServerMessage.screen(screenPayload)) {
            broadcastToSubscribed(data)
        }
    }

    // MARK: - Screen Recording

    func handleStartRecording(_ config: RecordingConfig, respond: @escaping (Data) -> Void) {
        if stakeout?.state == .recording {
            sendMessage(.recordingError("Recording already in progress"), respond: respond)
            return
        }

        let recorder = TheStakeout()
        recorder.captureFrame = { [weak self] in
            self?.bagman.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            switch result {
            case .success(let payload):
                if let data = try? JSONEncoder().encode(ServerMessage.recording(payload)) {
                    self?.broadcastToAll(data)
                }
            case .failure(let error):
                if let data = try? JSONEncoder().encode(ServerMessage.recordingError(error.localizedDescription)) {
                    self?.broadcastToAll(data)
                }
            }
            self?.stakeout = nil
            self?.bagman.stakeout = nil
        }

        stakeout = recorder
        bagman.stakeout = recorder
        do {
            try recorder.startRecording(config: config)
            sendMessage(.recordingStarted, respond: respond)
        } catch {
            sendMessage(.recordingError(error.localizedDescription), respond: respond)
            stakeout = nil
            bagman.stakeout = nil
        }
    }

    func handleStopRecording(respond: @escaping (Data) -> Void) {
        guard let stakeout else {
            sendMessage(.recordingError("No recording in progress"), respond: respond)
            return
        }
        if stakeout.state == .recording {
            stakeout.stopRecording(reason: .manual)
        }
        sendMessage(.recordingStopped, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

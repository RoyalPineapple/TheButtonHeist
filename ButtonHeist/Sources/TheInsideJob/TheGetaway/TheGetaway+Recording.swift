#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

// MARK: - Recording Lifecycle

extension TheGetaway {

    enum RecordingPhase {
        case idle
        case recording(stakeout: TheStakeout)
    }

    func handleStartRecording(_ config: RecordingConfig, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        if case .recording = recordingPhase {
            sendMessage(.recordingError("Recording already in progress"), requestId: requestId, respond: respond)
            return
        }

        let recorder = TheStakeout()
        recorder.captureFrame = { [weak self] in
            self?.brains.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            switch result {
            case .success(let payload):
                self?.broadcastToAll(.recording(payload))
            case .failure(let error):
                self?.broadcastToAll(.recordingError(error.localizedDescription))
            }
            self?.recordingPhase = .idle
            self?.brains.stakeout = nil
        }

        do {
            try recorder.startRecording(config: config)
            recordingPhase = .recording(stakeout: recorder)
            brains.stakeout = recorder
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
        if stakeout.isRecording {
            stakeout.stopRecording(reason: .manual)
        }
        sendMessage(.recordingStopped, requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

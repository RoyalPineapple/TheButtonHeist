#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

extension TheGetaway {

    // MARK: - Recording Lifecycle

    enum RecordingPhase {
        case idle
        case recording(stakeout: TheStakeout)
    }

    func handleStartRecording(_ config: RecordingConfig, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        if case .recording = recordingPhase {
            sendMessage(.error(ServerError(kind: .recording, message: "Recording already in progress")), requestId: requestId, respond: respond)
            return
        }

        completedRecording = nil
        let recorder = TheStakeout()
        recorder.captureFrame = { [weak self] in
            self?.brains.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            guard let self else { return }
            self.recordingPhase = .idle
            self.brains.stakeout = nil
            self.completedRecording = result

            if let pending = self.pendingRecordingResponse {
                self.pendingRecordingResponse = nil
                switch result {
                case .success(let payload):
                    self.sendMessage(.recording(payload), requestId: pending.requestId, respond: pending.respond)
                case .failure(let error):
                    let serverError = ServerError(kind: .recording, message: error.localizedDescription)
                    self.sendMessage(.error(serverError), requestId: pending.requestId, respond: pending.respond)
                }
                return
            }

            switch result {
            case .success:
                self.broadcastToAll(.recordingStopped)
            case .failure(let error):
                self.broadcastToAll(.error(ServerError(kind: .recording, message: error.localizedDescription)))
            }
        }

        do {
            try recorder.startRecording(config: config)
            recordingPhase = .recording(stakeout: recorder)
            brains.stakeout = recorder
            sendMessage(.recordingStarted, requestId: requestId, respond: respond)
        } catch {
            sendMessage(.error(ServerError(kind: .recording, message: error.localizedDescription)), requestId: requestId, respond: respond)
        }
    }

    func handleStopRecording(requestId: String? = nil, respond: @escaping (Data) -> Void) {
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
        if stakeout.isRecording {
            stakeout.stopRecording(reason: .manual)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

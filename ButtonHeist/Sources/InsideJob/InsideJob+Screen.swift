#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension InsideJob {

    // MARK: - Screen Capture

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = getTraversableWindows()
        guard let background = windows.last else { return nil }
        let bounds = background.window.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
            for (window, _) in windows.reversed() {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        return (image, bounds)
    }

    // MARK: - Screen Request Handler

    func handleScreen(respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard let (image, bounds) = captureScreen() else {
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
        guard !subscribedClients.isEmpty else { return }
        guard let (image, bounds) = captureScreen(),
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

    /// Capture the screen including the fingerprint overlay (for recordings).
    /// Unlike captureScreen(), this includes FingerprintWindow so
    /// tap/swipe indicators are visible in the video.
    private func captureScreenForRecording() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return nil
        }

        let allWindows = windowScene.windows
            .filter { !$0.isHidden && $0.bounds.size != .zero }
            .sorted { $0.windowLevel < $1.windowLevel }

        guard let background = allWindows.first else { return nil }
        let bounds = background.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            for window in allWindows {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
    }

    func handleStartRecording(_ config: RecordingConfig, respond: @escaping (Data) -> Void) {
        if stakeout?.state == .recording {
            sendMessage(.recordingError("Recording already in progress"), respond: respond)
            return
        }

        let recorder = Stakeout()
        recorder.captureFrame = { [weak self] in
            self?.captureScreenForRecording()
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
        }

        stakeout = recorder
        do {
            try recorder.startRecording(config: config)
            sendMessage(.recordingStarted, respond: respond)
        } catch {
            sendMessage(.recordingError(error.localizedDescription), respond: respond)
            stakeout = nil
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

    /// If recording, capture a bonus frame to ensure the action's visual effect is captured.
    func captureActionFrame() {
        stakeout?.captureActionFrame()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit
import AVFoundation
import os.log
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "recording")

/// Screen recording engine. Captures frames using TheInsideJob's window compositing
/// and encodes them as H.264/MP4 using AVAssetWriter.
@MainActor
final class TheStakeout {

    // MARK: - State Machine

    private enum StakeoutPhase {
        case idle
        case recording(RecordingSession)
        case finalizing(FinalizingSession)
    }

    struct RecordingSession {
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
        let outputURL: URL
        let screenBounds: CGRect
        let fps: Int
        let maxDuration: TimeInterval
        let inactivityTimeout: TimeInterval
        let startTime: Date
        var captureTimer: Task<Void, Never>
        var inactivityCheckTask: Task<Void, Never>
        var frameCount: Int
        var lastFrameTime: CMTime
        var lastActivityTime: Date
        var interactionLog: [InteractionEvent]
        var didLogCapWarning: Bool
    }

    struct FinalizingSession {
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let outputURL: URL
        let startTime: Date
        let frameCount: Int
        let fps: Int
        let screenBounds: CGRect
        let interactionLog: [InteractionEvent]
    }

    private var stakeoutPhase: StakeoutPhase = .idle

    /// Maximum number of interaction events to record. Beyond this, events are silently dropped
    /// and the log is capped to prevent unbounded memory growth in long recordings.
    private static let maxInteractionCount = 500

    var isRecording: Bool {
        if case .recording = stakeoutPhase { return true }
        return false
    }

    var isFinalizing: Bool {
        if case .finalizing = stakeoutPhase { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = stakeoutPhase { return true }
        return false
    }

    /// Interaction log — only meaningful during recording.
    var interactionLog: [InteractionEvent] {
        switch stakeoutPhase {
        case .idle: return []
        case .recording(let session): return session.interactionLog
        case .finalizing(let session): return session.interactionLog
        }
    }

    // Frame provider closure — set by TheInsideJob to provide captureScreenForRecording()
    var captureFrame: (() -> UIImage?)?

    // Completion handler — called when recording finishes for any reason
    var onRecordingComplete: ((Result<RecordingPayload, Error>) -> Void)?

    // MARK: - Public API

    func startRecording(config: RecordingConfig) throws {
        guard case .idle = stakeoutPhase else {
            throw TheStakeoutError.alreadyRecording
        }

        // Apply config with clamping
        let fps = max(1, min(15, config.fps ?? 8))
        let inactivityTimeout = max(1.0, config.inactivityTimeout ?? 5.0)
        let maxDuration = max(1.0, config.maxDuration ?? 60.0)
        // Determine output dimensions from screen.
        // Default: 1x point resolution (native pixels / screen scale).
        // If caller provides scale, use that fraction of native resolution.
        let screen = UIScreen.main
        let nativeWidth = screen.bounds.width * screen.scale
        let nativeHeight = screen.bounds.height * screen.scale
        let effectiveScale: CGFloat = if let requestedScale = config.scale {
            max(0.25, min(1.0, CGFloat(requestedScale)))
        } else {
            1.0 / screen.scale
        }
        let width = Int(nativeWidth * effectiveScale)
        let height = Int(nativeHeight * effectiveScale)
        // H.264 requires even pixel dimensions — the codec operates on 16x16 macroblocks,
        // and AVAssetWriter will reject odd-dimensioned buffers. Round up to the next even number.
        let evenWidth = width % 2 == 0 ? width : width + 1
        let evenHeight = height % 2 == 0 ? height : height + 1
        let screenBounds = CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight)

        // Set up temp file
        let tempDir = NSTemporaryDirectory()
        let fileName = "stakeout-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)

        // Configure AVAssetWriter
        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: evenWidth * evenHeight * 2, // ~2 bits/pixel
                AVVideoMaxKeyFrameIntervalKey: fps * 2, // Keyframe every 2 seconds
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: evenWidth,
            kCVPixelBufferHeightKey as String: evenHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw TheStakeoutError.writerSetupFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        writer.startSession(atSourceTime: .zero)

        let now = Date()
        let session = RecordingSession(
            assetWriter: writer,
            videoInput: input,
            pixelBufferAdaptor: adaptor,
            outputURL: url,
            screenBounds: screenBounds,
            fps: fps,
            maxDuration: maxDuration,
            inactivityTimeout: inactivityTimeout,
            startTime: now,
            captureTimer: Task { },
            inactivityCheckTask: Task { },
            frameCount: 0,
            lastFrameTime: .zero,
            lastActivityTime: now,
            interactionLog: [],
            didLogCapWarning: false
        )

        stakeoutPhase = .recording(session)

        logger.info("Recording started: \(evenWidth)x\(evenHeight) @ \(fps)fps, effectiveScale=\(effectiveScale)")

        // Start frame capture timer and inactivity monitor — these mutate the session
        // via stakeoutPhase, so they must be started after the state transition.
        startCaptureTimer()
        startInactivityMonitor()
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) {
        guard case .recording(let session) = stakeoutPhase else { return }

        logger.info("Stopping recording: reason=\(reason.rawValue), frames=\(session.frameCount)")

        session.captureTimer.cancel()
        session.inactivityCheckTask.cancel()

        let finalizingSession = FinalizingSession(
            assetWriter: session.assetWriter,
            videoInput: session.videoInput,
            outputURL: session.outputURL,
            startTime: session.startTime,
            frameCount: session.frameCount,
            fps: session.fps,
            screenBounds: session.screenBounds,
            interactionLog: session.interactionLog
        )
        stakeoutPhase = .finalizing(finalizingSession)

        finalizeRecording(session: finalizingSession, reason: reason)
    }

    /// Call this whenever client activity occurs (commands received, etc.)
    func noteActivity() {
        guard case .recording(var session) = stakeoutPhase else { return }
        session.lastActivityTime = Date()
        stakeoutPhase = .recording(session)
    }

    /// Call this whenever a screen change is detected (hierarchy hash change)
    func noteScreenChange() {
        guard case .recording(var session) = stakeoutPhase else { return }
        session.lastActivityTime = Date()
        stakeoutPhase = .recording(session)
    }

    /// Capture an extra frame outside the regular timer cadence.
    /// Used to ensure actions are represented in the recording.
    func captureActionFrame() {
        guard case .recording = stakeoutPhase else { return }
        captureAndAppendFrame()
    }

    /// Elapsed time since recording started, in seconds.
    var recordingElapsed: Double {
        guard case .recording(let session) = stakeoutPhase else { return 0 }
        return Date().timeIntervalSince(session.startTime)
    }

    /// Append an interaction event to the recording log.
    /// Silently drops events beyond `maxInteractionCount` to prevent unbounded growth.
    func recordInteraction(event: InteractionEvent) {
        guard case .recording(var session) = stakeoutPhase else { return }
        guard session.interactionLog.count < Self.maxInteractionCount else {
            if !session.didLogCapWarning {
                session.didLogCapWarning = true
                stakeoutPhase = .recording(session)
                logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
            }
            return
        }
        session.interactionLog.append(event)
        stakeoutPhase = .recording(session)
    }

    // MARK: - Frame Capture

    private func startCaptureTimer() {
        guard case .recording(var session) = stakeoutPhase else { return }
        let interval = Duration.seconds(1) / session.fps
        session.captureTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.captureAndAppendFrame()
                try? await Task.sleep(for: interval)
            }
        }
        stakeoutPhase = .recording(session)
    }

    private func captureAndAppendFrame() {
        guard case .recording(var session) = stakeoutPhase,
              session.videoInput.isReadyForMoreMediaData,
              let image = captureFrame?() else {
            return
        }

        // Check file size guard (7MB raw = ~9.3MB base64, under 10MB buffer limit)
        // If we can't read the file size, skip the check and continue recording
        let fileSize: Int?
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: session.outputURL.path)
            fileSize = attributes[.size] as? Int
        } catch {
            logger.warning("Could not read recording file size, skipping size check: \(error)")
            fileSize = nil
        }
        if let fileSize, fileSize > 7_000_000 {
            logger.warning("File size limit reached: \(fileSize) bytes")
            stopRecording(reason: .fileSizeLimit)
            return
        }

        // Check max duration
        if Date().timeIntervalSince(session.startTime) >= session.maxDuration {
            logger.warning("Max duration reached")
            stopRecording(reason: .maxDuration)
            return
        }

        // Create pixel buffer from UIImage
        guard let pixelBuffer = createPixelBuffer(from: image, session: session) else { return }

        let frameTime = CMTime(value: Int64(session.frameCount), timescale: Int32(session.fps))
        if session.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) {
            session.frameCount += 1
            session.lastFrameTime = frameTime
            stakeoutPhase = .recording(session)
        }
    }

    private func createPixelBuffer(from image: UIImage, session: RecordingSession) -> CVPixelBuffer? {
        guard let pool = session.pixelBufferAdaptor.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(session.screenBounds.width),
            height: Int(session.screenBounds.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }

        // Draw the image scaled into the pixel buffer.
        // Fingerprint indicators are rendered by TheFingerprints (on-screen UIView overlay)
        // and captured naturally via drawHierarchy — no CGContext compositing needed.
        context.draw(cgImage, in: session.screenBounds)

        return buffer
    }

    // MARK: - Inactivity Detection
    //
    // Inactivity is tracked via `lastActivityTime`, updated by:
    //   - `noteActivity()` — called on each incoming client command
    //   - `noteScreenChange()` — called when TheBagman detects a hierarchy hash change
    //
    // Note: screen hashing operates on the accessibility hierarchy, not pixels.
    // Subtle pixel-only animations (e.g. spinner rotation) do NOT count as activity,
    // so they won't prevent inactivity timeout. This is intentional — we only extend
    // recording when meaningful UI content changes.

    private func startInactivityMonitor() {
        guard case .recording(var session) = stakeoutPhase else { return }
        session.inactivityCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1)) // Check every second
                guard let self, case .recording(let currentSession) = self.stakeoutPhase else { continue }

                let elapsed = Date().timeIntervalSince(currentSession.lastActivityTime)
                if elapsed >= currentSession.inactivityTimeout {
                    logger.info("Inactivity timeout: \(elapsed)s since last activity")
                    self.stopRecording(reason: .inactivity)
                    return
                }
            }
        }
        stakeoutPhase = .recording(session)
    }

    // MARK: - Finalization

    private func finalizeRecording(session: FinalizingSession, reason: RecordingPayload.StopReason) {
        let writer = session.assetWriter

        session.videoInput.markAsFinished()

        let endTime = Date()
        let outputURL = session.outputURL
        let startTime = session.startTime
        let frameCount = session.frameCount
        let fps = session.fps
        let width = Int(session.screenBounds.width)
        let height = Int(session.screenBounds.height)
        let interactions = session.interactionLog

        writer.finishWriting { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                defer { self.cleanup(outputURL: outputURL) }
                guard let currentWriter = self.currentWriter else {
                    self.deliverError(.finalizationFailed("Writer deallocated during finalization"))
                    return
                }

                if currentWriter.status == .failed {
                    self.deliverError(.finalizationFailed(currentWriter.error?.localizedDescription ?? "Unknown"))
                    return
                }

                guard let videoData = try? Data(contentsOf: outputURL) else {
                    self.deliverError(.finalizationFailed("Could not read output file"))
                    return
                }

                let duration = endTime.timeIntervalSince(startTime)

                let payload = RecordingPayload(
                    videoData: videoData.base64EncodedString(),
                    width: width,
                    height: height,
                    duration: duration,
                    frameCount: frameCount,
                    fps: fps,
                    startTime: startTime,
                    endTime: endTime,
                    stopReason: reason,
                    interactionLog: interactions.isEmpty ? nil : interactions
                )

                logger.info("Recording complete: \(frameCount) frames, \(String(format: "%.1f", duration))s, \(videoData.count) bytes")
                self.onRecordingComplete?(.success(payload))
            }
        }
    }

    /// Access the writer from the current finalizing state for post-completion checks.
    private var currentWriter: AVAssetWriter? {
        guard case .finalizing(let session) = stakeoutPhase else { return nil }
        return session.assetWriter
    }

    private func deliverError(_ error: TheStakeoutError) {
        logger.error("Recording error: \(error)")
        onRecordingComplete?(.failure(error))
    }

    private func cleanup(outputURL: URL) {
        stakeoutPhase = .idle

        // Clean up temp file
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            logger.warning("Failed to clean up recording temp file at \(outputURL.path): \(error)")
        }
    }

    enum TheStakeoutError: Error, LocalizedError {
        case alreadyRecording
        case writerSetupFailed(String)
        case finalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .writerSetupFailed(let message): return "Failed to set up video writer: \(message)"
            case .finalizationFailed(let message): return "Failed to finalize recording: \(message)"
            }
        }
    }
}

#endif
#endif

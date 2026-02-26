#if canImport(UIKit)
#if DEBUG
import UIKit
import AVFoundation
import os.log
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.insidejob", category: "recording")

/// Screen recording engine. Captures frames using InsideJob's window compositing
/// and encodes them as H.264/MP4 using AVAssetWriter.
@MainActor
final class TheStakeout {

    enum State {
        case idle
        case recording
        case finalizing
    }

    private(set) var state: State = .idle

    // Configuration (with clamped defaults)
    private var fps: Int = 8
    private var inactivityTimeout: TimeInterval = 5.0
    private var maxDuration: TimeInterval = 60.0
    // AVAssetWriter pipeline
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?

    // Frame capture
    private var captureTimer: Task<Void, Never>?
    private var frameCount: Int = 0
    private var startTime: Date?
    private var lastFrameTime: CMTime = .zero
    private var screenBounds: CGRect = .zero

    // Inactivity tracking
    private var lastActivityTime: Date = Date()
    private var inactivityCheckTask: Task<Void, Never>?

    // Interaction recording — wire-level command/result log
    private(set) var interactionLog: [InteractionEvent] = []
    /// Maximum number of interaction events to record. Beyond this, events are silently dropped
    /// and the log is capped to prevent unbounded memory growth in long recordings.
    private static let maxInteractionCount = 500

    // Frame provider closure — set by InsideJob to provide captureScreenForRecording()
    var captureFrame: (() -> UIImage?)?

    // Completion handler — called when recording finishes for any reason
    var onRecordingComplete: ((Result<RecordingPayload, Error>) -> Void)?

    // MARK: - Public API

    func startRecording(config: RecordingConfig) throws {
        guard state == .idle else {
            throw TheStakeoutError.alreadyRecording
        }

        // Apply config with clamping
        fps = max(1, min(15, config.fps ?? 8))
        inactivityTimeout = max(1.0, config.inactivityTimeout ?? 5.0)
        maxDuration = max(1.0, config.maxDuration ?? 60.0)
        // Determine output dimensions from screen.
        // Default: 1x point resolution (native pixels / screen scale).
        // If caller provides scale, use that fraction of native resolution.
        let screen = UIScreen.main
        let nativeWidth = screen.bounds.width * screen.scale
        let nativeHeight = screen.bounds.height * screen.scale
        let effectiveScale: CGFloat
        if let requestedScale = config.scale {
            effectiveScale = max(0.25, min(1.0, CGFloat(requestedScale)))
        } else {
            // Default: 1x point size = native / screen.scale
            effectiveScale = 1.0 / screen.scale
        }
        let width = Int(nativeWidth * effectiveScale)
        let height = Int(nativeHeight * effectiveScale)
        // H.264 requires even pixel dimensions — the codec operates on 16x16 macroblocks,
        // and AVAssetWriter will reject odd-dimensioned buffers. Round up to the next even number.
        let evenWidth = width % 2 == 0 ? width : width + 1
        let evenHeight = height % 2 == 0 ? height : height + 1
        screenBounds = CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight)

        // Set up temp file
        let tempDir = NSTemporaryDirectory()
        let fileName = "stakeout-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        outputURL = url

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

        assetWriter = writer
        videoInput = input
        pixelBufferAdaptor = adaptor
        frameCount = 0
        startTime = Date()
        lastFrameTime = .zero
        lastActivityTime = Date()
        interactionLog = []
        state = .recording

        logger.info("Recording started: \(evenWidth)x\(evenHeight) @ \(self.fps)fps, effectiveScale=\(effectiveScale)")

        // Start frame capture timer
        startCaptureTimer()

        // Start inactivity monitor
        startInactivityMonitor()
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) {
        guard state == .recording else { return }
        state = .finalizing

        logger.info("Stopping recording: reason=\(reason.rawValue), frames=\(self.frameCount)")

        captureTimer?.cancel()
        captureTimer = nil
        inactivityCheckTask?.cancel()
        inactivityCheckTask = nil

        finalizeRecording(reason: reason)
    }

    /// Call this whenever client activity occurs (commands received, etc.)
    func noteActivity() {
        lastActivityTime = Date()
    }

    /// Call this whenever a screen change is detected (hierarchy hash change)
    func noteScreenChange() {
        lastActivityTime = Date()
    }

    /// Capture an extra frame outside the regular timer cadence.
    /// Used to ensure actions are represented in the recording.
    func captureActionFrame() {
        guard state == .recording else { return }
        captureAndAppendFrame()
    }

    /// Elapsed time since recording started, in seconds.
    var recordingElapsed: Double {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    /// Append an interaction event to the recording log.
    /// Silently drops events beyond `maxInteractionCount` to prevent unbounded growth.
    func recordInteraction(event: InteractionEvent) {
        guard state == .recording else { return }
        guard interactionLog.count < Self.maxInteractionCount else {
            if interactionLog.count == Self.maxInteractionCount {
                logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
            }
            return
        }
        interactionLog.append(event)
    }

    // MARK: - Frame Capture

    private func startCaptureTimer() {
        let interval = UInt64(1_000_000_000 / UInt64(fps))
        captureTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.captureAndAppendFrame()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func captureAndAppendFrame() {
        guard state == .recording,
              let input = videoInput, input.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor,
              let image = captureFrame?() else {
            return
        }

        // Check file size guard (7MB raw = ~9.3MB base64, under 10MB buffer limit)
        if let url = outputURL,
           let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           fileSize > 7_000_000 {
            logger.warning("File size limit reached: \(fileSize) bytes")
            stopRecording(reason: .fileSizeLimit)
            return
        }

        // Check max duration
        if let start = startTime, Date().timeIntervalSince(start) >= maxDuration {
            logger.warning("Max duration reached")
            stopRecording(reason: .maxDuration)
            return
        }

        // Create pixel buffer from UIImage
        guard let pixelBuffer = createPixelBuffer(from: image) else { return }

        let frameTime = CMTime(value: Int64(frameCount), timescale: Int32(fps))
        if adaptor.append(pixelBuffer, withPresentationTime: frameTime) {
            frameCount += 1
            lastFrameTime = frameTime
        }
    }

    private func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let pool = pixelBufferAdaptor?.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(screenBounds.width),
            height: Int(screenBounds.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }

        // Draw the image scaled into the pixel buffer.
        // Fingerprint indicators are rendered by TheFingerprints (on-screen UIView overlay)
        // and captured naturally via drawHierarchy — no CGContext compositing needed.
        context.draw(cgImage, in: screenBounds)

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
        inactivityCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
                guard let self, self.state == .recording else { continue }

                let elapsed = Date().timeIntervalSince(self.lastActivityTime)
                if elapsed >= self.inactivityTimeout {
                    logger.info("Inactivity timeout: \(elapsed)s since last activity")
                    self.stopRecording(reason: .inactivity)
                    return
                }
            }
        }
    }

    // MARK: - Finalization

    private func finalizeRecording(reason: RecordingPayload.StopReason) {
        guard let writer = assetWriter, let input = videoInput else {
            deliverError(.finalizationFailed("No active writer"))
            return
        }

        input.markAsFinished()

        let endTime = Date()
        let startTime = self.startTime ?? endTime
        let frameCount = self.frameCount
        let fps = self.fps
        let width = Int(screenBounds.width)
        let height = Int(screenBounds.height)
        let url = outputURL
        let interactions = self.interactionLog

        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                defer { self.cleanup() }

                if writer.status == .failed {
                    self.deliverError(.finalizationFailed(writer.error?.localizedDescription ?? "Unknown"))
                    return
                }

                guard let url,
                      let videoData = try? Data(contentsOf: url) else {
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

    private func deliverError(_ error: TheStakeoutError) {
        logger.error("Recording error: \(error)")
        onRecordingComplete?(.failure(error))
        cleanup()
    }

    private func cleanup() {
        state = .idle
        captureTimer?.cancel()
        captureTimer = nil
        inactivityCheckTask?.cancel()
        inactivityCheckTask = nil
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil

        interactionLog = []

        // Clean up temp file
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
        }
        outputURL = nil
    }

    enum TheStakeoutError: Error, LocalizedError {
        case alreadyRecording
        case writerSetupFailed(String)
        case finalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .writerSetupFailed(let msg): return "Failed to set up video writer: \(msg)"
            case .finalizationFailed(let msg): return "Failed to finalize recording: \(msg)"
            }
        }
    }
}

#endif
#endif

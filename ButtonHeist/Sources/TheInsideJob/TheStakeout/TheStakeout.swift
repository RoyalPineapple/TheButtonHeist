#if canImport(UIKit)
#if DEBUG
import AVFoundation
import UIKit
import os.log

import TheScore

private let logger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "recording")

/// Screen recording engine. Captures frames using TheInsideJob's window compositing
/// and encodes them as H.264/MP4 using AVAssetWriter.
///
/// Isolation: actor-isolated. The single MainActor escape hatch is `captureFrame`,
/// the closure that produces a UIImage by snapshotting the window hierarchy. Every
/// other piece of state (the `StakeoutLifecycle` state machine, AVAssetWriter, sample
/// buffers) lives inside the actor — AVAssetWriter and its pixel-buffer adaptor are
/// thread-safe and do not require MainActor isolation. The AVAssetWriter
/// `finishWriting` completion handler bridges back into the actor with
/// `Task { await self.handleFinalize(...) }` rather than the previous
/// `Task { @MainActor in ... }` shape called out in the concurrency audit.
actor TheStakeout {

    /// Screen metrics captured on MainActor and passed into the actor at startRecording.
    /// Avoids reaching back through MainActor for layout values that don't change for
    /// the duration of a recording.
    struct ScreenInfo: Sendable {
        let bounds: CGRect
        let scale: CGFloat
    }

    private struct RecordingSetup {
        let caps: [RecordedInputCap]
        let fps: Int
        let maxDuration: TimeInterval
        let inactivityTimeout: TimeInterval?
        let effectiveScale: CGFloat
        let screenBounds: CGRect
        let evenWidth: Int
        let evenHeight: Int
    }

    enum TheStakeoutError: Error, LocalizedError {
        case alreadyRecording
        case writerSetupFailed(String)
        case writerSetupFailedWithoutUnderlyingError
        case finalizationFailed(String)
        case finalizationFailedWithoutUnderlyingError

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .writerSetupFailed(let message): return "Failed to set up video writer: \(message)"
            case .writerSetupFailedWithoutUnderlyingError: return "Failed to set up video writer without an underlying AVFoundation error"
            case .finalizationFailed(let message): return "Failed to finalize recording: \(message)"
            case .finalizationFailedWithoutUnderlyingError: return "Failed to finalize recording without an underlying AVFoundation error"
            }
        }
    }

    // MARK: - Properties

    /// The single MainActor-bound thing — UI capture. Set at init, immutable thereafter.
    private let captureFrame: @MainActor @Sendable () async -> UIImage?

    /// Completion handler — called when recording finishes for any reason.
    /// Writes are actor-isolated; reads happen on MainActor inside the closure.
    /// Use ``setOnRecordingComplete(_:)`` to assign.
    private var onRecordingComplete: (@MainActor @Sendable (Result<RecordingPayload, Error>) -> Void)?

    private var lifecycle = StakeoutLifecycle()

    /// Maximum number of interaction events to record. Beyond this, events are silently dropped
    /// and the log is capped to prevent unbounded memory growth in long recordings.
    private static let maxInteractionCount = 500
    /// Raw MP4 byte cap. Base64 expansion keeps this under the 10MB wire buffer.
    private static let maxVideoDataBytes = 7_000_000

    var isRecording: Bool {
        lifecycle.isRecording
    }

    var isFinalizing: Bool {
        lifecycle.isFinalizing
    }

    var isIdle: Bool {
        lifecycle.isIdle
    }

    /// Interaction log — only meaningful during recording.
    var interactionLog: [InteractionEvent] {
        lifecycle.interactionLog
    }

    /// Elapsed time since recording started, in seconds.
    var recordingElapsed: Double {
        lifecycle.recordingElapsed()
    }

    var lifecycleSnapshot: LifecycleSnapshot {
        lifecycle.snapshot
    }

    private static func clampInt(
        name: String,
        requested: Int?,
        defaultValue: Int,
        range: ClosedRange<Int>,
        reason: String,
        caps: inout [RecordedInputCap]
    ) -> Int {
        let value: Int
        switch requested {
        case .some(let requestedValue):
            value = requestedValue
        case .none:
            value = defaultValue
        }
        let applied = min(max(value, range.lowerBound), range.upperBound)
        if let requested, requested != applied {
            caps.append(RecordedInputCap(
                name: name,
                requested: .int(requested),
                applied: .int(applied),
                minimum: .int(range.lowerBound),
                maximum: .int(range.upperBound),
                reason: reason
            ))
        }
        return applied
    }

    private static func clampDouble(
        name: String,
        requested: Double?,
        defaultValue: Double,
        minimum: Double,
        maximum: Double?,
        reason: String,
        caps: inout [RecordedInputCap]
    ) -> Double {
        let value: Double
        switch requested {
        case .some(let requestedValue):
            value = requestedValue
        case .none:
            value = defaultValue
        }
        var applied = max(value, minimum)
        if let maximum {
            applied = min(applied, maximum)
        }
        if let requested, requested != applied {
            caps.append(RecordedInputCap(
                name: name,
                requested: .double(requested),
                applied: .double(applied),
                minimum: .double(minimum),
                maximum: maximum.map { .double($0) },
                reason: reason
            ))
        }
        return applied
    }

    private static func makeRecordingSetup(config: RecordingConfig, screen: ScreenInfo) -> RecordingSetup {
        var caps: [RecordedInputCap] = []

        let fps = clampInt(
            name: "fps",
            requested: config.fps,
            defaultValue: 8,
            range: 1...15,
            reason: "recording fps is capped to the encoder-supported range",
            caps: &caps
        )
        let timing = resolvedStakeoutTiming(for: config)
        let inactivityTimeout = timing.inactivityTimeout
        let maxDuration = timing.maxDuration
        if let requested = config.inactivityTimeout,
           let applied = inactivityTimeout,
           requested != applied {
            caps.append(RecordedInputCap(
                name: "inactivityTimeout",
                requested: .double(requested),
                applied: .double(applied),
                minimum: .double(1.0),
                reason: "recording inactivity timeout must be at least 1 second"
            ))
        }
        if let requested = config.maxDuration, requested != maxDuration {
            caps.append(RecordedInputCap(
                name: "maxDuration",
                requested: .double(requested),
                applied: .double(maxDuration),
                minimum: .double(1.0),
                reason: "recording max duration must be at least 1 second"
            ))
        }

        let nativeWidth = screen.bounds.width * screen.scale
        let nativeHeight = screen.bounds.height * screen.scale
        let effectiveScale: CGFloat
        if let requestedScale = config.scale {
            effectiveScale = CGFloat(clampDouble(
                name: "scale",
                requested: requestedScale,
                defaultValue: Double(1.0 / screen.scale),
                minimum: 0.25,
                maximum: 1.0,
                reason: "recording scale is capped to the supported output range",
                caps: &caps
            ))
        } else {
            effectiveScale = 1.0 / screen.scale
        }
        let width = Int(nativeWidth * effectiveScale)
        let height = Int(nativeHeight * effectiveScale)
        let evenWidth = width % 2 == 0 ? width : width + 1
        let evenHeight = height % 2 == 0 ? height : height + 1
        if evenWidth != width {
            caps.append(RecordedInputCap(
                name: "width",
                requested: .int(width),
                applied: .int(evenWidth),
                reason: "H.264 output dimensions must be even"
            ))
        }
        if evenHeight != height {
            caps.append(RecordedInputCap(
                name: "height",
                requested: .int(height),
                applied: .int(evenHeight),
                reason: "H.264 output dimensions must be even"
            ))
        }

        return RecordingSetup(
            caps: caps,
            fps: fps,
            maxDuration: maxDuration,
            inactivityTimeout: inactivityTimeout,
            effectiveScale: effectiveScale,
            screenBounds: CGRect(x: 0, y: 0, width: evenWidth, height: evenHeight),
            evenWidth: evenWidth,
            evenHeight: evenHeight
        )
    }

    // MARK: - Init

    init(captureFrame: @escaping @MainActor @Sendable () async -> UIImage?) {
        self.captureFrame = captureFrame
    }

    func setOnRecordingComplete(_ handler: (@MainActor @Sendable (Result<RecordingPayload, Error>) -> Void)?) {
        self.onRecordingComplete = handler
    }

    // MARK: - Recording Lifecycle

    func startRecording(config: RecordingConfig, screen: ScreenInfo) throws {
        try lifecycle.requireIdle()

        let setup = Self.makeRecordingSetup(config: config, screen: screen)

        // Set up temp file
        let tempDir = NSTemporaryDirectory()
        let fileName = "stakeout-\(UUID().uuidString).mp4"
        let url = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)

        // Configure AVAssetWriter
        let writer = try AVAssetWriter(url: url, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: setup.evenWidth,
            AVVideoHeightKey: setup.evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: setup.evenWidth * setup.evenHeight * 2, // ~2 bits/pixel
                AVVideoMaxKeyFrameIntervalKey: setup.fps * 2, // Keyframe every 2 seconds
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: setup.evenWidth,
            kCVPixelBufferHeightKey as String: setup.evenHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw Self.writerSetupFailure(from: writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let recordingID = UUID()
        let now = Date()
        let captureTask = makeCaptureTimer(sessionID: recordingID, fps: setup.fps)
        let activity = makeActivityLifecycle(
            sessionID: recordingID,
            inactivityTimeout: setup.inactivityTimeout,
            startedAt: now
        )
        let session = ActiveRecording(
            id: recordingID,
            writer: ActiveWriterResources(
                assetWriter: writer,
                videoInput: input,
                pixelBufferAdaptor: adaptor
            ),
            output: RecordingOutput(screenBounds: setup.screenBounds, fps: setup.fps),
            timing: RecordingTiming(maxDuration: setup.maxDuration),
            evidence: RecordingEvidenceState(
                caps: setup.caps
            ),
            startedAt: now,
            capture: CaptureLifecycle(task: captureTask, frameCount: 0),
            activity: activity,
            interactions: ActiveInteractionLog()
        )

        try lifecycle.start(session)

        logger.info(
            "Recording started: \(setup.evenWidth)x\(setup.evenHeight) @ \(setup.fps)fps, effectiveScale=\(setup.effectiveScale)"
        )

        // Capture and inactivity tasks were created with this recording ID before
        // the state transition. Their first actor hop verifies this active session.
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) async {
        guard let finalizingSession = lifecycle.beginFinalizing() else { return }
        logger.info("Stopping recording: reason=\(reason.rawValue), frames=\(finalizingSession.frameCount)")

        await finalizeRecording(session: finalizingSession, reason: reason)
    }

    /// Call this whenever client activity occurs (commands received, etc.)
    func noteActivity() {
        _ = lifecycle.noteTrackedActivity(at: Date())
    }

    /// Call this whenever a screen change is detected (hierarchy hash change)
    func noteScreenChange() {
        _ = lifecycle.noteTrackedActivity(at: Date())
    }

    /// Capture an extra frame outside the regular timer cadence.
    /// Used to ensure actions are represented in the recording.
    func captureActionFrame() async {
        guard lifecycle.isRecording else { return }
        await captureAndAppendFrame()
    }

    /// Append an interaction event to the recording log.
    /// Silently drops events beyond `maxInteractionCount` to prevent unbounded growth.
    func recordInteraction(event: InteractionEvent) {
        if lifecycle.recordInteraction(event: event, limit: Self.maxInteractionCount) == true {
            logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
        }
    }

    /// Atomically record an interaction if the stakeout is currently in the
    /// `.recording` phase. Combines the phase check, elapsed-time read, and
    /// log append into a single actor-isolated step so callers can't observe
    /// a half-transitioned state between the three (the pattern that the
    /// cross-cutting audit's Finding 3 flagged as a TOCTOU window).
    ///
    /// No-ops gracefully when the stakeout is `.idle` or `.finalizing`.
    func recordInteractionIfRecording(command: ClientMessage, result: ActionResult) {
        if lifecycle.recordInteractionIfRecording(
            command: command,
            result: result,
            limit: Self.maxInteractionCount
        ) == true {
            logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
        }
    }

    // MARK: - Frame Capture

    private func makeCaptureTimer(sessionID: UUID, fps: Int) -> Task<Void, Never> {
        let interval = Duration.seconds(1) / fps
        return Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard await self.currentSessionID == sessionID else { return }
                await self.captureAndAppendFrame()
                guard await Task.cancellableSleep(for: interval) else { break }
            }
        }
    }

    private func captureAndAppendFrame() async {
        guard let startingSession = lifecycle.frameCaptureSession() else { return }
        let sessionID = startingSession.id

        // Hop to MainActor only for the UI snapshot itself.
        guard let image = await captureFrame() else { return }

        // After the await, the phase may have changed — re-check that we're
        // still in the same recording session before appending.
        guard let session = lifecycle.activeRecording(matching: sessionID) else { return }

        // Check file size guard (7MB raw = ~9.3MB base64, under 10MB buffer limit)
        // If we can't read the file size, skip the check and continue recording
        let fileSize: Int?
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: session.writer.assetWriter.outputURL.path)
            fileSize = attributes[.size] as? Int
        } catch {
            logger.warning("Could not read recording file size, skipping size check: \(error)")
            fileSize = nil
        }
        if let fileSize, fileSize > Self.maxVideoDataBytes {
            logger.warning("File size limit reached: \(fileSize) bytes")
            await stopRecording(reason: .fileSizeLimit)
            return
        }

        // Check max duration
        if Date().timeIntervalSince(session.startedAt) >= session.timing.maxDuration {
            logger.warning("Max duration reached")
            await stopRecording(reason: .maxDuration)
            return
        }

        // Create pixel buffer from UIImage
        guard let pixelBuffer = createPixelBuffer(from: image, session: session) else { return }

        let frameTime = CMTime(value: Int64(session.capture.frameCount), timescale: Int32(session.output.fps))
        if session.writer.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) {
            _ = lifecycle.noteFrameAppended(for: sessionID)
        }
    }

    private func createPixelBuffer(from image: UIImage, session: ActiveRecording) -> CVPixelBuffer? {
        guard let pool = session.writer.pixelBufferAdaptor.pixelBufferPool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(session.output.screenBounds.width),
            height: Int(session.output.screenBounds.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage else { return nil }

        // Draw the image scaled into the pixel buffer.
        // Fingerprint indicators are rendered by TheFingerprints (on-screen UIView overlay)
        // and captured naturally via drawHierarchy — no CGContext compositing needed.
        context.draw(cgImage, in: session.output.screenBounds)

        return buffer
    }

    // MARK: - Inactivity Detection
    //
    // Inactivity is tracked only when explicitly configured, updated by:
    //   - `noteActivity()` — called on each incoming client command
    //   - `noteScreenChange()` — called by TheGetaway after a settled hierarchy change
    //
    // Note: screen hashing operates on the accessibility hierarchy, not pixels.
    // Subtle pixel-only animations (e.g. spinner rotation) do NOT count as activity,
    // so they won't prevent inactivity timeout. This is intentional — we only extend
    // recording when meaningful UI content changes.

    private func makeActivityLifecycle(
        sessionID: UUID,
        inactivityTimeout: TimeInterval?,
        startedAt: Date
    ) -> ActivityLifecycle {
        guard let inactivityTimeout else { return .notTracked }
        let monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard await Task.cancellableSleep(for: .seconds(1)) else { break } // Check every second
                guard let self else { return }
                guard let deadline = await self.inactivityDeadline(sessionID: sessionID) else {
                    return
                }
                if deadline.elapsed >= deadline.timeout {
                    logger.info("Inactivity timeout: \(deadline.elapsed)s since last activity")
                    await self.stopRecording(reason: .inactivity)
                    return
                }
            }
        }
        return .tracking(MonitoredActivity(
            timeout: inactivityTimeout,
            lastActivityAt: startedAt,
            task: monitorTask
        ))
    }

    private func inactivityDeadline(sessionID: UUID) -> (elapsed: TimeInterval, timeout: TimeInterval)? {
        lifecycle.inactivityDeadline(sessionID: sessionID)
    }

    // MARK: - Finalization

    private func finalizeRecording(session: FinalizingRecording, reason: RecordingPayload.StopReason) async {
        let writer = session.assetWriter

        // `finishWriting` runs on AVFoundation's internal queue. We bridge
        // back into the actor with `Task { await self.handleFinalize(...) }`,
        // replacing the previous `Task { @MainActor in ... }` bridge flagged
        // by the concurrency audit. `AVAssetWriter` is non-Sendable so it
        // cannot be captured into the `@Sendable` completion closure of
        // `finishWriting`; instead `handleFinalize` re-reads the finalizing
        // session from `StakeoutLifecycle`. The `.finalizing` phase is exclusive:
        // `startRecording` only accepts `.idle`, so no second finalizing session
        // can replace the current one while this writer is finishing.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { [weak self] in
                Task { [weak self] in
                    await self?.handleFinalize(reason: reason)
                    continuation.resume()
                }
            }
        }
    }

    private func handleFinalize(reason: RecordingPayload.StopReason) async {
        guard let session = lifecycle.finalizingSession else { return }

        defer { cleanup(outputURL: session.assetWriter.outputURL) }

        let writerStatus = session.assetWriter.status
        let writerError = session.assetWriter.error
        if writerStatus == .failed {
            await deliverError(Self.finalizationFailure(from: writerError))
            return
        }

        let videoData: Data
        do {
            videoData = try Data(contentsOf: session.assetWriter.outputURL)
        } catch {
            await deliverError(.finalizationFailed("Could not read output file: \(error.localizedDescription)"))
            return
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(session.startedAt)

        let payload = RecordingPayload(
            videoData: videoData.base64EncodedString(),
            width: Int(session.output.screenBounds.width),
            height: Int(session.output.screenBounds.height),
            duration: duration,
            frameCount: session.frameCount,
            fps: session.output.fps,
            startTime: session.startedAt,
            endTime: endTime,
            stopReason: reason,
            interactionLog: session.interactions.events.isEmpty ? nil : session.interactions.events,
            evidence: RecordingPayloadEvidence(
                caps: session.evidence.caps,
                interactionLogLimit: Self.maxInteractionCount,
                droppedInteractionCount: session.interactions.droppedCount == 0 ? nil : session.interactions.droppedCount,
                fileSizeLimitBytes: Self.maxVideoDataBytes
            )
        )

        logger.info("Recording complete: \(session.frameCount) frames, \(String(format: "%.1f", duration))s, \(videoData.count) bytes")
        await deliverSuccess(payload)
    }

    /// Identity of the currently-active recording, or nil if not recording.
    /// Used by capture/inactivity Tasks to detect a session boundary —
    /// if the current session ID no longer matches the one captured at
    /// task spawn, the task bails rather than acting on a fresh session.
    private var currentSessionID: UUID? {
        lifecycle.currentRecordingID
    }

    private static func writerSetupFailure(from error: Error?) -> TheStakeoutError {
        if let error {
            return .writerSetupFailed(error.localizedDescription)
        }
        return .writerSetupFailedWithoutUnderlyingError
    }

    private static func finalizationFailure(from error: Error?) -> TheStakeoutError {
        if let error {
            return .finalizationFailed(error.localizedDescription)
        }
        return .finalizationFailedWithoutUnderlyingError
    }

    private func deliverError(_ error: TheStakeoutError) async {
        logger.error("Recording error: \(error)")
        guard let handler = onRecordingComplete else { return }
        await MainActor.run { handler(.failure(error)) }
    }

    private func deliverSuccess(_ payload: RecordingPayload) async {
        guard let handler = onRecordingComplete else { return }
        await MainActor.run { handler(.success(payload)) }
    }

    private func cleanup(outputURL: URL) {
        lifecycle.markIdle()

        // Clean up temp file
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch {
            logger.warning("Failed to clean up recording temp file at \(outputURL.path): \(error)")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

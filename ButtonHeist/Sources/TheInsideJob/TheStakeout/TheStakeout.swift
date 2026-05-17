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
/// other piece of state (the `stakeoutPhase` state machine, AVAssetWriter, sample
/// buffers) lives inside the actor — AVAssetWriter and its pixel-buffer adaptor are
/// thread-safe and do not require MainActor isolation. The AVAssetWriter
/// `finishWriting` completion handler bridges back into the actor with
/// `Task { await self.handleFinalize(...) }` rather than the previous
/// `Task { @MainActor in ... }` shape called out in the concurrency audit.
actor TheStakeout {

    // MARK: - Nested Types

    enum StakeoutPhase {
        case idle
        case recording(RecordingSession)
        case finalizing(FinalizingSession)
    }

    struct RecordingSession {
        /// Identity token for this recording. Captured by the capture timer
        /// and inactivity monitor so a Task scheduled for one recording can
        /// detect if it's woken up after a new recording has already started.
        let id: UUID
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
        let outputURL: URL
        let screenBounds: CGRect
        let fps: Int
        let maxDuration: TimeInterval
        let inactivityTimeout: TimeInterval
        let startTime: Date
        let requestedConfig: RecordingConfigurationEvidence
        let appliedConfig: RecordingConfigurationEvidence
        let caps: [RecordedInputCap]
        var captureTimer: Task<Void, Never>
        var inactivityCheckTask: Task<Void, Never>
        var frameCount: Int
        var lastFrameTime: CMTime
        var lastActivityTime: Date
        var interactionLog: [InteractionEvent]
        var droppedInteractionCount: Int
        var didLogCapWarning: Bool
    }

    struct FinalizingSession {
        let id: UUID
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let outputURL: URL
        let startTime: Date
        let frameCount: Int
        let fps: Int
        let screenBounds: CGRect
        let interactionLog: [InteractionEvent]
        let requestedConfig: RecordingConfigurationEvidence
        let appliedConfig: RecordingConfigurationEvidence
        let caps: [RecordedInputCap]
        let droppedInteractionCount: Int
    }

    /// Screen metrics captured on MainActor and passed into the actor at startRecording.
    /// Avoids reaching back through MainActor for layout values that don't change for
    /// the duration of a recording.
    struct ScreenInfo: Sendable {
        let bounds: CGRect
        let scale: CGFloat
    }

    private struct RecordingSetup {
        let requestedConfig: RecordingConfigurationEvidence
        let appliedConfig: RecordingConfigurationEvidence
        let caps: [RecordedInputCap]
        let fps: Int
        let maxDuration: TimeInterval
        let inactivityTimeout: TimeInterval
        let effectiveScale: CGFloat
        let screenBounds: CGRect
        let evenWidth: Int
        let evenHeight: Int
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

    // MARK: - Properties

    /// The single MainActor-bound thing — UI capture. Set at init, immutable thereafter.
    private let captureFrame: @MainActor @Sendable () async -> UIImage?

    /// Completion handler — called when recording finishes for any reason.
    /// Writes are actor-isolated; reads happen on MainActor inside the closure.
    /// Use ``setOnRecordingComplete(_:)`` to assign — the property is read-only externally.
    private(set) var onRecordingComplete: (@MainActor @Sendable (Result<RecordingPayload, Error>) -> Void)?

    private var stakeoutPhase: StakeoutPhase = .idle

    /// Maximum number of interaction events to record. Beyond this, events are silently dropped
    /// and the log is capped to prevent unbounded memory growth in long recordings.
    private static let maxInteractionCount = 500
    /// Raw MP4 byte cap. Base64 expansion keeps this under the 10MB wire buffer.
    private static let maxVideoDataBytes = 7_000_000

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

    /// Elapsed time since recording started, in seconds.
    var recordingElapsed: Double {
        guard case .recording(let session) = stakeoutPhase else { return 0 }
        return Date().timeIntervalSince(session.startTime)
    }

    private static func clampInt(
        name: String,
        requested: Int?,
        defaultValue: Int,
        range: ClosedRange<Int>,
        reason: String,
        caps: inout [RecordedInputCap]
    ) -> Int {
        let value = requested ?? defaultValue
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
        let value = requested ?? defaultValue
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
        let requestedConfig = RecordingConfigurationEvidence(config)
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
        if let requested = config.inactivityTimeout, requested != inactivityTimeout {
            caps.append(RecordedInputCap(
                name: "inactivityTimeout",
                requested: .double(requested),
                applied: .double(inactivityTimeout),
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
        let effectiveScale: CGFloat = if let requestedScale = config.scale {
            CGFloat(clampDouble(
                name: "scale",
                requested: requestedScale,
                defaultValue: Double(1.0 / screen.scale),
                minimum: 0.25,
                maximum: 1.0,
                reason: "recording scale is capped to the supported output range",
                caps: &caps
            ))
        } else {
            1.0 / screen.scale
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

        let appliedConfig = RecordingConfigurationEvidence(
            fps: fps,
            scale: Double(effectiveScale),
            inactivityTimeout: inactivityTimeout,
            maxDuration: maxDuration
        )
        return RecordingSetup(
            requestedConfig: requestedConfig,
            appliedConfig: appliedConfig,
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
        guard case .idle = stakeoutPhase else {
            throw TheStakeoutError.alreadyRecording
        }

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
            throw TheStakeoutError.writerSetupFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        writer.startSession(atSourceTime: .zero)

        let now = Date()
        let session = RecordingSession(
            id: UUID(),
            assetWriter: writer,
            videoInput: input,
            pixelBufferAdaptor: adaptor,
            outputURL: url,
            screenBounds: setup.screenBounds,
            fps: setup.fps,
            maxDuration: setup.maxDuration,
            inactivityTimeout: setup.inactivityTimeout,
            startTime: now,
            requestedConfig: setup.requestedConfig,
            appliedConfig: setup.appliedConfig,
            caps: setup.caps,
            captureTimer: Task { },
            inactivityCheckTask: Task { },
            frameCount: 0,
            lastFrameTime: .zero,
            lastActivityTime: now,
            interactionLog: [],
            droppedInteractionCount: 0,
            didLogCapWarning: false
        )

        stakeoutPhase = .recording(session)

        logger.info(
            "Recording started: \(setup.evenWidth)x\(setup.evenHeight) @ \(setup.fps)fps, effectiveScale=\(setup.effectiveScale)"
        )

        // Start frame capture timer and inactivity monitor — these mutate the session
        // via stakeoutPhase, so they must be started after the state transition.
        startCaptureTimer()
        startInactivityMonitor()
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) async {
        guard case .recording(let session) = stakeoutPhase else { return }

        logger.info("Stopping recording: reason=\(reason.rawValue), frames=\(session.frameCount)")

        session.captureTimer.cancel()
        session.inactivityCheckTask.cancel()

        let finalizingSession = FinalizingSession(
            id: session.id,
            assetWriter: session.assetWriter,
            videoInput: session.videoInput,
            outputURL: session.outputURL,
            startTime: session.startTime,
            frameCount: session.frameCount,
            fps: session.fps,
            screenBounds: session.screenBounds,
            interactionLog: session.interactionLog,
            requestedConfig: session.requestedConfig,
            appliedConfig: session.appliedConfig,
            caps: session.caps,
            droppedInteractionCount: session.droppedInteractionCount
        )
        stakeoutPhase = .finalizing(finalizingSession)

        await finalizeRecording(session: finalizingSession, reason: reason)
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
    func captureActionFrame() async {
        guard case .recording = stakeoutPhase else { return }
        await captureAndAppendFrame()
    }

    /// Append an interaction event to the recording log.
    /// Silently drops events beyond `maxInteractionCount` to prevent unbounded growth.
    func recordInteraction(event: InteractionEvent) {
        guard case .recording(var session) = stakeoutPhase else { return }
        guard session.interactionLog.count < Self.maxInteractionCount else {
            session.droppedInteractionCount += 1
            if !session.didLogCapWarning {
                session.didLogCapWarning = true
                logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
            }
            stakeoutPhase = .recording(session)
            return
        }
        session.interactionLog.append(event)
        stakeoutPhase = .recording(session)
    }

    /// Atomically record an interaction if the stakeout is currently in the
    /// `.recording` phase. Combines the phase check, elapsed-time read, and
    /// log append into a single actor-isolated step so callers can't observe
    /// a half-transitioned state between the three (the pattern that the
    /// cross-cutting audit's Finding 3 flagged as a TOCTOU window).
    ///
    /// No-ops gracefully when the stakeout is `.idle` or `.finalizing`.
    func recordInteractionIfRecording(command: ClientMessage, result: ActionResult) {
        guard case .recording(let session) = stakeoutPhase else { return }
        let elapsed = Date().timeIntervalSince(session.startTime)
        let event = InteractionEvent(timestamp: elapsed, command: command, result: result)
        recordInteraction(event: event)
    }

    // MARK: - Frame Capture

    private func startCaptureTimer() {
        guard case .recording(var session) = stakeoutPhase else { return }
        let interval = Duration.seconds(1) / session.fps
        let sessionID = session.id
        session.captureTimer = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard await self.currentSessionID == sessionID else { return }
                await self.captureAndAppendFrame()
                guard await Task.cancellableSleep(for: interval) else { break }
            }
        }
        stakeoutPhase = .recording(session)
    }

    private func captureAndAppendFrame() async {
        guard case .recording(var session) = stakeoutPhase,
              session.videoInput.isReadyForMoreMediaData else {
            return
        }

        // Hop to MainActor only for the UI snapshot itself.
        guard let image = await captureFrame() else { return }

        // After the await, the phase may have changed — re-check that we're
        // still in the same recording session before appending.
        guard case .recording(var current) = stakeoutPhase, current.id == session.id else {
            return
        }
        session = current

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
        if let fileSize, fileSize > Self.maxVideoDataBytes {
            logger.warning("File size limit reached: \(fileSize) bytes")
            await stopRecording(reason: .fileSizeLimit)
            return
        }

        // Check max duration
        if Date().timeIntervalSince(session.startTime) >= session.maxDuration {
            logger.warning("Max duration reached")
            await stopRecording(reason: .maxDuration)
            return
        }

        // Create pixel buffer from UIImage
        guard let pixelBuffer = createPixelBuffer(from: image, session: session) else { return }

        let frameTime = CMTime(value: Int64(session.frameCount), timescale: Int32(session.fps))
        if session.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) {
            current.frameCount = session.frameCount + 1
            current.lastFrameTime = frameTime
            stakeoutPhase = .recording(current)
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
    //   - `noteScreenChange()` — called when TheStash detects a hierarchy hash change
    //
    // Note: screen hashing operates on the accessibility hierarchy, not pixels.
    // Subtle pixel-only animations (e.g. spinner rotation) do NOT count as activity,
    // so they won't prevent inactivity timeout. This is intentional — we only extend
    // recording when meaningful UI content changes.

    private func startInactivityMonitor() {
        guard case .recording(var session) = stakeoutPhase else { return }
        let sessionID = session.id
        session.inactivityCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard await Task.cancellableSleep(for: .seconds(1)) else { break } // Check every second
                guard let self else { return }
                guard let elapsed = await self.elapsedSinceLastActivity(sessionID: sessionID) else {
                    return
                }
                guard let timeout = await self.inactivityTimeoutFor(sessionID: sessionID) else {
                    return
                }
                if elapsed >= timeout {
                    logger.info("Inactivity timeout: \(elapsed)s since last activity")
                    await self.stopRecording(reason: .inactivity)
                    return
                }
            }
        }
        stakeoutPhase = .recording(session)
    }

    private func elapsedSinceLastActivity(sessionID: UUID) -> Double? {
        guard case .recording(let session) = stakeoutPhase, session.id == sessionID else {
            return nil
        }
        return Date().timeIntervalSince(session.lastActivityTime)
    }

    private func inactivityTimeoutFor(sessionID: UUID) -> TimeInterval? {
        guard case .recording(let session) = stakeoutPhase, session.id == sessionID else {
            return nil
        }
        return session.inactivityTimeout
    }

    // MARK: - Finalization

    private func finalizeRecording(session: FinalizingSession, reason: RecordingPayload.StopReason) async {
        let writer = session.assetWriter
        let sessionID = session.id

        session.videoInput.markAsFinished()

        // `finishWriting` runs on AVFoundation's internal queue. We bridge
        // back into the actor with `Task { await self.handleFinalize(...) }`,
        // replacing the previous `Task { @MainActor in ... }` bridge flagged
        // by the concurrency audit. `AVAssetWriter` is non-Sendable so it
        // cannot be captured into the `@Sendable` completion closure of
        // `finishWriting`; instead `handleFinalize` re-reads the finalizing
        // session from `stakeoutPhase` after verifying the session ID, which
        // gives us back the writer plus all the per-recording metadata in one
        // step.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { [weak self] in
                Task { [weak self] in
                    await self?.handleFinalize(sessionID: sessionID, reason: reason)
                    continuation.resume()
                }
            }
        }
    }

    private func handleFinalize(sessionID: UUID, reason: RecordingPayload.StopReason) async {
        // Verify the finalizing session is still ours — if a new recording
        // started while we were waiting on `finishWriting`, bail out rather
        // than acting on a foreign writer. (In practice this can't happen
        // because `startRecording` requires `.idle` and we hold `.finalizing`
        // until cleanup, but the check makes the invariant explicit.)
        guard case .finalizing(let session) = stakeoutPhase, session.id == sessionID else {
            await deliverError(.finalizationFailed("Finalization for stale session"))
            return
        }

        defer { cleanup(outputURL: session.outputURL) }

        let writerStatus = session.assetWriter.status
        let writerError = session.assetWriter.error
        if writerStatus == .failed {
            await deliverError(.finalizationFailed(writerError?.localizedDescription ?? "Unknown"))
            return
        }

        let videoData: Data
        do {
            videoData = try Data(contentsOf: session.outputURL)
        } catch {
            await deliverError(.finalizationFailed("Could not read output file: \(error.localizedDescription)"))
            return
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(session.startTime)

        let payload = RecordingPayload(
            videoData: videoData.base64EncodedString(),
            width: Int(session.screenBounds.width),
            height: Int(session.screenBounds.height),
            duration: duration,
            frameCount: session.frameCount,
            fps: session.fps,
            startTime: session.startTime,
            endTime: endTime,
            stopReason: reason,
            interactionLog: session.interactionLog.isEmpty ? nil : session.interactionLog,
            evidence: RecordingPayloadEvidence(
                requestedConfig: session.requestedConfig,
                appliedConfig: session.appliedConfig,
                caps: session.caps,
                interactionLogLimit: Self.maxInteractionCount,
                droppedInteractionCount: session.droppedInteractionCount == 0 ? nil : session.droppedInteractionCount,
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
        if case .recording(let session) = stakeoutPhase { return session.id }
        return nil
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
        stakeoutPhase = .idle

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

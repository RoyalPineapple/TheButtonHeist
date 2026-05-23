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
        case recording(ActiveRecording)
        case finalizing(FinalizingRecording)
    }

    enum ActivityTrackingSnapshot: Equatable, Sendable {
        case notTracked
        case tracking(timeout: TimeInterval)
    }

    enum LifecycleSnapshot: Equatable, Sendable {
        case idle
        case recording(
            activity: ActivityTrackingSnapshot,
            frameCount: Int,
            interactionCount: Int,
            droppedInteractionCount: Int
        )
        case finalizing(
            frameCount: Int,
            interactionCount: Int,
            droppedInteractionCount: Int
        )
    }

    struct ActiveRecording {
        /// Identity token for this recording. Captured by the capture timer
        /// and inactivity monitor so a Task scheduled for one recording can
        /// detect if it's woken up after a new recording has already started.
        let id: UUID
        let writer: ActiveWriterResources
        let output: RecordingOutput
        let timing: RecordingTiming
        let evidence: RecordingEvidenceState
        let startedAt: Date
        var capture: CaptureLifecycle
        var activity: ActivityLifecycle
        var interactions: ActiveInteractionLog

        func cancelRuntimeTasks() {
            capture.task.cancel()
            activity.cancel()
        }

        func finalizing() -> FinalizingRecording {
            FinalizingRecording(
                id: id,
                writer: writer.file,
                output: output,
                startedAt: startedAt,
                frameCount: capture.frameCount,
                interactions: interactions.finalized(),
                evidence: evidence
            )
        }
    }

    struct FinalizingRecording {
        let id: UUID
        let writer: RecordingFile
        let output: RecordingOutput
        let startedAt: Date
        let frameCount: Int
        let interactions: FinalizedInteractionLog
        let evidence: RecordingEvidenceState
    }

    struct RecordingFile {
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
        let outputURL: URL
    }

    struct ActiveWriterResources {
        let file: RecordingFile
        let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    }

    struct RecordingOutput {
        let screenBounds: CGRect
        let fps: Int
    }

    struct RecordingTiming {
        let maxDuration: TimeInterval
    }

    struct RecordingEvidenceState {
        let caps: [RecordedInputCap]
    }

    struct CaptureLifecycle {
        let task: Task<Void, Never>
        var frameCount: Int
    }

    enum ActivityLifecycle {
        case notTracked
        case tracking(MonitoredActivity)

        var snapshot: ActivityTrackingSnapshot {
            switch self {
            case .notTracked:
                return .notTracked
            case .tracking(let activity):
                return .tracking(timeout: activity.timeout)
            }
        }

        mutating func noteActivity(at date: Date) -> Bool {
            guard case .tracking(var activity) = self else { return false }
            activity.lastActivityAt = date
            self = .tracking(activity)
            return true
        }

        func inactivityDeadline(now: Date) -> (elapsed: TimeInterval, timeout: TimeInterval)? {
            guard case .tracking(let activity) = self else { return nil }
            return (now.timeIntervalSince(activity.lastActivityAt), activity.timeout)
        }

        func cancel() {
            guard case .tracking(let activity) = self else { return }
            activity.task.cancel()
        }
    }

    struct MonitoredActivity {
        let timeout: TimeInterval
        var lastActivityAt: Date
        let task: Task<Void, Never>
    }

    struct ActiveInteractionLog {
        var events: [InteractionEvent] = []
        var droppedCount = 0

        mutating func append(_ event: InteractionEvent, limit: Int) -> Bool {
            guard events.count < limit else {
                let shouldLogCapWarning = droppedCount == 0
                droppedCount += 1
                return shouldLogCapWarning
            }
            events.append(event)
            return false
        }

        func finalized() -> FinalizedInteractionLog {
            FinalizedInteractionLog(events: events, droppedCount: droppedCount)
        }
    }

    struct FinalizedInteractionLog {
        let events: [InteractionEvent]
        let droppedCount: Int
    }

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
    /// Use ``setOnRecordingComplete(_:)`` to assign.
    private var onRecordingComplete: (@MainActor @Sendable (Result<RecordingPayload, Error>) -> Void)?

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
        case .recording(let session): return session.interactions.events
        case .finalizing(let session): return session.interactions.events
        }
    }

    /// Elapsed time since recording started, in seconds.
    var recordingElapsed: Double {
        guard case .recording(let session) = stakeoutPhase else { return 0 }
        return Date().timeIntervalSince(session.startedAt)
    }

    var lifecycleSnapshot: LifecycleSnapshot {
        switch stakeoutPhase {
        case .idle:
            return .idle
        case .recording(let session):
            return .recording(
                activity: session.activity.snapshot,
                frameCount: session.capture.frameCount,
                interactionCount: session.interactions.events.count,
                droppedInteractionCount: session.interactions.droppedCount
            )
        case .finalizing(let session):
            return .finalizing(
                frameCount: session.frameCount,
                interactionCount: session.interactions.events.count,
                droppedInteractionCount: session.interactions.droppedCount
            )
        }
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

        let recordingID = UUID()
        let now = Date()
        let captureTask = makeCaptureTimer(sessionID: recordingID, fps: setup.fps)
        let activity = makeActivityLifecycle(
            sessionID: recordingID,
            inactivityTimeout: setup.inactivityTimeout,
            startedAt: now
        )
        let file = RecordingFile(assetWriter: writer, videoInput: input, outputURL: url)
        let session = ActiveRecording(
            id: recordingID,
            writer: ActiveWriterResources(file: file, pixelBufferAdaptor: adaptor),
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

        stakeoutPhase = .recording(session)

        logger.info(
            "Recording started: \(setup.evenWidth)x\(setup.evenHeight) @ \(setup.fps)fps, effectiveScale=\(setup.effectiveScale)"
        )

        // Capture and inactivity tasks were created with this recording ID before
        // the state transition. Their first actor hop verifies this active session.
    }

    func stopRecording(reason: RecordingPayload.StopReason = .manual) async {
        guard case .recording(let session) = stakeoutPhase else { return }

        logger.info("Stopping recording: reason=\(reason.rawValue), frames=\(session.capture.frameCount)")

        session.cancelRuntimeTasks()

        let finalizingSession = session.finalizing()
        stakeoutPhase = .finalizing(finalizingSession)

        await finalizeRecording(session: finalizingSession, reason: reason)
    }

    /// Call this whenever client activity occurs (commands received, etc.)
    func noteActivity() {
        guard case .recording(var session) = stakeoutPhase else { return }
        guard session.activity.noteActivity(at: Date()) else { return }
        stakeoutPhase = .recording(session)
    }

    /// Call this whenever a screen change is detected (hierarchy hash change)
    func noteScreenChange() {
        guard case .recording(var session) = stakeoutPhase else { return }
        guard session.activity.noteActivity(at: Date()) else { return }
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
        let shouldLogCapWarning = session.interactions.append(event, limit: Self.maxInteractionCount)
        if shouldLogCapWarning {
            logger.warning("Interaction log capped at \(Self.maxInteractionCount) events; further events will be dropped")
        }
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
        let elapsed = Date().timeIntervalSince(session.startedAt)
        let event = InteractionEvent(timestamp: elapsed, command: command, result: result)
        recordInteraction(event: event)
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
        guard case .recording(let startingSession) = stakeoutPhase,
              startingSession.writer.file.videoInput.isReadyForMoreMediaData else {
            return
        }
        let sessionID = startingSession.id

        // Hop to MainActor only for the UI snapshot itself.
        guard let image = await captureFrame() else { return }

        // After the await, the phase may have changed — re-check that we're
        // still in the same recording session before appending.
        guard case .recording(var session) = stakeoutPhase, session.id == sessionID else {
            return
        }

        // Check file size guard (7MB raw = ~9.3MB base64, under 10MB buffer limit)
        // If we can't read the file size, skip the check and continue recording
        let fileSize: Int?
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: session.writer.file.outputURL.path)
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
            session.capture.frameCount += 1
            stakeoutPhase = .recording(session)
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
        guard case .recording(let session) = stakeoutPhase, session.id == sessionID else {
            return nil
        }
        return session.activity.inactivityDeadline(now: Date())
    }

    // MARK: - Finalization

    private func finalizeRecording(session: FinalizingRecording, reason: RecordingPayload.StopReason) async {
        let writer = session.writer.assetWriter
        let sessionID = session.id

        session.writer.videoInput.markAsFinished()

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
        guard case .finalizing(let session) = stakeoutPhase, session.id == sessionID else { return }

        defer { cleanup(outputURL: session.writer.outputURL) }

        let writerStatus = session.writer.assetWriter.status
        let writerError = session.writer.assetWriter.error
        if writerStatus == .failed {
            await deliverError(.finalizationFailed(writerError?.localizedDescription ?? "Unknown"))
            return
        }

        let videoData: Data
        do {
            videoData = try Data(contentsOf: session.writer.outputURL)
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

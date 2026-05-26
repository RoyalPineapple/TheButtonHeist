#if canImport(UIKit)
#if DEBUG
import AVFoundation
import UIKit

import TheScore

extension TheStakeout {
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
                assetWriter: writer.assetWriter,
                output: output,
                startedAt: startedAt,
                frameCount: capture.frameCount,
                interactions: interactions.finalized(),
                evidence: evidence
            )
        }
    }

    struct FinalizingRecording {
        let assetWriter: AVAssetWriter
        let output: RecordingOutput
        let startedAt: Date
        let frameCount: Int
        let interactions: FinalizedInteractionLog
        let evidence: RecordingEvidenceState
    }

    struct ActiveWriterResources {
        let assetWriter: AVAssetWriter
        let videoInput: AVAssetWriterInput
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
}

struct StakeoutLifecycle {
    private var phase: TheStakeout.StakeoutPhase = .idle

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var isFinalizing: Bool {
        if case .finalizing = phase { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    var interactionLog: [InteractionEvent] {
        switch phase {
        case .idle: return []
        case .recording(let session): return session.interactions.events
        case .finalizing(let session): return session.interactions.events
        }
    }

    func recordingElapsed(now: Date = Date()) -> Double {
        guard case .recording(let session) = phase else { return 0 }
        return now.timeIntervalSince(session.startedAt)
    }

    var snapshot: TheStakeout.LifecycleSnapshot {
        switch phase {
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

    var currentRecordingID: UUID? {
        guard case .recording(let session) = phase else { return nil }
        return session.id
    }

    var finalizingSession: TheStakeout.FinalizingRecording? {
        guard case .finalizing(let session) = phase else { return nil }
        return session
    }

    func requireIdle() throws {
        guard isIdle else {
            throw TheStakeout.TheStakeoutError.alreadyRecording
        }
    }

    mutating func start(_ session: TheStakeout.ActiveRecording) throws {
        try requireIdle()
        phase = .recording(session)
    }

    mutating func beginFinalizing() -> TheStakeout.FinalizingRecording? {
        guard case .recording(let session) = phase else { return nil }
        session.cancelRuntimeTasks()
        session.writer.videoInput.markAsFinished()
        let finalizingSession = session.finalizing()
        phase = .finalizing(finalizingSession)
        return finalizingSession
    }

    mutating func markIdle() {
        phase = .idle
    }

    mutating func noteTrackedActivity(at date: Date) -> Bool {
        guard case .recording(var session) = phase else { return false }
        guard session.activity.noteActivity(at: date) else { return false }
        phase = .recording(session)
        return true
    }

    mutating func recordInteraction(event: InteractionEvent, limit: Int) -> Bool? {
        guard case .recording(var session) = phase else { return nil }
        let shouldLogCapWarning = session.interactions.append(event, limit: limit)
        phase = .recording(session)
        return shouldLogCapWarning
    }

    mutating func recordInteractionIfRecording(
        command: ClientMessage,
        result: ActionResult,
        limit: Int,
        now: Date = Date()
    ) -> Bool? {
        guard case .recording(var session) = phase else { return nil }
        let elapsed = now.timeIntervalSince(session.startedAt)
        let event = InteractionEvent(timestamp: elapsed, command: command, result: result)
        let shouldLogCapWarning = session.interactions.append(event, limit: limit)
        phase = .recording(session)
        return shouldLogCapWarning
    }

    func frameCaptureSession() -> TheStakeout.ActiveRecording? {
        guard case .recording(let session) = phase,
              session.writer.videoInput.isReadyForMoreMediaData else {
            return nil
        }
        return session
    }

    func activeRecording(matching id: UUID) -> TheStakeout.ActiveRecording? {
        guard case .recording(let session) = phase, session.id == id else {
            return nil
        }
        return session
    }

    mutating func noteFrameAppended(for id: UUID) -> Bool {
        guard case .recording(var session) = phase, session.id == id else {
            return false
        }
        session.capture.frameCount += 1
        phase = .recording(session)
        return true
    }

    func inactivityDeadline(sessionID: UUID, now: Date = Date()) -> (elapsed: TimeInterval, timeout: TimeInterval)? {
        guard case .recording(let session) = phase, session.id == sessionID else {
            return nil
        }
        return session.activity.inactivityDeadline(now: now)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

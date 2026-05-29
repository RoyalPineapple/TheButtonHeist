#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

/// The getaway driver — runs comms between the wire and the crew.
///
/// TheGetaway owns message routing between the transport and crew members.
/// Transport wiring, encoding, broadcast, and status construction live in
/// focused extension files so this root stays a coordinator.
@MainActor
final class TheGetaway {

    // MARK: - Crew References (not owned)

    let muscle: TheMuscle
    let brains: TheBrains

    /// Identity info provided by TheInsideJob for ServerInfo responses.
    struct ServerIdentity {
        let sessionId: UUID
        let effectiveInstanceId: String
        var tlsActive: Bool
    }

    var identity: ServerIdentity
    let pongPayload: PongPayload

    // MARK: - State

    // `RecordingRouteState`, `RecordingPhase`, `RecordingOutcome`, and their handlers live in
    // TheGetaway+Recording.swift.
    private(set) var recordingRouteState: RecordingRouteState = .idle
    private(set) var backgroundChangeState = BackgroundChangeState()

    /// Current transport — set by `wireTransport`, cleared on teardown.
    weak var transport: ServerTransport?

    /// Single long-lived consumer Task for `transport.events`. Cancelled on
    /// `tearDown()`; the for-await loop also exits when the transport finishes
    /// its event continuation in `stop()`.
    var eventConsumerTask: Task<Void, Never>?

    /// Pending Tasks spawned to bridge MainActor-bound recording callbacks
    /// back into TheGetaway. There is at most one in-flight delivery per
    /// recording session, but storing the handle in a tracker keeps the
    /// lifecycle-tracking pattern uniform with the rest of TheGetaway.
    let pendingRecordingTasks = TaskTracker()

    var stakeout: TheStakeout? {
        recordingRouteState.activeStakeout
    }

    var recordingPhase: RecordingPhase {
        recordingRouteState.phase
    }

    var completedRecording: RecordingOutcome {
        guard case .completed(let completion) = recordingRouteState else { return .none }
        return completion.outcome
    }

    var pendingRecordingResponse: RecordingWaiter? {
        guard case .stopping(_, let waiter) = recordingRouteState else { return nil }
        return waiter
    }

    var recordingOriginatorClientId: Int? {
        recordingRouteState.ownerClientId
    }

    var recordingInvalidationReason: RecordingInvalidationReason? {
        switch recordingRouteState {
        case .invalidated(_, let reason), .invalidating(_, _, let reason):
            return reason
        case .idle, .starting, .recording, .stopping, .completed:
            return nil
        }
    }

    /// Test seam for routing tests that need to stage an otherwise internal
    /// recording lifecycle state without making the state store module-writable.
    func installRecordingRouteStateForTest(_ state: RecordingRouteState) {
        replaceRecordingRouteState(state)
    }

    /// Recording-route transitions are intentionally funneled through
    /// TheGetaway methods so no other component can assign the lifecycle store.
    func replaceRecordingRouteState(_ state: RecordingRouteState) {
        recordingRouteState = state
    }

    func noteBackgroundChange() {
        backgroundChangeState.noteChange()
    }

    func resetBackgroundChangeState() {
        backgroundChangeState.reset()
    }

    var hasPendingBackgroundChange: Bool {
        backgroundChangeState.hasPendingSettledChange
    }

    // MARK: - Init

    init(muscle: TheMuscle, brains: TheBrains, identity: ServerIdentity) {
        self.muscle = muscle
        self.brains = brains
        self.identity = identity
        self.pongPayload = Self.makePongPayload(identity: identity)
    }

    /// Insert a Task into `pendingRecordingTasks` and prune already-completed
    /// handles so the set does not grow across many recordings.
    func trackRecordingTask(_ task: Task<Void, Never>) {
        pendingRecordingTasks.record(task)
    }

    // MARK: - Message Dispatch

    func handleClientMessage(_ admitted: AdmittedClientMessage, respond: @escaping (Data) -> Void) async {
        let clientId = admitted.clientId
        let envelope = admitted.envelope
        let requestId = envelope.requestId
        let message = envelope.message

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        switch message {
        case .clientHello, .authenticate:
            insideJobLogger.fault("Protocol message reached app dispatch after admission")
            sendMessage(
                .error(ServerError(
                    kind: .validationError,
                    message: "Protocol messages are handled by admission before app dispatch."
                )),
                requestId: requestId,
                respond: respond
            )
        case .requestInterface(let query):
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(query: query, requestId: requestId, respond: respond)
        case .ping:
            await muscle.noteClientActivity(clientId)
            sendMessage(.pong(pongPayload.withServerTimestamp()), requestId: requestId, respond: respond)
        case .status:
            sendMessage(.status(await makeStatusPayload()), requestId: requestId, respond: respond)

        // Observation
        case .getPasteboard:
            let result = brains.executePasteboardRead()
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
        case .requestScreen:
            brains.stash.clearPendingRotorResult()
            handleScreen(requestId: requestId, respond: respond)
        case .waitForIdle(let target):
            brains.stash.clearPendingRotorResult()
            let observedGeneration = backgroundChangeState.latestGeneration
            let result = await brains.executeWaitForIdle(timeout: min(target.timeout ?? 5.0, 60.0))
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            noteCommandParseSatisfiedIfNeeded(result.accessibilityTrace, observedGeneration: observedGeneration)
            brains.recordSentState()
        case .waitForChange(let target):
            brains.stash.clearPendingRotorResult()
            let observedGeneration = backgroundChangeState.latestGeneration
            let result = await brains.executeWaitForChange(
                timeout: target.resolvedTimeout, expectation: target.expect
            )
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            noteCommandParseSatisfiedIfNeeded(result.accessibilityTrace, observedGeneration: observedGeneration)
            brains.recordSentState()

        // Recording & interactions
        default:
            switch message {
            case .startRecording(let config):
                brains.stash.clearPendingRotorResult()
                await handleStartRecording(config, clientId: clientId, requestId: requestId, respond: respond)
            case .stopRecording:
                brains.stash.clearPendingRotorResult()
                await handleStopRecording(clientId: clientId, requestId: requestId, respond: respond)
            default:
                if let stakeout {
                    await stakeout.noteActivity()
                }
                let observedBackgroundGeneration = backgroundChangeState.latestGeneration
                let backgroundTrace = await brains.computeBackgroundAccessibilityTrace()

                let actionResult = await withCommandParseInFlight {
                    await brains.executeCommand(message)
                }
                await recordAndRespond(
                    command: message,
                    actionResult: actionResult,
                    requestId: requestId,
                    accessibilityTrace: backgroundTrace,
                    observedBackgroundGeneration: observedBackgroundGeneration,
                    respond: respond
                )
            }
        }
    }

    private func withCommandParseInFlight<T>(_ operation: () async -> T) async -> T {
        backgroundChangeState.beginCommand()
        defer { backgroundChangeState.finishCommand() }
        return await operation()
    }

    private func recordAndRespond(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        accessibilityTrace: AccessibilityTrace? = nil,
        observedBackgroundGeneration: UInt64,
        respond: @escaping (Data) -> Void
    ) async {
        if let stakeout {
            await stakeout.recordInteractionIfRecording(command: command, result: actionResult)
        }

        sendMessage(
            .actionResult(actionResult),
            requestId: requestId,
            accessibilityTrace: accessibilityTrace,
            respond: respond
        )
        noteCommandParseSatisfiedIfNeeded(
            actionResult.accessibilityTrace ?? accessibilityTrace,
            observedGeneration: observedBackgroundGeneration
        )
        brains.recordSentState()
    }

    private func noteCommandParseSatisfiedIfNeeded(_ accessibilityTrace: AccessibilityTrace?, observedGeneration: UInt64) {
        guard accessibilityTrace != nil else { return }
        backgroundChangeState.markObserved(through: observedGeneration)
    }

    // MARK: - Settled Change Tracking

    func noteSettledChangeIfNeeded() async {
        while let claimedGeneration = backgroundChangeState.beginSettledParse() {
            let result = await brains.parseSettledTripwireChange()
            backgroundChangeState.finishSettledParse(claimedGeneration: claimedGeneration)
            guard result.changed else { continue }

            if let stakeout {
                await stakeout.noteScreenChange()
            }
        }
    }

    func sendInterface(
        query: InterfaceQuery = InterfaceQuery(),
        requestId: String? = nil,
        respond: @escaping (Data) -> Void
    ) async {
        let observedGeneration = backgroundChangeState.latestGeneration
        switch await brains.observeInterface(query) {
        case .success(let interface):
            insideJobLogger.info("Interface: \(interface.elements.count) elements")
            sendMessage(
                .interface(interface),
                requestId: requestId,
                respond: respond
            )
            backgroundChangeState.markObserved(through: observedGeneration)
            brains.recordSentState()
        case .failure(let error):
            sendMessage(.error(ServerError(kind: .general, message: error.message)), requestId: requestId, respond: respond)
        }
    }

    // MARK: - Screen Capture

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")
        let observedGeneration = backgroundChangeState.latestGeneration

        guard brains.refresh() != nil else {
            sendMessage(.error(ServerError(kind: .general, message: "Could not access accessibility tree")), requestId: requestId, respond: respond)
            return
        }

        guard let (image, bounds) = brains.stash.captureScreen() else {
            sendMessage(.error(ServerError(kind: .general, message: "Could not access app window")), requestId: requestId, respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error(ServerError(kind: .general, message: "Failed to encode screen as PNG")), requestId: requestId, respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height,
            interface: brains.stash.interface()
        )

        sendMessage(.screen(payload), requestId: requestId, respond: respond)
        backgroundChangeState.markObserved(through: observedGeneration)
        insideJobLogger.debug("Screen sent: \(pngData.count) bytes")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

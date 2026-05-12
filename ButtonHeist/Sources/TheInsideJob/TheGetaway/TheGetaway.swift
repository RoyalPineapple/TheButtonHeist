#if canImport(UIKit)
#if DEBUG
import UIKit
import os.log

import TheScore

/// The getaway driver — runs comms between the wire and the crew.
///
/// TheGetaway owns all message routing, encoding, broadcasting, and transport
/// wiring. It does not own any crew members — it receives references to
/// TheMuscle, TheBrains, and TheTripwire from TheInsideJob and routes
/// messages between them and the network.
@MainActor
final class TheGetaway {

    // MARK: - Crew References (not owned)

    let muscle: TheMuscle
    let brains: TheBrains
    let tripwire: TheTripwire

    /// Identity info provided by TheInsideJob for ServerInfo responses.
    struct ServerIdentity {
        let sessionId: UUID
        let effectiveInstanceId: String
        var tlsActive: Bool
    }

    var identity: ServerIdentity

    // MARK: - State

    // `RecordingPhase`, `RecordingOutcome`, and their handlers live in
    // TheGetaway+Recording.swift.
    var recordingPhase: RecordingPhase = .idle
    var hierarchyInvalidated = false
    var completedRecording: RecordingOutcome = .none
    var pendingRecordingResponse: (requestId: String?, respond: (Data) -> Void)?

    /// Client ID of the connection that issued the in-flight `start_recording`.
    /// Set in `handleStartRecording` and threaded through the lifecycle so
    /// (a) auto-finish payloads can be delivered to the originator instead of
    /// broadcast to every authenticated client, and (b) any cached completion
    /// can be invalidated when that connection drops or the session releases.
    /// Nil between recordings. Cleared in `tearDown`, on originator disconnect,
    /// on session-active-change-to-false, and when `completedRecording` is
    /// drained by a `stop_recording` pickup or successful direct delivery.
    var recordingOriginatorClientId: Int?

    /// Current transport — set by `wireTransport`, cleared on teardown.
    private(set) weak var transport: ServerTransport?

    /// Single long-lived consumer Task for `transport.events`. Cancelled on
    /// `tearDown()`; the for-await loop also exits when the transport finishes
    /// its event continuation in `stop()`.
    private var eventConsumerTask: Task<Void, Never>?

    /// Pending Tasks spawned to bridge MainActor-bound recording callbacks
    /// back into TheGetaway. There is at most one in-flight delivery per
    /// recording session, but storing the handle in a tracker keeps the
    /// lifecycle-tracking pattern uniform with the rest of TheGetaway.
    private let pendingRecordingTasks = TaskTracker()

    var stakeout: TheStakeout? {
        if case .recording(let stakeout) = recordingPhase { return stakeout }
        return nil
    }

    // MARK: - Init

    init(muscle: TheMuscle, brains: TheBrains, tripwire: TheTripwire, identity: ServerIdentity) {
        self.muscle = muscle
        self.brains = brains
        self.tripwire = tripwire
        self.identity = identity
    }

    // MARK: - Transport Wiring

    /// Wire a transport to the crew.
    ///
    /// Async because `muscle.installCallbacks(...)` must complete *before* any
    /// transport event consumer starts. The previous shape kicked off an
    /// unstructured `Task { await muscle.installCallbacks(...) }` and returned
    /// synchronously; the caller then immediately ran `transport.start(...)`
    /// and the event consumer began accepting `.clientConnected` events. Task
    /// submission onto an actor's mailbox is not FIFO across separately-rooted
    /// Tasks, so the first `.clientConnected` could race ahead of the install
    /// — `sendToClient` was still nil — and the serverHello was silently
    /// dropped. Awaiting `installCallbacks` inline closes that race for both
    /// `start()` and `resume()`. See finding PR #352 (High) and #359 M1.
    func wireTransport(_ transport: ServerTransport) async {
        self.transport = transport

        // Install actor-isolated callbacks on TheMuscle. Each callback is
        // `@Sendable`. We capture the inner `SimpleSocketServer` actor (which
        // is Sendable) rather than the `ServerTransport` wrapper (NSObject,
        // non-Sendable) so the closures don't drag a non-Sendable type into
        // actor-isolated storage. `onSessionActiveChanged` updates Bonjour
        // TXT state — which is `@MainActor` on the transport — so it hops to
        // MainActor and keeps `[weak transport]` (the hop makes the capture
        // safe). `handleClientConnected` is `@MainActor`, so the
        // onClientAuthenticated bridge hops through an unstructured Task too.
        let server = transport.server
        // These closures are awaited inline at every TheMuscle call site so
        // back-to-back sends/disconnects from one logical operation execute
        // in FIFO order on the SimpleSocketServer actor. The previous
        // fire-and-forget `Task { await server.foo(...) }` shape relied on
        // Swift's unstructured-Task scheduling, which makes no FIFO
        // guarantee — the cross-cutting audit's Finding 5.
        let sendToClient: @Sendable (Data, Int) async -> Void = { data, clientId in
            await server.send(data, to: clientId)
        }
        let markAuth: @Sendable (Int) async -> Void = { clientId in
            await server.markAuthenticated(clientId)
        }
        let disconnect: @Sendable (Int) async -> Void = { clientId in
            await server.disconnect(clientId: clientId)
        }
        let onAuthenticated: @MainActor @Sendable (Int, @escaping @Sendable (Data) -> Void) -> Void = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }
        let onSessionActiveChanged: @MainActor @Sendable (Bool) -> Void = { [weak self] isActive in
            self?.transport?.updateTXTRecord([TXTRecordKey.sessionActive.rawValue: isActive ? "1" : "0"])
            if !isActive {
                // Session released — drop any cached recording payload so a
                // future driver can't pick up a video the previous driver
                // started. Pending stop waiters are also cleared; their
                // transport is dead anyway.
                self?.invalidateRecordingForSessionRelease()
            }
        }
        // Awaited inline: the event consumer below must not see a
        // `.clientConnected` before `sendToClient` and friends are installed.
        // There is no prior install Task to cancel — every call to
        // `wireTransport` simply awaits and reinstalls cleanly, so re-wiring
        // on `resume()` is safe by construction.
        await muscle.installCallbacks(
            sendToClient: sendToClient,
            markClientAuthenticated: markAuth,
            disconnectClient: disconnect,
            onClientAuthenticated: onAuthenticated,
            onSessionActiveChanged: onSessionActiveChanged
        )

        // Keepalives must be answered even when the main actor is wedged on a
        // long parse/settle/explore. The interceptor decodes and replies on
        // the network queue before the message ever enters the event stream;
        // a `.fastPathHandled` event is yielded so we can still note client
        // activity in order with everything else.
        transport.setSyncDataInterceptor { _, data in
            PingFastPath.encodedPong(for: data)
        }

        // `wireTransport` is idempotent: re-wiring cancels any prior
        // consumer Task so the new transport's events flow without contention.
        eventConsumerTask?.cancel()
        eventConsumerTask = Task { @MainActor [weak self, events = transport.events] in
            for await event in events {
                guard let self else { return }
                await self.handleTransportEvent(event)
            }
        }
    }

    /// Dispatch a single transport event on the main actor.
    ///
    /// The consumer awaits this method per event, so `clientConnected` always
    /// completes before the first `dataReceived` for that client and message
    /// N+1 cannot start before message N finishes. The previous per-event
    /// `Task { @MainActor in ... }` bridge could lose ordering: a slow
    /// connect Task and a fast first-message Task were independently
    /// scheduled, and the message could observe an unregistered client
    /// address.
    func handleTransportEvent(_ event: TransportEvent) async {
        switch event {
        case .clientConnected(let clientId, let remoteAddress):
            insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
            if let remoteAddress {
                await muscle.registerClientAddress(clientId, address: remoteAddress)
            }
            await muscle.sendServerHello(clientId: clientId)

        case .clientDisconnected(let clientId):
            insideJobLogger.info("Client \(clientId) disconnected")
            invalidateRecordingForDisconnect(clientId: clientId)
            await muscle.handleClientDisconnected(clientId)

        case .dataReceived(let clientId, let data, let respond):
            await handleClientMessage(clientId, data: data, respond: respond)

        case .unauthenticatedData(let clientId, let data, let respond):
            if let envelope = decodeRequest(data),
               case .status = envelope.message,
               await muscle.helloValidatedClients.contains(clientId) {
                await handleClientMessage(clientId, data: data, respond: respond)
            } else {
                await muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
            }

        case .rateLimited(_, let respond):
            let message = "Rate limited: max \(SimpleSocketServer.maxMessagesPerSecond) messages per second"
            sendMessage(.error(ServerError(kind: .general, message: message)), respond: respond)

        case .fastPathHandled(let clientId):
            await muscle.noteClientActivity(clientId)
        }
    }

    func tearDown() {
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        pendingRecordingTasks.cancelAll()
        transport = nil
        hierarchyInvalidated = false
        completedRecording = .none
        pendingRecordingResponse = nil
        recordingOriginatorClientId = nil
    }

    /// Insert a Task into `pendingRecordingTasks` and prune already-completed
    /// handles so the set does not grow across many recordings.
    func trackRecordingTask(_ task: Task<Void, Never>) {
        pendingRecordingTasks.record(task)
    }

    // MARK: - Message Dispatch

    func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let envelope = decodeRequest(data) else {
            sendMessage(.error(ServerError(kind: .general, message: "Malformed message — could not decode")), respond: respond)
            return
        }

        let requestId = envelope.requestId
        let message = envelope.message

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        let isObserver = await muscle.observerClients.contains(clientId)

        switch message {
        // Protocol messages
        case .clientHello, .authenticate, .watch:
            break
        case .requestInterface:
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(requestId: requestId, respond: respond)
        case .subscribe:
            await muscle.subscribe(clientId: clientId)
        case .unsubscribe:
            await muscle.unsubscribe(clientId: clientId)
        case .ping:
            await muscle.noteClientActivity(clientId)
            sendMessage(.pong, requestId: requestId, respond: respond)
        case .status:
            sendMessage(.status(await makeStatusPayload()), requestId: requestId, respond: respond)

        // Observation
        case .requestScreen:
            handleScreen(requestId: requestId, respond: respond)
        case .waitForIdle(let target):
            let result = await brains.executeWaitForIdle(timeout: min(target.timeout ?? 5.0, 60.0))
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            brains.recordSentState()
        case .waitForChange(let target):
            let result = await brains.executeWaitForChange(
                timeout: target.resolvedTimeout, expectation: target.expect
            )
            sendMessage(.actionResult(result), requestId: requestId, respond: respond)
            brains.recordSentState()

        // Recording & interactions — blocked for observers
        default:
            if isObserver {
                var builder = ActionResultBuilder(method: .activate, screenName: brains.screenName, screenId: brains.screenId)
                builder.message = "Watch mode is read-only"
                sendMessage(.actionResult(builder.failure(errorKind: .unsupported)), requestId: requestId, respond: respond)
                return
            }

            switch message {
            case .startRecording(let config):
                await handleStartRecording(config, clientId: clientId, requestId: requestId, respond: respond)
            case .stopRecording:
                await handleStopRecording(clientId: clientId, requestId: requestId, respond: respond)
            default:
                if let stakeout {
                    await stakeout.noteActivity()
                }
                let backgroundDelta = brains.computeBackgroundDelta()

                if let backgroundDelta, backgroundDelta.isScreenChanged,
                   brains.screenChangedSinceLastSent,
                   message.actionTarget != nil {
                    let lastScreen = brains.lastSentScreenId ?? "unknown"
                    var builder = ActionResultBuilder(method: .waitForChange, screenName: brains.screenName, screenId: brains.screenId)
                    builder.message = "Screen changed while you were thinking"
                        + " (\(lastScreen) → \(brains.screenId ?? "unknown"))"
                        + " — action skipped, here is the current state"
                    builder.interfaceDelta = backgroundDelta
                    let actionResult = builder.success()
                    await recordAndBroadcast(command: message, actionResult: actionResult, requestId: requestId, respond: respond)
                    return
                }

                let actionResult = await brains.executeCommand(message)
                await recordAndBroadcast(command: message, actionResult: actionResult, requestId: requestId, backgroundDelta: backgroundDelta, respond: respond)
            }
        }
    }

    // MARK: - Encode / Decode

    func encodeEnvelope(_ message: ServerMessage, requestId: String? = nil, backgroundDelta: InterfaceDelta? = nil) -> Data? {
        do {
            return try ResponseEnvelope(requestId: requestId, message: message, backgroundDelta: backgroundDelta).encoded()
        } catch {
            insideJobLogger.error("Failed to encode message: \(error)")
            return nil
        }
    }

    func decodeRequest(_ data: Data) -> RequestEnvelope? {
        do {
            return try RequestEnvelope.decoded(from: data)
        } catch {
            insideJobLogger.error("Failed to decode client message: \(error)")
            return nil
        }
    }

    // MARK: - Send / Broadcast

    func sendMessage(_ message: ServerMessage, requestId: String? = nil, backgroundDelta: InterfaceDelta? = nil, respond: @escaping (Data) -> Void) {
        if let data = encodeEnvelope(message, requestId: requestId, backgroundDelta: backgroundDelta) {
            insideJobLogger.debug("Sending \(data.count) bytes")
            respond(data)
        } else if let errorData = encodeEnvelope(.error(ServerError(kind: .general, message: "Encoding failed")), requestId: requestId) {
            respond(errorData)
        }
    }

    /// Broadcast a server message to every subscribed client.
    ///
    /// Awaits the per-subscriber sends so two back-to-back
    /// `broadcastToSubscribed` calls deliver in FIFO order — the
    /// outbound-broadcast risk that the cross-cutting audit's
    /// Finding 5 called out.
    func broadcastToSubscribed(_ message: ServerMessage) async {
        guard !message.isScreenshot else {
            insideJobLogger.error("Refusing to broadcast screenshot payload; screenshots must be requested explicitly")
            return
        }
        guard let data = encodeEnvelope(message) else { return }
        await muscle.broadcastToSubscribed(data)
    }

    /// Broadcast a server message to every authenticated client.
    ///
    /// Awaits the transport so two back-to-back `broadcastToAll` calls from
    /// the same caller deliver in FIFO order. The previous sync shape used
    /// fire-and-forget Tasks under the hood, which made no FIFO guarantee.
    func broadcastToAll(_ message: ServerMessage) async {
        guard !message.isScreenshot else {
            insideJobLogger.error("Refusing to broadcast screenshot payload; screenshots must be requested explicitly")
            return
        }
        guard let data = encodeEnvelope(message) else { return }
        // Capture the Sendable SimpleSocketServer actor across the hop —
        // ServerTransport itself is NSObject and non-Sendable.
        guard let server = transport?.server else { return }
        await server.broadcastToAll(data)
    }

    // MARK: - Response Helpers

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    private func sendServerInfo(respond: @escaping (Data) -> Void) {
        let screenBounds = ScreenMetrics.current.bounds
        let info = ServerInfo(
            appName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            screenWidth: screenBounds.width,
            screenHeight: screenBounds.height,
            instanceId: identity.sessionId.uuidString,
            instanceIdentifier: identity.effectiveInstanceId,
            listeningPort: transport?.listeningPort,
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
            vendorIdentifier: UIDevice.current.identifierForVendor?.uuidString,
            tlsActive: identity.tlsActive
        )
        sendMessage(.info(info), respond: respond)
    }

    private func makeStatusPayload() async -> StatusPayload {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

        let identity = StatusIdentity(
            appName: appName,
            bundleIdentifier: bundleId,
            appBuild: appBuild,
            deviceName: UIDevice.current.name,
            systemVersion: UIDevice.current.systemVersion,
            buttonHeistVersion: buttonHeistVersion
        )

        let isActive = await muscle.isSessionActive
        let watchersAllowed = await muscle.watchersAllowed
        let connectionCount = await muscle.activeSessionConnectionCount
        let session = StatusSession(
            active: isActive,
            watchersAllowed: isActive && watchersAllowed,
            activeConnections: connectionCount
        )

        return StatusPayload(identity: identity, session: session)
    }

    private func recordAndBroadcast(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        backgroundDelta: InterfaceDelta? = nil,
        respond: @escaping (Data) -> Void
    ) async {
        if let stakeout {
            await stakeout.recordInteractionIfRecording(command: command, result: actionResult)
        }

        sendMessage(.actionResult(actionResult), requestId: requestId, backgroundDelta: backgroundDelta, respond: respond)
        brains.recordSentState()

        if await muscle.hasSubscribers {
            let event = InteractionEvent(
                timestamp: Date().timeIntervalSince1970,
                command: command,
                result: actionResult
            )
            await broadcastToSubscribed(.interaction(event))
        }
    }

    // MARK: - Hierarchy Broadcast

    func broadcastIfChanged() async {
        guard await muscle.hasSubscribers else {
            // Still clear the invalidation flag — the hierarchy may have changed
            // but no one is listening so skip the expensive refresh/wire work.
            hierarchyInvalidated = false
            return
        }

        guard let payload = brains.broadcastInterfaceIfChanged() else {
            hierarchyInvalidated = false
            return
        }
        hierarchyInvalidated = false

        await broadcastToSubscribed(.interface(payload))
        if let stakeout {
            Task { await stakeout.noteScreenChange() }
        }

        let subscriberCount = await muscle.subscribedClients.count
        insideJobLogger.debug("Broadcast hierarchy update to \(subscriberCount) subscriber(s)")
    }

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard brains.refresh() != nil else {
            sendMessage(.error(ServerError(kind: .general, message: "Could not access root view")), requestId: requestId, respond: respond)
            return
        }

        let manifest = await brains.navigation.exploreAndPrune()
        let time = String(format: "%.2f", manifest.explorationTime)
        let payload = brains.currentInterface()
        insideJobLogger.info("Explore: \(payload.elements.count) elements (\(manifest.scrollCount) scrolls, \(time)s)")
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
        brains.recordSentState(treeHash: payload.tree.hashValue)
    }

    // MARK: - Screen Capture

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard let (image, bounds) = brains.captureScreen() else {
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
            height: bounds.height
        )

        sendMessage(.screen(payload), requestId: requestId, respond: respond)
        insideJobLogger.debug("Screen sent: \(pngData.count) bytes")
    }
}

private extension ServerMessage {
    var isScreenshot: Bool {
        if case .screen = self { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

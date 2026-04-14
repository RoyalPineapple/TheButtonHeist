#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import os.log

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

    enum RecordingPhase {
        case idle
        case recording(stakeout: TheStakeout)
    }

    var recordingPhase: RecordingPhase = .idle
    var hierarchyInvalidated = false

    /// Current transport — set by `wireTransport`, cleared on teardown.
    private(set) weak var transport: ServerTransport?

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

    func wireTransport(_ transport: ServerTransport) {
        self.transport = transport

        muscle.sendToClient = { [weak transport] data, clientId in transport?.send(data, to: clientId) }
        muscle.markClientAuthenticated = { [weak transport] clientId in transport?.markAuthenticated(clientId) }
        muscle.disconnectClient = { [weak transport] clientId in transport?.disconnect(clientId: clientId) }
        muscle.onClientAuthenticated = { [weak self] clientId, respond in
            self?.handleClientConnected(clientId, respond: respond)
        }
        muscle.onSessionActiveChanged = { [weak transport] isActive in
            transport?.updateTXTRecord([TXTRecordKey.sessionActive.rawValue: isActive ? "1" : "0"])
        }

        transport.onClientConnected = { [weak self] clientId, remoteAddress in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) connected from \(remoteAddress ?? "unknown"), awaiting hello")
                if let remoteAddress {
                    self?.muscle.registerClientAddress(clientId, address: remoteAddress)
                }
                self?.muscle.sendServerHello(clientId: clientId)
            }
        }

        transport.onClientDisconnected = { [weak self] clientId in
            Task { @MainActor in
                insideJobLogger.info("Client \(clientId) disconnected")
                self?.muscle.handleClientDisconnected(clientId)
            }
        }

        transport.onDataReceived = { [weak self] clientId, data, respond in
            Task { @MainActor in
                await self?.handleClientMessage(clientId, data: data, respond: respond)
            }
        }

        transport.onUnauthenticatedData = { [weak self] clientId, data, respond in
            Task { @MainActor in
                guard let self else { return }
                if let envelope = self.decodeRequest(data),
                   case .status = envelope.message,
                   self.muscle.helloValidatedClients.contains(clientId) {
                    await self.handleClientMessage(clientId, data: data, respond: respond)
                } else {
                    self.muscle.handleUnauthenticatedMessage(clientId, data: data, respond: respond)
                }
            }
        }
    }

    func tearDown() {
        transport = nil
        hierarchyInvalidated = false
    }

    // MARK: - Message Dispatch

    func handleClientMessage(_ clientId: Int, data: Data, respond: @escaping (Data) -> Void) async {
        guard let envelope = decodeRequest(data) else {
            sendMessage(.error("Malformed message — could not decode"), respond: respond)
            return
        }

        let requestId = envelope.requestId
        let message = envelope.message

        insideJobLogger.debug("Received from client \(clientId): \(String(describing: message).prefix(40))")

        let isObserver = muscle.observerClients.contains(clientId)

        switch message {
        // Protocol messages
        case .clientHello, .authenticate, .watch:
            break
        case .requestInterface:
            insideJobLogger.debug("Interface requested by client \(clientId)")
            await sendInterface(requestId: requestId, respond: respond)
        case .subscribe:
            muscle.subscribe(clientId: clientId)
        case .unsubscribe:
            muscle.unsubscribe(clientId: clientId)
        case .ping:
            muscle.noteClientActivity(clientId)
            sendMessage(.pong, requestId: requestId, respond: respond)
        case .status:
            sendMessage(.status(makeStatusPayload()), requestId: requestId, respond: respond)

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
                handleStartRecording(config, requestId: requestId, respond: respond)
            case .stopRecording:
                handleStopRecording(requestId: requestId, respond: respond)
            default:
                stakeout?.noteActivity()
                let backgroundDelta = brains.computeBackgroundDelta()

                if let backgroundDelta, backgroundDelta.kind == .screenChanged,
                   brains.screenChangedSinceLastSent,
                   message.actionTarget != nil {
                    let lastScreen = brains.lastSentScreenId ?? "unknown"
                    var builder = ActionResultBuilder(method: .waitForChange, screenName: brains.screenName, screenId: brains.screenId)
                    builder.message = "Screen changed while you were thinking"
                        + " (\(lastScreen) → \(brains.screenId ?? "unknown"))"
                        + " — action skipped, here is the current state"
                    builder.interfaceDelta = backgroundDelta
                    let actionResult = builder.success()
                    recordAndBroadcast(command: message, actionResult: actionResult, requestId: requestId, respond: respond)
                    return
                }

                let actionResult = await brains.executeCommand(message)
                recordAndBroadcast(command: message, actionResult: actionResult, requestId: requestId, backgroundDelta: backgroundDelta, respond: respond)
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
        } else if let errorData = encodeEnvelope(.error("Encoding failed"), requestId: requestId) {
            respond(errorData)
        }
    }

    func broadcastToSubscribed(_ message: ServerMessage) {
        guard let data = encodeEnvelope(message) else { return }
        muscle.broadcastToSubscribed(data)
    }

    func broadcastToAll(_ message: ServerMessage) {
        guard let data = encodeEnvelope(message) else { return }
        transport?.broadcastToAll(data)
    }

    // MARK: - Response Helpers

    private func handleClientConnected(_ clientId: Int, respond: @escaping (Data) -> Void) {
        sendServerInfo(respond: respond)
    }

    private func sendServerInfo(respond: @escaping (Data) -> Void) {
        let screenBounds = UIScreen.main.bounds
        let info = ServerInfo(
            protocolVersion: protocolVersion,
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

    private func makeStatusPayload() -> StatusPayload {
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

        let session = StatusSession(
            active: muscle.isSessionActive,
            watchersAllowed: muscle.isSessionActive && muscle.watchersAllowed,
            activeConnections: muscle.activeSessionConnectionCount
        )

        return StatusPayload(identity: identity, session: session)
    }

    private func recordAndBroadcast(
        command: ClientMessage,
        actionResult: ActionResult,
        requestId: String?,
        backgroundDelta: InterfaceDelta? = nil,
        respond: @escaping (Data) -> Void
    ) {
        if let stakeout, stakeout.isRecording {
            let event = InteractionEvent(
                timestamp: stakeout.recordingElapsed,
                command: command,
                result: actionResult
            )
            stakeout.recordInteraction(event: event)
        }

        sendMessage(.actionResult(actionResult), requestId: requestId, backgroundDelta: backgroundDelta, respond: respond)
        brains.recordSentState()

        if muscle.hasSubscribers {
            let event = InteractionEvent(
                timestamp: Date().timeIntervalSince1970,
                command: command,
                result: actionResult
            )
            broadcastToSubscribed(.interaction(event))
        }
    }

    // MARK: - Hierarchy Broadcast

    func broadcastIfChanged() {
        guard let payload = brains.broadcastInterfaceIfChanged() else {
            hierarchyInvalidated = false
            return
        }
        hierarchyInvalidated = false

        guard muscle.hasSubscribers else { return }

        broadcastToSubscribed(.interface(payload))
        broadcastScreen()
        stakeout?.noteScreenChange()

        insideJobLogger.debug("Broadcast hierarchy update to \(self.muscle.subscribedClients.count) subscriber(s)")
    }

    func sendInterface(requestId: String? = nil, respond: @escaping (Data) -> Void) async {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard brains.refresh() != nil else {
            sendMessage(.error("Could not access root view"), requestId: requestId, respond: respond)
            return
        }

        let manifest = await brains.exploreAndPrune()
        insideJobLogger.info("Explore: \(manifest.elementCount) elements (\(manifest.scrollCount) scrolls, \(String(format: "%.2f", manifest.explorationTime))s)")

        let payload = brains.currentInterface()
        sendMessage(.interface(payload), requestId: requestId, respond: respond)
        brains.recordSentState(treeHash: payload.elements.hashValue)
    }

    // MARK: - Screen Capture

    func handleScreen(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        insideJobLogger.debug("Screen requested")

        guard let (image, bounds) = brains.captureScreen() else {
            sendMessage(.error("Could not access app window"), requestId: requestId, respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screen as PNG"), requestId: requestId, respond: respond)
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

    func broadcastScreen() {
        guard muscle.hasSubscribers else { return }
        guard let (image, bounds) = brains.captureScreen(),
              let pngData = image.pngData() else { return }

        broadcastToSubscribed(.screen(ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )))
    }

    // MARK: - Recording

    func handleStartRecording(_ config: RecordingConfig, requestId: String? = nil, respond: @escaping (Data) -> Void) {
        if case .recording = recordingPhase {
            sendMessage(.recordingError("Recording already in progress"), requestId: requestId, respond: respond)
            return
        }

        let recorder = TheStakeout()
        recorder.captureFrame = { [weak self] in
            self?.brains.captureScreenForRecording()
        }
        recorder.onRecordingComplete = { [weak self] result in
            switch result {
            case .success(let payload):
                self?.broadcastToAll(.recording(payload))
            case .failure(let error):
                self?.broadcastToAll(.recordingError(error.localizedDescription))
            }
            self?.recordingPhase = .idle
            self?.brains.stakeout = nil
        }

        do {
            try recorder.startRecording(config: config)
            recordingPhase = .recording(stakeout: recorder)
            brains.stakeout = recorder
            sendMessage(.recordingStarted, requestId: requestId, respond: respond)
        } catch {
            sendMessage(.recordingError(error.localizedDescription), requestId: requestId, respond: respond)
        }
    }

    func handleStopRecording(requestId: String? = nil, respond: @escaping (Data) -> Void) {
        guard let stakeout else {
            sendMessage(.recordingError("No recording in progress"), requestId: requestId, respond: respond)
            return
        }
        if stakeout.isRecording {
            stakeout.stopRecording(reason: .manual)
        }
        sendMessage(.recordingStopped, requestId: requestId, respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

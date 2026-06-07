import Foundation
import os.log

private let handoffConnectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "connection")

@ButtonHeistActor
extension TheHandoff {
    @discardableResult
    func connect(to device: DiscoveredDevice) -> UUID {
        disconnectForReplacement()
        return openConnection(to: device)
    }

    @discardableResult
    func openConnection(to device: DiscoveredDevice) -> UUID {
        let attemptID = connectionLifecycle.beginConnecting(device: device)

        connection = makeConnection?(device) ?? DeviceConnection(device: device, token: token)
        connection?.onEvent = { [weak self, attemptID] event in
            self?.handleConnectionEvent(event, attemptID: attemptID, device: device)
        }

        connection?.connect()
        return attemptID
    }

    func handleServerMessage(_ message: ServerMessage, requestId: String?) {
        applyServerMessageRoute(serverMessages.route(message, requestId: requestId))
    }

    func disconnect() {
        tearDownConnection(cancelAutoReconnect: true)
    }

    func disconnectForReplacement() {
        tearDownConnection(cancelAutoReconnect: true, replacementReason: .localDisconnect)
    }

    func closeConnection() {
        connection?.disconnect()
        connection = nil
    }

    /// Tear down an in-flight connection attempt after its owner reaches a setup
    /// terminal state (for example, discovery/direct-connect timeout). This
    /// intentionally does not schedule reconnect: there was no usable session
    /// drop, only a failed setup attempt.
    func abortConnectionAttempt(_ attemptID: UUID, failure: HandoffConnectionError) {
        guard connectionLifecycle.disconnectAttempt(attemptID, failure: failure) else { return }
        closeConnection()
    }

    func disableAutoReconnect() {
        if reconnect.disable() {
            connectionLifecycle.leaveReconnectIfActive()
        }
    }

    func waitForConnectionResult(timeout: TimeInterval) async throws {
        try await connectionLifecycle.waitForConnectionResult(timeout: timeout)
    }

    /// Force-close the connection. Use when a timeout suggests the connection
    /// is dead but TCP hasn't noticed yet.
    func forceDisconnect(expectedAttemptID: UUID? = nil) {
        if let expectedAttemptID,
           connectionLifecycle.activeAttemptID != expectedAttemptID {
            return
        }
        guard isConnected else { return }
        handoffConnectionLogger.warning("Force-disconnecting stale connection")
        let reconnectDevice = connectedDevice
        tearDownConnection(cancelAutoReconnect: true, replacementReason: .localDisconnect)
        if let reconnectDevice {
            scheduleAutoReconnectIfNeeded(disconnectedDevice: reconnectDevice)
        }
    }

    @discardableResult
    func send(_ message: ClientMessage, requestId: String? = nil) -> DeviceSendOutcome {
        guard case .connected = connectionPhase,
              let connection else {
            return .failed(.notConnected)
        }
        return connection.send(message, requestId: requestId)
    }

    @discardableResult
    func tickKeepalive(expectedAttemptID: UUID? = nil) -> Int {
        connectionLifecycle.tickKeepalive(expectedAttemptID: expectedAttemptID) {
            connection?.send(.ping, requestId: nil)
        }
    }

    private func handleConnectionEvent(
        _ event: ConnectionEvent,
        attemptID: UUID,
        device: DiscoveredDevice
    ) {
        guard connectionLifecycle.isActiveAttempt(attemptID) else { return }

        switch event {
        case .connected:
            connectionLifecycle.markConnected(
                attemptID: attemptID,
                device: device,
                keepaliveTask: makeKeepaliveTask(attemptID: attemptID)
            )
        case .disconnected(let reason):
            handleDisconnectEvent(reason, attemptID: attemptID, device: device)
        case .sendFailed(let failure, let requestId):
            onSendFailure?(failure, requestId)
        case .message(let message, let requestId):
            handleServerMessage(message, requestId: requestId)
        }
    }

    private func handleDisconnectEvent(
        _ reason: DisconnectReason,
        attemptID: UUID,
        device: DiscoveredDevice
    ) {
        if case .failed = connectionPhase {
            return
        }
        guard connectionLifecycle.markDisconnected(
            reason: reason,
            expectedAttemptID: attemptID
        ) else { return }
        if reason.retryable {
            scheduleAutoReconnectIfNeeded(disconnectedDevice: device)
        }
    }

    private func applyServerMessageRoute(_ route: HandoffServerMessageRoute) {
        switch route {
        case .admission(let decision):
            applyAdmissionDecision(decision)
        case .serverInfo(let info):
            connectionLifecycle.recordServerInfo(info)
        case .forward(let message, let requestId):
            onServerMessage?(message, requestId)
        case .connectionFailure(let message):
            connectionLifecycle.markFailed(.connectionFailed(message))
        case .pong(let payload, let requestId):
            connectionLifecycle.markPongReceived()
            if let requestId {
                onServerMessage?(.pong(payload), requestId)
            }
        case .handled:
            break
        }
    }

    private func applyAdmissionDecision(_ decision: HandoffAdmissionDecision) {
        switch decision {
        case .send(let message):
            sendAdmissionMessage(message)
        case .terminalFailure(let failure):
            failActiveConnection(failure)
        }
    }

    private func failActiveConnection(_ failure: HandoffConnectionError) {
        connectionLifecycle.markFailed(failure)
        closeConnection()
    }

    private func sendAdmissionMessage(_ message: ClientMessage) {
        guard let connection else {
            connectionLifecycle.markFailed(.connectionFailed("Cannot send admission message without an active transport"))
            return
        }
        let outcome = connection.send(message, requestId: nil)
        if case .failed(let failure) = outcome {
            connectionLifecycle.markFailed(.connectionFailed(failure.localizedDescription))
        }
    }

    private func tearDownConnection(
        cancelAutoReconnect: Bool,
        replacementReason: DisconnectReason? = nil
    ) {
        let hadActiveAttempt = connectionLifecycle.activeAttemptID != nil
        if cancelAutoReconnect {
            if reconnect.cancel(clearTarget: true) {
                connectionLifecycle.leaveReconnectIfActive()
            }
        }
        closeConnection()

        if hadActiveAttempt, let replacementReason {
            connectionLifecycle.markDisconnected(reason: replacementReason)
        } else {
            connectionLifecycle.markDisconnected()
        }
    }

    private func makeKeepaliveTask(attemptID: UUID) -> Task<Void, Never> {
        keepalive.makeTask(
            tick: { [weak self] in self?.tickKeepalive(expectedAttemptID: attemptID) ?? 0 },
            forceDisconnect: { [weak self] count in
                handoffConnectionLogger.warning("No pong received for \(count) consecutive pings — forcing disconnect")
                self?.forceDisconnect(expectedAttemptID: attemptID)
            }
        )
    }
}

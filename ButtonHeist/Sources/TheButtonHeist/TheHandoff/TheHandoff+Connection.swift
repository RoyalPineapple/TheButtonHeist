import Foundation
import os.log

import TheScore

private let handoffConnectionLogger = ButtonHeistLog.logger(.handoff(.connection))

@ButtonHeistActor
extension TheHandoff {
    @discardableResult
    func connect(to device: DiscoveredDevice) -> UUID {
        disconnectForReplacement()
        return openConnection(to: device)
    }

    @discardableResult
    func openConnection(to device: DiscoveredDevice) -> UUID {
        let connection = makeConnection?(device) ?? DeviceConnection(
            device: device,
            token: serverMessages.authToken
        )
        let attemptID = connectionLifecycle.beginConnecting(device: device, connection: connection)
        connection.onEvent = { [weak self, attemptID] event in
            self?.handleConnectionEvent(event, attemptID: attemptID, device: device)
        }

        connection.connect()
        return attemptID
    }

    func handleServerMessage(_ message: ServerMessage, requestId: RequestID?) {
        applyServerMessageRoute(serverMessages.route(message, requestId: requestId))
    }

    func disconnect() {
        tearDownConnection(cancelAutoReconnect: true)
    }

    func disconnectForReplacement() {
        tearDownConnection(cancelAutoReconnect: true, replacementReason: .localDisconnect)
    }

    func closeConnection() {
        connectionLifecycle.activeConnection?.disconnect()
    }

    /// Tear down an in-flight connection attempt after its owner reaches a setup
    /// terminal state (for example, discovery/direct-connect timeout). This
    /// intentionally does not schedule reconnect: there was no usable session
    /// drop, only a failed setup attempt.
    func abortConnectionAttempt(_ attemptID: UUID, failure: HandoffConnectionError) {
        guard connectionLifecycle.activeAttemptID == attemptID else { return }
        let connection = connectionLifecycle.activeConnection
        guard connectionLifecycle.disconnectAttempt(attemptID, failure: failure) else { return }
        connection?.disconnect()
    }

    func disableAutoReconnect() {
        _ = connectionLifecycle.disable()
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
    func send(_ message: ClientMessage, requestId: RequestID? = nil) -> DeviceSendOutcome {
        guard case .connected = connectionPhase,
              let connection = connectionLifecycle.activeConnection else {
            return .failed(.notConnected)
        }
        return connection.send(message, requestId: requestId)
    }

    @discardableResult
    func tickKeepalive(expectedAttemptID: UUID? = nil) -> Int {
        let missedPongCount = connectionLifecycle.recordKeepaliveTick(
            expectedAttemptID: expectedAttemptID
        )
        if missedPongCount > 0 {
            connectionLifecycle.activeConnection?.send(.ping, requestId: nil)
        }
        return missedPongCount
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
        case .serverFailure(let serverError):
            failActiveConnection(.serverFailure(serverError))
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
        let connection = connectionLifecycle.activeConnection
        connectionLifecycle.markFailed(failure)
        connection?.disconnect()
    }

    private func sendAdmissionMessage(_ message: ClientMessage) {
        guard let connection = connectionLifecycle.activeConnection else {
            connectionLifecycle.markFailed(.connectionFailed("Cannot send admission message without an active transport"))
            return
        }
        let outcome = connection.send(message, requestId: nil)
        if case .failed(let failure) = outcome {
            failActiveConnection(.connectionFailed(failure.localizedDescription))
        }
    }

    private func tearDownConnection(
        cancelAutoReconnect: Bool,
        replacementReason: DisconnectReason? = nil
    ) {
        let hadActiveAttempt = connectionLifecycle.activeAttemptID != nil
        if cancelAutoReconnect {
            _ = connectionLifecycle.cancel(clearTarget: true)
        }
        if hadActiveAttempt, let replacementReason {
            let connection = connectionLifecycle.activeConnection
            connectionLifecycle.markDisconnected(reason: replacementReason)
            connection?.disconnect()
        } else {
            let connection = connectionLifecycle.activeConnection
            connectionLifecycle.markDisconnected()
            connection?.disconnect()
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

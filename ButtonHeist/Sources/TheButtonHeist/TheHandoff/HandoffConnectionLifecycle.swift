import Foundation

/// Invariant: connection phase, attempt failure, and result waiters advance together.
@ButtonHeistActor
final class HandoffConnectionLifecycle {
    private(set) var phase: HandoffConnectionPhase = .disconnected
    private var attemptFailure: HandoffConnectionError?
    private let waiters = ConnectionResultWaiters()

    var onPhaseChanged: (@ButtonHeistActor (HandoffConnectionPhase) -> Void)?

    var activeAttemptID: UUID? {
        switch phase {
        case .connecting(let attempt):
            return attempt.id
        case .connected(let session):
            return session.attemptID
        case .disconnected, .reconnecting, .failed:
            return nil
        }
    }

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    var diagnosticFailure: HandoffConnectionError? {
        switch phase {
        case .failed(let failure):
            return failure
        case .disconnected, .reconnecting:
            return attemptFailure
        case .connecting:
            return attemptFailure
        case .connected:
            return nil
        }
    }

    var connectedDevice: DiscoveredDevice? {
        if case .connected(let session) = phase { return session.device }
        return nil
    }

    var serverInfo: ServerInfo? {
        if case .connected(let session) = phase { return session.serverInfo }
        return nil
    }

    var missedPongCount: Int {
        if case .connected(let session) = phase { return session.missedPongCount }
        return 0
    }

    func isActiveAttempt(_ attemptID: UUID) -> Bool {
        activeAttemptID == attemptID
    }

    func beginConnecting(device: DiscoveredDevice) -> UUID {
        let attempt = HandoffConnectionAttempt(id: UUID(), device: device)
        attemptFailure = nil
        setPhase(.connecting(attempt))
        return attempt.id
    }

    @discardableResult
    func markConnected(
        attemptID: UUID,
        device: DiscoveredDevice,
        keepaliveTask: Task<Void, Never>
    ) -> Bool {
        guard case .connecting(let attempt) = phase, attempt.id == attemptID else {
            keepaliveTask.cancel()
            return false
        }
        attemptFailure = nil
        setPhase(.connected(HandoffConnectedSession(
            attemptID: attemptID,
            device: device,
            keepaliveTask: keepaliveTask
        )))
        waiters.resolve(attemptID: attemptID, with: .connected)
        return true
    }

    func markFailed(_ failure: HandoffConnectionError) {
        attemptFailure = failure
        let attemptID = activeAttemptID
        let wasActive = phase.isActive
        setPhase(.failed(failure))
        if wasActive, let attemptID {
            waiters.resolve(attemptID: attemptID, with: .failed(failure))
        }
    }

    @discardableResult
    func markDisconnected(
        reason: DisconnectReason? = nil,
        expectedAttemptID: UUID? = nil
    ) -> Bool {
        let attemptID = activeAttemptID
        if let expectedAttemptID, attemptID != expectedAttemptID { return false }

        let wasActive = phase.isActive
        if wasActive {
            if let reason {
                let failure = HandoffConnectionError.disconnected(reason)
                attemptFailure = failure
                setPhase(.disconnected)
                if let attemptID {
                    waiters.resolve(attemptID: attemptID, with: .failed(failure))
                }
            } else {
                let failure = HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage)
                setPhase(.disconnected)
                if let attemptID {
                    waiters.resolve(attemptID: attemptID, with: .failed(failure))
                }
            }
        } else {
            if reason == nil {
                // No active transition and no new cause: clear any stale attempt cause.
                // If a cause arrives after the first disconnect, keep the original cause
                // because it is the one waitForConnectionResult reports on the fast path.
                attemptFailure = nil
            }
            setPhase(.disconnected)
        }
        return wasActive
    }

    @discardableResult
    func disconnectAttempt(_ attemptID: UUID, failure: HandoffConnectionError) -> Bool {
        guard activeAttemptID == attemptID else { return false }
        attemptFailure = failure
        setPhase(.disconnected)
        waiters.resolve(attemptID: attemptID, with: .failed(failure))
        return true
    }

    func recordAttemptFailure(_ failure: HandoffConnectionError) {
        attemptFailure = failure
    }

    func leaveReconnectIfActive() {
        if case .reconnecting = phase {
            setPhase(.disconnected)
        }
    }

    func markReconnecting(target: HandoffReconnectTarget, runID: UUID) {
        setPhase(.reconnecting(HandoffReconnectAttempt(runID: runID, target: target)))
    }

    func recordServerInfo(_ info: ServerInfo) {
        updateConnectedSession { $0.serverInfo = info }
    }

    func markPongReceived() {
        updateConnectedSession { $0.missedPongCount = 0 }
    }

    private func updateConnectedSession(_ body: (inout HandoffConnectedSession) -> Void) {
        guard case .connected(var session) = phase else { return }
        body(&session)
        phase = .connected(session)
    }

    func waitForConnectionResult(timeout: TimeInterval) async throws {
        let attemptID: UUID
        switch phase {
        case .connected:
            return
        case .failed(let failure):
            throw failure
        case .disconnected, .reconnecting:
            if let failure = attemptFailure {
                throw failure
            }
            throw HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage)
        case .connecting(let attempt):
            attemptID = attempt.id
        }

        let waiterID = UUID()
        let timeoutDuration: Duration = .seconds(max(timeout, 0))
        let timeoutTask = Task { @ButtonHeistActor [weak self] in
            guard await Task.cancellableSleep(for: timeoutDuration) else { return }
            self?.waiters.fail(id: waiterID, attemptID: attemptID, with: HandoffConnectionError.timeout)
        }
        defer { timeoutTask.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard activeAttemptID == attemptID else {
                    continuation.resume(throwing: HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage))
                    return
                }
                waiters.register(id: waiterID, attemptID: attemptID, continuation: continuation)
            }
        } onCancel: {
            Task { @ButtonHeistActor [weak self] in
                self?.waiters.cancel(id: waiterID)
            }
        }
    }

    @discardableResult
    func tickKeepalive(expectedAttemptID: UUID? = nil, sendPing: () -> Void) -> Int {
        guard case .connected(var session) = phase else { return 0 }
        if let expectedAttemptID, session.attemptID != expectedAttemptID { return 0 }
        sendPing()
        session.missedPongCount += 1
        let count = session.missedPongCount
        phase = .connected(session)
        return count
    }

    private func setPhase(_ nextPhase: HandoffConnectionPhase) {
        let previousPhase = phase
        cancelOwnedTasksLeaving(previousPhase, for: nextPhase)
        phase = nextPhase
        guard !Self.isSameConnectionPhase(previousPhase, nextPhase) else { return }
        onPhaseChanged?(nextPhase)
    }

    private func cancelOwnedTasksLeaving(
        _ previousPhase: HandoffConnectionPhase,
        for nextPhase: HandoffConnectionPhase
    ) {
        guard case .connected(let session) = previousPhase else { return }
        if case .connected = nextPhase { return }
        session.keepaliveTask.cancel()
    }

    private static func isSameConnectionPhase(
        _ lhs: HandoffConnectionPhase,
        _ rhs: HandoffConnectionPhase
    ) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.failed, .failed):
            return true
        case (.reconnecting(let lhsAttempt), .reconnecting(let rhsAttempt)):
            return lhsAttempt.runID == rhsAttempt.runID
                && lhsAttempt.target == rhsAttempt.target
        default:
            return false
        }
    }

    private static let disconnectedDuringAttemptMessage =
        "Disconnected during connection attempt. The app may have been busy, suspended, or restarted before the handshake completed."
}

private extension HandoffConnectionPhase {
    var isActive: Bool {
        switch self {
        case .connecting, .connected:
            return true
        case .disconnected, .reconnecting, .failed:
            return false
        }
    }
}

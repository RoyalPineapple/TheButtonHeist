import Foundation
import ButtonHeistSupport

/// Invariant: runtime phase, live connection handle, keepalive, attempt failure,
/// and result waiters advance together. The public `phase` is a projection of
/// this runtime owner so disconnected/failed states cannot retain a live handle.
@ButtonHeistActor
final class HandoffConnectionLifecycle {
    private struct ConnectingRuntime {
        let attempt: HandoffConnectionAttempt
        let connection: any DeviceConnecting
    }

    private struct ConnectedRuntime {
        var session: HandoffConnectedSession
        let connection: any DeviceConnecting
    }

    private enum RuntimePhase {
        case disconnected(failure: HandoffConnectionError?)
        case reconnecting(HandoffReconnectAttempt, failure: HandoffConnectionError?)
        case connecting(ConnectingRuntime, failure: HandoffConnectionError?)
        case connected(ConnectedRuntime)
        case failed(HandoffConnectionError)

        var projectedPhase: HandoffConnectionPhase {
            switch self {
            case .disconnected:
                return .disconnected
            case .reconnecting(let attempt, _):
                return .reconnecting(attempt)
            case .connecting(let runtime, _):
                return .connecting(runtime.attempt)
            case .connected(let runtime):
                return .connected(runtime.session)
            case .failed(let failure):
                return .failed(failure)
            }
        }

        var activeAttemptID: UUID? {
            switch self {
            case .connecting(let runtime, _):
                return runtime.attempt.id
            case .connected(let runtime):
                return runtime.session.attemptID
            case .disconnected, .reconnecting, .failed:
                return nil
            }
        }

        var activeConnection: (any DeviceConnecting)? {
            switch self {
            case .connecting(let runtime, _):
                return runtime.connection
            case .connected(let runtime):
                return runtime.connection
            case .disconnected, .reconnecting, .failed:
                return nil
            }
        }

        var diagnosticFailure: HandoffConnectionError? {
            switch self {
            case .failed(let failure):
                return failure
            case .disconnected(let failure),
                 .reconnecting(_, let failure),
                 .connecting(_, let failure):
                return failure
            case .connected:
                return nil
            }
        }

        var isActive: Bool {
            switch self {
            case .connecting, .connected:
                return true
            case .disconnected, .reconnecting, .failed:
                return false
            }
        }

        var connectedRuntime: ConnectedRuntime? {
            if case .connected(let runtime) = self { return runtime }
            return nil
        }
    }

    private var runtimePhase: RuntimePhase = .disconnected(failure: nil)
    private let waiters = ConnectionResultWaiters()

    var onPhaseChanged: (@ButtonHeistActor (HandoffConnectionPhase) -> Void)?

    var phase: HandoffConnectionPhase {
        runtimePhase.projectedPhase
    }

    var activeAttemptID: UUID? {
        runtimePhase.activeAttemptID
    }

    var activeConnection: (any DeviceConnecting)? {
        runtimePhase.activeConnection
    }

    var isConnected: Bool {
        if case .connected = runtimePhase { return true }
        return false
    }

    var diagnosticFailure: HandoffConnectionError? {
        runtimePhase.diagnosticFailure
    }

    var connectedDevice: DiscoveredDevice? {
        if case .connected(let runtime) = runtimePhase { return runtime.session.device }
        return nil
    }

    var serverInfo: ServerInfo? {
        if case .connected(let runtime) = runtimePhase { return runtime.session.serverInfo }
        return nil
    }

    var missedPongCount: Int {
        if case .connected(let runtime) = runtimePhase { return runtime.session.missedPongCount }
        return 0
    }

    func isActiveAttempt(_ attemptID: UUID) -> Bool {
        activeAttemptID == attemptID
    }

    func beginConnecting(device: DiscoveredDevice, connection: any DeviceConnecting) -> UUID {
        let attempt = HandoffConnectionAttempt(id: UUID(), device: device)
        setRuntimePhase(.connecting(
            ConnectingRuntime(attempt: attempt, connection: connection),
            failure: nil
        ))
        return attempt.id
    }

    @discardableResult
    func markConnected(
        attemptID: UUID,
        device: DiscoveredDevice,
        keepaliveTask: Task<Void, Never>
    ) -> Bool {
        guard case .connecting(let runtime, _) = runtimePhase, runtime.attempt.id == attemptID else {
            keepaliveTask.cancel()
            return false
        }
        setRuntimePhase(.connected(ConnectedRuntime(
            session: HandoffConnectedSession(
                attemptID: attemptID,
                device: device,
                keepaliveTask: keepaliveTask
            ),
            connection: runtime.connection
        )))
        waiters.resolve(attemptID: attemptID, with: .connected)
        return true
    }

    func markFailed(_ failure: HandoffConnectionError) {
        let attemptID = activeAttemptID
        let wasActive = runtimePhase.isActive
        setRuntimePhase(.failed(failure))
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

        let wasActive = runtimePhase.isActive
        if wasActive {
            if let reason {
                let failure = HandoffConnectionError.disconnected(reason)
                setRuntimePhase(.disconnected(failure: failure))
                if let attemptID {
                    waiters.resolve(attemptID: attemptID, with: .failed(failure))
                }
            } else {
                let failure = HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage)
                setRuntimePhase(.disconnected(failure: nil))
                if let attemptID {
                    waiters.resolve(attemptID: attemptID, with: .failed(failure))
                }
            }
        } else {
            let failure = reason == nil ? nil : runtimePhase.diagnosticFailure
            setRuntimePhase(.disconnected(failure: failure))
        }
        return wasActive
    }

    @discardableResult
    func disconnectAttempt(_ attemptID: UUID, failure: HandoffConnectionError) -> Bool {
        guard activeAttemptID == attemptID else { return false }
        setRuntimePhase(.disconnected(failure: failure))
        waiters.resolve(attemptID: attemptID, with: .failed(failure))
        return true
    }

    func recordAttemptFailure(_ failure: HandoffConnectionError) {
        switch runtimePhase {
        case .disconnected:
            setRuntimePhase(.disconnected(failure: failure))
        case .reconnecting(let attempt, _):
            setRuntimePhase(.reconnecting(attempt, failure: failure))
        case .connecting(let runtime, _):
            setRuntimePhase(.connecting(runtime, failure: failure))
        case .connected, .failed:
            break
        }
    }

    func leaveReconnectIfActive() {
        if case .reconnecting(_, let failure) = runtimePhase {
            setRuntimePhase(.disconnected(failure: failure))
        }
    }

    func markReconnecting(target: HandoffReconnectTarget, runID: UUID) {
        setRuntimePhase(.reconnecting(
            HandoffReconnectAttempt(runID: runID, target: target),
            failure: runtimePhase.diagnosticFailure
        ))
    }

    func recordServerInfo(_ info: ServerInfo) {
        updateConnectedSession { $0.serverInfo = info }
    }

    func markPongReceived() {
        updateConnectedSession { $0.missedPongCount = 0 }
    }

    private func updateConnectedSession(_ body: (inout HandoffConnectedSession) -> Void) {
        guard case .connected(var runtime) = runtimePhase else { return }
        body(&runtime.session)
        setRuntimePhase(.connected(runtime))
    }

    func waitForConnectionResult(timeout: TimeInterval) async throws {
        let attemptID: UUID
        switch runtimePhase {
        case .connected:
            return
        case .failed(let failure):
            throw failure
        case .disconnected(let failure), .reconnecting(_, let failure):
            if let failure {
                throw failure
            }
            throw HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage)
        case .connecting(let runtime, _):
            attemptID = runtime.attempt.id
        }

        let waiterID = UUID()
        let timeoutDuration: Duration = .seconds(max(timeout, 0))
        let timeoutTask = Task { @ButtonHeistActor [weak self] in
            guard await Task.cancellableSleep(for: timeoutDuration) else { return }
            self?.waiters.fail(id: waiterID, attemptID: attemptID, with: HandoffConnectionError.timeout)
        }
        defer { timeoutTask.cancel() }

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, Error>, Never>) in
                let completion = TimedOneShot<Result<Void, Error>>()
                _ = completion.register(continuation)
                if Task.isCancelled {
                    completion.resolve(returning: .failure(CancellationError()))
                    return
                }
                guard activeAttemptID == attemptID else {
                    completion.resolve(returning: .failure(HandoffConnectionError.connectionFailed(Self.disconnectedDuringAttemptMessage)))
                    return
                }
                waiters.register(id: waiterID, attemptID: attemptID, completion: completion)
            }
        } onCancel: {
            Task { @ButtonHeistActor [weak self] in
                self?.waiters.cancel(id: waiterID)
            }
        }
        try result.get()
    }

    @discardableResult
    func tickKeepalive(expectedAttemptID: UUID? = nil, sendPing: () -> Void) -> Int {
        guard case .connected(var runtime) = runtimePhase else { return 0 }
        if let expectedAttemptID, runtime.session.attemptID != expectedAttemptID { return 0 }
        sendPing()
        runtime.session.missedPongCount += 1
        let count = runtime.session.missedPongCount
        setRuntimePhase(.connected(runtime))
        return count
    }

    private func setRuntimePhase(_ nextPhase: RuntimePhase) {
        let previousPhase = runtimePhase
        cancelOwnedTasksLeaving(previousPhase, for: nextPhase)
        runtimePhase = nextPhase
        let previousProjection = previousPhase.projectedPhase
        let nextProjection = nextPhase.projectedPhase
        guard !Self.isSameConnectionPhase(previousProjection, nextProjection) else { return }
        onPhaseChanged?(nextProjection)
    }

    private func cancelOwnedTasksLeaving(
        _ previousPhase: RuntimePhase,
        for nextPhase: RuntimePhase
    ) {
        guard let previousConnected = previousPhase.connectedRuntime else { return }
        if let nextConnected = nextPhase.connectedRuntime,
           nextConnected.session.attemptID == previousConnected.session.attemptID {
            return
        }
        previousConnected.session.keepaliveTask.cancel()
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

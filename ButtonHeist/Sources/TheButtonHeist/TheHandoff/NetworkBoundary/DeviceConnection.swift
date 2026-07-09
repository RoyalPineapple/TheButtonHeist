import Foundation
import Network
import os.log

import TheScore

let deviceConnectionLogger = ButtonHeistLog.logger(.handoff(.connection))

/// Single ordered event emitted from an NWConnection's network-queue
/// callbacks. Routing both state updates and receive callbacks through one
/// stream means a `.cancelled` cannot land on the actor before a `.ready`
/// for the same connection — a race the prior per-event Task bridge could
/// lose during reconnect.
enum DeviceConnectionEvent: Sendable {
    case state(NWConnection.State, sessionID: UUID, connection: NWConnection)
    case received(DeviceReceiveEvent, sessionID: UUID, connection: NWConnection)
}

/// Connection client using Network framework.
@ButtonHeistActor
final class DeviceConnection: DeviceConnecting, TransportReachabilityConnecting {

    struct ActiveConnection {
        let connection: NWConnection
        var receiveBuffer: Data = Data()
    }

    enum ConnectionState {
        case disconnected
        case connecting(connection: NWConnection)
        case connected(ActiveConnection)
    }

    // Internal for testing (tests use @testable import to set state directly)
    var connectionState: ConnectionState {
        get { runtimePhase.connectionState }
        set {
            setRuntimePhase(RuntimePhase(connectionState: newValue))
        }
    }
    private let device: DiscoveredDevice

    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var onTransportReady: (@ButtonHeistActor () -> Void)?
    var sendContent: (
        @Sendable (
            _ connection: NWConnection,
            _ content: Data,
            _ completion: NWConnection.SendCompletion
        ) -> Void
    ) = { connection, content, completion in
        connection.send(content: content, completion: completion)
    }

    private let token: HandoffAuthToken?

    struct RuntimeSession {
        let id: UUID
        let connection: NWConnection
        var receiveBuffer: Data

        /// Single consumer Task driving NW callbacks into the actor in order.
        /// Replaced on each `connect()`; cancelled when the owning session exits.
        var eventConsumerTask: Task<Void, Never>?

        /// Continuation tied to this connection attempt. Yielded to from
        /// NWConnection's `.global()` callbacks; finished when the session exits.
        var eventContinuation: AsyncStream<DeviceConnectionEvent>.Continuation?
        var tlsFailureTracker: TLSFailureTracker?

        init(
            id: UUID = UUID(),
            connection: NWConnection,
            receiveBuffer: Data = Data(),
            eventConsumerTask: Task<Void, Never>? = nil,
            eventContinuation: AsyncStream<DeviceConnectionEvent>.Continuation? = nil,
            tlsFailureTracker: TLSFailureTracker? = nil
        ) {
            self.id = id
            self.connection = connection
            self.receiveBuffer = receiveBuffer
            self.eventConsumerTask = eventConsumerTask
            self.eventContinuation = eventContinuation
            self.tlsFailureTracker = tlsFailureTracker
        }

        var activeConnection: ActiveConnection {
            ActiveConnection(connection: connection, receiveBuffer: receiveBuffer)
        }

        func cancelOwnedSidecars() {
            eventContinuation?.finish()
            eventConsumerTask?.cancel()
        }
    }

    private enum RuntimePhase {
        case disconnected
        case connecting(RuntimeSession)
        case connected(RuntimeSession)

        init(connectionState: ConnectionState) {
            switch connectionState {
            case .disconnected:
                self = .disconnected
            case .connecting(let connection):
                self = .connecting(RuntimeSession(connection: connection))
            case .connected(let active):
                self = .connected(RuntimeSession(
                    connection: active.connection,
                    receiveBuffer: active.receiveBuffer
                ))
            }
        }

        var connectionState: ConnectionState {
            switch self {
            case .disconnected:
                return .disconnected
            case .connecting(let session):
                return .connecting(connection: session.connection)
            case .connected(let session):
                return .connected(session.activeConnection)
            }
        }

        var sessionID: UUID? {
            switch self {
            case .disconnected:
                return nil
            case .connecting(let session), .connected(let session):
                return session.id
            }
        }

        var connection: NWConnection? {
            switch self {
            case .disconnected:
                return nil
            case .connecting(let session), .connected(let session):
                return session.connection
            }
        }

        func cancelOwnedSidecars() {
            switch self {
            case .disconnected:
                return
            case .connecting(let session), .connected(let session):
                session.cancelOwnedSidecars()
            }
        }
    }

    private var runtimePhase: RuntimePhase = .disconnected

    init(device: DiscoveredDevice, token: String? = nil) {
        self.device = device
        self.token = HandoffAuthToken(token)
    }

    func connect() {
        deviceConnectionLogger.info("Connecting to \(self.device.name)...")

        guard let token else {
            setRuntimePhase(.disconnected)
            deviceConnectionLogger.error("No TLS token available — refusing connection")
            onEvent?(.disconnected(.missingToken))
            return
        }

        let parameters = ButtonHeistTLSPreSharedKey.networkParameters(from: token.rawValue)
        deviceConnectionLogger.info("TLS enabled with token-derived PSK")

        let conn = NWConnection(to: device.endpoint.nwEndpoint, using: parameters)
        let sessionID = UUID()

        // `connect` is idempotent: any prior consumer Task and event stream
        // are torn down so the new connection's events flow without crosstalk
        // from a previous attempt.
        let eventStream = DeviceConnectionEventStream.makeStream()

        conn.stateUpdateHandler = { state in
            DeviceConnectionEventStream.yield(.state(state, sessionID: sessionID, connection: conn), to: eventStream.continuation) { [weak self, weak conn] in
                guard let conn else { return }
                Task { @ButtonHeistActor [weak self] in
                    self?.handleEventStreamOverflow(connection: conn, sessionID: sessionID)
                }
            }
        }

        let eventConsumerTask = Task { @ButtonHeistActor [weak self] in
            for await event in eventStream.events {
                guard let self else { return }
                switch event {
                case .state(let state, let sessionID, let connection):
                    self.handleStateChange(state, sessionID: sessionID, connection: connection)
                case .received(let receiveEvent, let sessionID, let connection):
                    self.handleReceive(receiveEvent, connection: connection, sessionID: sessionID)
                }
            }
        }

        setRuntimePhase(.connecting(RuntimeSession(
            id: sessionID,
            connection: conn,
            eventConsumerTask: eventConsumerTask,
            eventContinuation: eventStream.continuation,
            tlsFailureTracker: TLSFailureTracker()
        )))
        conn.start(queue: .global())
    }

    func disconnect() {
        let connectionToCancel: NWConnection?
        switch runtimePhase {
        case .connecting(let session), .connected(let session):
            connectionToCancel = session.connection
        case .disconnected:
            connectionToCancel = nil
        }
        connectionToCancel?.cancel()
        setRuntimePhase(.disconnected)
    }

    private func setRuntimePhase(_ nextPhase: RuntimePhase) {
        let previousPhase = runtimePhase
        if previousPhase.sessionID != nextPhase.sessionID {
            previousPhase.cancelOwnedSidecars()
        }
        runtimePhase = nextPhase
    }

    func isCurrentSession(
        _ sessionID: UUID?,
        connection suppliedConnection: NWConnection?
    ) -> Bool {
        if let sessionID, runtimePhase.sessionID != sessionID {
            return false
        }
        if let suppliedConnection {
            guard let current = runtimePhase.connection else { return false }
            if current !== suppliedConnection {
                return false
            }
        }
        return true
    }

    private func currentTLSFailureReason(sessionID: UUID?) -> DisconnectReason? {
        switch runtimePhase {
        case .connecting(let session) where sessionID == nil || session.id == sessionID:
            return session.tlsFailureTracker?.currentReason()
        case .connected(let session) where sessionID == nil || session.id == sessionID:
            return session.tlsFailureTracker?.currentReason()
        case .disconnected, .connecting, .connected:
            return nil
        }
    }

    func connectedSession(
        matching sessionID: UUID?,
        connection suppliedConnection: NWConnection
    ) -> RuntimeSession? {
        guard case .connected(let session) = runtimePhase,
              session.connection === suppliedConnection,
              sessionID == nil || session.id == sessionID else {
            return nil
        }
        return session
    }

    func connectedSession(matching sessionID: UUID) -> RuntimeSession? {
        guard case .connected(let session) = runtimePhase,
              session.id == sessionID else {
            return nil
        }
        return session
    }

    func updateConnectedSession(_ session: RuntimeSession) {
        guard case .connected(let current) = runtimePhase,
              current.id == session.id,
              current.connection === session.connection else {
            return
        }
        setRuntimePhase(.connected(session))
    }

    func disconnectConnectedSession(_ session: RuntimeSession) {
        guard case .connected(let current) = runtimePhase,
              current.id == session.id,
              current.connection === session.connection else {
            return
        }
        setRuntimePhase(.disconnected)
    }

    var currentSessionID: UUID? {
        runtimePhase.sessionID
    }

    // MARK: - Private

    /// The NWConnection currently owned by this state machine, regardless of
    /// phase. Used to filter stale callbacks from prior connect attempts.
    var currentConnection: NWConnection? {
        runtimePhase.connection
    }

    /// Internal for testing: state updates are normally dispatched by the
    /// AsyncStream consumer in `connect()`. Tests inject states directly.
    func handleStateChange(
        _ state: NWConnection.State,
        sessionID: UUID? = nil,
        connection: NWConnection? = nil
    ) {
        guard isCurrentSession(sessionID, connection: connection) else { return }
        switch state {
        case .ready:
            guard case .connecting(let session) = runtimePhase else { return }
            if let connection, session.connection !== connection { return }
            deviceConnectionLogger.info("Connected")
            setRuntimePhase(.connected(session))
            onTransportReady?()
            startReceiving()
        case .failed(let error):
            deviceConnectionLogger.error("Connection failed: \(error)")
            let reason = currentTLSFailureReason(sessionID: sessionID) ?? .networkError(error)
            setRuntimePhase(.disconnected)
            onEvent?(.disconnected(reason))
        case .cancelled:
            deviceConnectionLogger.info("Connection cancelled")
            // Client-initiated teardown paths (disconnect(), .failed, buffer overflow,
            // protocol/auth rejection) all set the runtime phase to disconnected before
            // the cancel callback reaches the actor, so wasActive is false and we stay
            // silent. A true wasActive means NWConnection cancelled while we still
            // believed we were live — treat that as an unsolicited server-side close.
            let wasActive = switch runtimePhase {
            case .connecting, .connected:
                true
            case .disconnected:
                false
            }
            setRuntimePhase(.disconnected)
            if wasActive {
                onEvent?(.disconnected(.serverClosed))
            }
        default:
            break
        }
    }

}

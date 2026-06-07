import Foundation
import Network
import os.log

let deviceConnectionLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "connection")

/// Single ordered event emitted from an NWConnection's network-queue
/// callbacks. Routing both state updates and receive callbacks through one
/// stream means a `.cancelled` cannot land on the actor before a `.ready`
/// for the same connection — a race the prior per-event Task bridge could
/// lose during reconnect.
enum DeviceConnectionEvent: Sendable {
    case state(NWConnection.State, connection: NWConnection)
    case received(content: Data?, isComplete: Bool, error: NWError?, connection: NWConnection)
}

/// Connection client using Network framework.
@ButtonHeistActor
final class DeviceConnection: TransportReachabilityConnecting {

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
    var connectionState: ConnectionState = .disconnected
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

    private let token: String?

    /// Single consumer Task driving NW callbacks into the actor in order.
    /// Replaced on each `connect()`; cancelled in `disconnect()`. The for-await
    /// loop also exits when the per-connection event continuation is finished.
    private var eventConsumerTask: Task<Void, Never>?

    /// Continuation tied to the current connection attempt. Yielded to from
    /// NWConnection's `.global()` callbacks; finished when we tear down.
    var eventContinuation: AsyncStream<DeviceConnectionEvent>.Continuation?
    private var tlsFailureTracker: TLSFailureTracker?

    init(device: DiscoveredDevice, token: String? = nil) {
        self.device = device
        self.token = token
    }

    func connect() {
        deviceConnectionLogger.info("Connecting to \(self.device.name)...")

        guard let token = Self.validToken(token) else {
            tlsFailureTracker = nil
            deviceConnectionLogger.error("No TLS token available — refusing connection")
            onEvent?(.disconnected(.missingToken))
            return
        }

        tlsFailureTracker = nil
        let parameters = Self.makeTLSParameters(token: token)
        deviceConnectionLogger.info("TLS enabled with token-derived PSK")

        let conn = NWConnection(to: device.endpoint, using: parameters)

        // `connect` is idempotent: any prior consumer Task and event stream
        // are torn down so the new connection's events flow without crosstalk
        // from a previous attempt.
        eventConsumerTask?.cancel()
        eventContinuation?.finish()

        let (stream, continuation) = DeviceConnectionEventStream.makeStream()
        eventContinuation = continuation

        conn.stateUpdateHandler = { state in
            DeviceConnectionEventStream.yield(.state(state, connection: conn), to: continuation) { [weak self, weak conn] in
                guard let conn else { return }
                Task { @ButtonHeistActor [weak self] in
                    self?.handleEventStreamOverflow(connection: conn)
                }
            }
        }

        eventConsumerTask = Task { @ButtonHeistActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .state(let state, let connection):
                    self.handleStateChange(state, connection: connection)
                case .received(let content, let isComplete, let error, let connection):
                    self.handleReceive(content: content, isComplete: isComplete, error: error, connection: connection)
                }
            }
        }

        connectionState = .connecting(connection: conn)
        conn.start(queue: .global())
    }

    func disconnect() {
        switch connectionState {
        case .connecting(let connection):
            connection.cancel()
        case .connected(let active):
            active.connection.cancel()
        // Already disconnected — connection-state switch, not a wire-message dispatch.
        // swiftlint:disable:next agent_wire_message_arm_no_op_break
        case .disconnected:
            break
        }
        connectionState = .disconnected
        eventContinuation?.finish()
        eventContinuation = nil
        eventConsumerTask?.cancel()
        eventConsumerTask = nil
        tlsFailureTracker = nil
    }

    // MARK: - Private

    /// The NWConnection currently owned by this state machine, regardless of
    /// phase. Used to filter stale callbacks from prior connect attempts.
    var currentConnection: NWConnection? {
        switch connectionState {
        case .connecting(let connection): return connection
        case .connected(let active): return active.connection
        case .disconnected: return nil
        }
    }

    private nonisolated static func validToken(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }

    /// Internal for testing: state updates are normally dispatched by the
    /// AsyncStream consumer in `connect()`. Tests inject states directly.
    func handleStateChange(_ state: NWConnection.State, connection: NWConnection? = nil) {
        // If a connection was supplied (production path), ignore callbacks
        // from a prior connect attempt. The consumer Task is recreated on
        // every connect, so stale callbacks here would only be possible if NW
        // flushed events for a previously-cancelled connection before the
        // continuation finished.
        if let connection, let current = currentConnection, current !== connection {
            return
        }
        switch state {
        case .ready:
            guard case .connecting(let conn) = connectionState else { return }
            deviceConnectionLogger.info("Connected")
            connectionState = .connected(ActiveConnection(connection: conn))
            onTransportReady?()
            startReceiving()
        case .failed(let error):
            deviceConnectionLogger.error("Connection failed: \(error)")
            let reason = tlsFailureTracker?.currentReason() ?? .networkError(error)
            connectionState = .disconnected
            tlsFailureTracker = nil
            onEvent?(.disconnected(reason))
        case .cancelled:
            deviceConnectionLogger.info("Connection cancelled")
            // Client-initiated teardown paths (disconnect(), .failed, buffer overflow,
            // protocol/auth rejection) all set connectionState = .disconnected before
            // the cancel callback reaches the actor, so wasActive is false and we stay
            // silent. A true wasActive means NWConnection cancelled while we still
            // believed we were live — treat that as an unsolicited server-side close.
            let wasActive = switch connectionState {
            case .connecting, .connected:
                true
            case .disconnected:
                false
            }
            connectionState = .disconnected
            tlsFailureTracker = nil
            if wasActive {
                onEvent?(.disconnected(.serverClosed))
            }
        default:
            break
        }
    }

}

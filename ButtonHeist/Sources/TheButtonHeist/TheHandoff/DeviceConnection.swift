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

    private static let maxBufferSize = 64 * 1024 * 1024
    nonisolated static let eventStreamBufferLimit = 512

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

    private let expectedFingerprint: String?

    /// Single consumer Task driving NW callbacks into the actor in order.
    /// Replaced on each `connect()`; cancelled in `disconnect()`. The for-await
    /// loop also exits when the per-connection event continuation is finished.
    private var eventConsumerTask: Task<Void, Never>?

    /// Continuation tied to the current connection attempt. Yielded to from
    /// NWConnection's `.global()` callbacks; finished when we tear down.
    private var eventContinuation: AsyncStream<DeviceConnectionEvent>.Continuation?
    private var tlsFailureTracker: TLSFailureTracker?

    init(device: DiscoveredDevice) {
        self.device = device
        self.expectedFingerprint = device.certFingerprint
    }

    func connect() {
        deviceConnectionLogger.info("Connecting to \(self.device.name)...")

        let parameters: NWParameters
        if let expectedFingerprint {
            let tracker = TLSFailureTracker()
            tlsFailureTracker = tracker
            parameters = Self.makeTLSParameters(expectedFingerprint: expectedFingerprint, failureTracker: tracker)
            deviceConnectionLogger.info("TLS enabled, verifying fingerprint: \(expectedFingerprint.prefix(20))...")
        } else if Self.isLoopbackEndpoint(device.endpoint) {
            tlsFailureTracker = nil
            parameters = Self.makeLoopbackTLSParameters()
            deviceConnectionLogger.warning("No TLS fingerprint available for loopback endpoint, allowing direct simulator connection")
        } else {
            tlsFailureTracker = nil
            deviceConnectionLogger.error("No TLS fingerprint available — refusing plain TCP connection")
            onEvent?(.disconnected(.missingFingerprint))
            return
        }

        let conn = NWConnection(to: device.endpoint, using: parameters)

        // `connect` is idempotent: any prior consumer Task and event stream
        // are torn down so the new connection's events flow without crosstalk
        // from a previous attempt.
        eventConsumerTask?.cancel()
        eventContinuation?.finish()

        let (stream, continuation) = Self.makeEventStream()
        eventContinuation = continuation

        conn.stateUpdateHandler = { state in
            Self.yieldEvent(.state(state, connection: conn), to: continuation) { [weak self, weak conn] in
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

    @discardableResult
    func send(_ message: ClientMessage, requestId: String? = nil) -> DeviceSendOutcome {
        guard case .connected(let active) = connectionState else {
            return .failed(.notConnected)
        }
        let envelope = RequestEnvelope(requestId: requestId, message: message)
        let data: Data
        do {
            var encoded = try JSONEncoder().encode(envelope)
            encoded.append(0x0A)
            data = encoded
        } catch {
            deviceConnectionLogger.error("Failed to encode message: \(error)")
            return .failed(.encodingFailed(error.localizedDescription))
        }

        let connection = active.connection
        sendContent(connection, data, .contentProcessed { [weak self] error in
            if let error {
                deviceConnectionLogger.error("Send error: \(error)")
                Task { @ButtonHeistActor [weak self] in
                    self?.handleSendFailure(error, requestId: requestId, connection: connection)
                }
            }
        })
        return .enqueued
    }

    // MARK: - Private

    /// The NWConnection currently owned by this state machine, regardless of
    /// phase. Used to filter stale callbacks from prior connect attempts.
    private var currentConnection: NWConnection? {
        switch connectionState {
        case .connecting(let connection): return connection
        case .connected(let active): return active.connection
        case .disconnected: return nil
        }
    }

    private func handleSendFailure(_ error: NWError, requestId: String?, connection: NWConnection) {
        if let current = currentConnection, current !== connection {
            return
        }
        onEvent?(.sendFailed(.transportFailed(error.localizedDescription), requestId: requestId))
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

    private func startReceiving() {
        guard case .connected(let active) = connectionState else { return }
        receiveNext(connection: active.connection)
    }

    private func receiveNext(connection: NWConnection) {
        // Yield receive callbacks onto the same ordered stream as state
        // changes; the consumer Task in `connect()` dispatches them back into
        // the actor in arrival order.
        let continuation = eventContinuation
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
            guard let continuation else { return }
            Self.yieldEvent(
                .received(content: content, isComplete: isComplete, error: error, connection: connection),
                to: continuation
            ) { [weak self, weak connection] in
                guard let connection else { return }
                Task { @ButtonHeistActor [weak self] in
                    self?.handleEventStreamOverflow(connection: connection)
                }
            }
        }
    }

    nonisolated static func makeEventStream() -> (
        AsyncStream<DeviceConnectionEvent>,
        AsyncStream<DeviceConnectionEvent>.Continuation
    ) {
        AsyncStream<DeviceConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(eventStreamBufferLimit)
        )
    }

    nonisolated static func yieldEvent(
        _ event: DeviceConnectionEvent,
        to continuation: AsyncStream<DeviceConnectionEvent>.Continuation,
        onOverflow: @escaping @Sendable () -> Void
    ) {
        switch continuation.yield(event) {
        case .enqueued, .terminated:
            return
        case .dropped:
            continuation.finish()
            onOverflow()
        @unknown default:
            continuation.finish()
            onOverflow()
        }
    }

    /// Internal for testing and overflow handling from NW callbacks.
    func handleEventStreamOverflow(connection: NWConnection) {
        guard let current = currentConnection, current === connection else { return }
        deviceConnectionLogger.error("Connection event backlog exceeded \(Self.eventStreamBufferLimit), disconnecting")
        disconnect()
        onEvent?(.disconnected(.eventBacklogOverflow(maxEvents: Self.eventStreamBufferLimit)))
    }

    // Internal for testing stale-callback handling.
    func handleReceive(
        content: Data?,
        isComplete: Bool,
        error: NWError?,
        connection: NWConnection
    ) {
        guard case .connected(var active) = connectionState,
              active.connection === connection else {
            // Ignore callbacks from stale/cancelled sockets after reconnect.
            return
        }

        if let error {
            deviceConnectionLogger.error("Receive error: \(error)")
            connectionState = .disconnected
            onEvent?(.disconnected(.networkError(error)))
            return
        }

        if let content {
            active.receiveBuffer.append(content)

            if active.receiveBuffer.count > Self.maxBufferSize {
                deviceConnectionLogger.error("Server exceeded max buffer size, disconnecting")
                disconnect()
                onEvent?(.disconnected(.bufferOverflow))
                return
            }

            connectionState = .connected(active)
            processBuffer()
            guard case .connected(let latest) = connectionState,
                  latest.connection === connection else {
                return
            }
        }

        if isComplete {
            deviceConnectionLogger.info("Connection closed by server")
            connectionState = .disconnected
            onEvent?(.disconnected(.serverClosed))
        } else {
            guard case .connected(let latest) = connectionState,
                  latest.connection === connection else { return }
            receiveNext(connection: connection)
        }
    }

    private func processBuffer() {
        while true {
            guard case .connected(var active) = connectionState else { return }
            guard let newlineIndex = active.receiveBuffer.firstIndex(of: 0x0A) else { return }
            let messageData = active.receiveBuffer.prefix(upTo: newlineIndex)
            active.receiveBuffer = Data(active.receiveBuffer.suffix(from: active.receiveBuffer.index(after: newlineIndex)))
            connectionState = .connected(active)

            if !messageData.isEmpty {
                handleMessage(Data(messageData))
            }
        }
    }

}

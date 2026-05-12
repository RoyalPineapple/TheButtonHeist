import Foundation
import Network
import CryptoKit
import Security
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "connection")

/// Structured reason for why a connection was closed.
///
/// Kept separate from FenceError because DisconnectReason is a value type
/// used in the `onDisconnected` callback and `ConnectionEvent.disconnected`,
/// not a thrown error. It carries transport-level detail (bufferOverflow,
/// serverClosed, networkError, certificateMismatch, protocolMismatch,
/// localDisconnect) that callers never need to catch — they observe it
/// through the callback to decide whether to reconnect. FenceError is
/// the single thrown error type for all of TheFence, TheHandoff, and
/// DeviceResolver.
enum DisconnectReason: Error, LocalizedError {
    case networkError(Error)
    case bufferOverflow
    case serverClosed
    case authFailed(String)
    case sessionLocked(String)
    case protocolMismatch(String)
    case localDisconnect
    case certificateMismatch
    case missingFingerprint

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .bufferOverflow:
            return "Server exceeded max buffer size"
        case .serverClosed:
            return "Connection closed by server"
        case .authFailed(let reason):
            return "Auth failed: \(reason)"
        case .sessionLocked(let message):
            return "Session locked: \(message)"
        case .protocolMismatch(let message):
            return "Protocol mismatch: \(message)"
        case .localDisconnect:
            return "Disconnected by client"
        case .certificateMismatch:
            return "Server certificate fingerprint does not match expected value"
        case .missingFingerprint:
            return "No TLS fingerprint available for non-loopback device — cannot establish secure connection"
        }
    }
}

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
final class DeviceConnection: DeviceConnecting {

    private static let maxBufferSize = 64 * 1024 * 1024

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
    private(set) var token: String?

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    var onEvent: (@ButtonHeistActor (ConnectionEvent) -> Void)?
    var autoRespondToAuthRequired = true
    var onSend: (@ButtonHeistActor (ClientMessage, String?) -> Void)?

    /// When true, send .watch instead of .authenticate on authRequired
    var observeMode: Bool = false
    /// Driver identity for session locking (set via BUTTONHEIST_DRIVER_ID)
    var driverId: String?

    private let expectedFingerprint: String?

    /// Single consumer Task driving NW callbacks into the actor in order.
    /// Replaced on each `connect()`; cancelled in `disconnect()`. The for-await
    /// loop also exits when the per-connection event continuation is finished.
    private var eventConsumerTask: Task<Void, Never>?

    /// Continuation tied to the current connection attempt. Yielded to from
    /// NWConnection's `.global()` callbacks; finished when we tear down.
    private var eventContinuation: AsyncStream<DeviceConnectionEvent>.Continuation?

    init(device: DiscoveredDevice, token: String? = nil, driverId: String? = nil) {
        self.device = device
        self.token = token
        self.driverId = driverId
        self.expectedFingerprint = device.certFingerprint
    }

    func connect() {
        logger.info("Connecting to \(self.device.name)...")

        let parameters: NWParameters
        if let expectedFingerprint {
            parameters = Self.makeTLSParameters(expectedFingerprint: expectedFingerprint)
            logger.info("TLS enabled, verifying fingerprint: \(expectedFingerprint.prefix(20))...")
        } else if Self.isLoopbackEndpoint(device.endpoint) {
            parameters = Self.makeLoopbackTLSParameters()
            logger.warning("No TLS fingerprint available for loopback endpoint, allowing direct simulator connection")
        } else {
            logger.error("No TLS fingerprint available — refusing plain TCP connection")
            onEvent?(.disconnected(.missingFingerprint))
            return
        }

        let conn = NWConnection(to: device.endpoint, using: parameters)

        // `connect` is idempotent: any prior consumer Task and event stream
        // are torn down so the new connection's events flow without crosstalk
        // from a previous attempt.
        eventConsumerTask?.cancel()
        eventContinuation?.finish()

        let (stream, continuation) = AsyncStream<DeviceConnectionEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        eventContinuation = continuation

        conn.stateUpdateHandler = { state in
            continuation.yield(.state(state, connection: conn))
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
    }

    func send(_ message: ClientMessage, requestId: String? = nil) {
        onSend?(message, requestId)
        guard case .connected(let active) = connectionState else { return }
        let envelope = RequestEnvelope(requestId: requestId, message: message)
        let data: Data
        do {
            var encoded = try JSONEncoder().encode(envelope)
            encoded.append(0x0A)
            data = encoded
        } catch {
            logger.error("Failed to encode message: \(error)")
            return
        }

        active.connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                logger.error("Send error: \(error)")
            }
        })
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
            logger.info("Connected")
            connectionState = .connected(ActiveConnection(connection: conn))
            onEvent?(.transportReady)
            startReceiving()
        case .failed(let error):
            logger.error("Connection failed: \(error)")
            connectionState = .disconnected
            onEvent?(.disconnected(.networkError(error)))
        case .cancelled:
            logger.info("Connection cancelled")
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
            continuation?.yield(.received(content: content, isComplete: isComplete, error: error, connection: connection))
        }
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
            logger.error("Receive error: \(error)")
            connectionState = .disconnected
            onEvent?(.disconnected(.networkError(error)))
            return
        }

        if let content {
            active.receiveBuffer.append(content)

            if active.receiveBuffer.count > Self.maxBufferSize {
                logger.error("Server exceeded max buffer size, disconnecting")
                disconnect()
                onEvent?(.disconnected(.bufferOverflow))
                return
            }

            connectionState = .connected(active)
            processBuffer()
        }

        if isComplete {
            logger.info("Connection closed by server")
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

    // Internal for testing (see AuthFlowTests, AuthFailureTests)
    func handleMessage(_ data: Data) {
        logger.debug("Parsing message: \(data.count) bytes")
        guard let envelope = decodeEnvelope(from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                logger.error("Failed to decode: \(str.prefix(200))")
            }
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? "<binary data>"
            onEvent?(.message(.error(ServerError(kind: .general, message: "Failed to decode server message: \(detail)")), requestId: nil, backgroundDelta: nil))
            return
        }

        if envelope.buttonHeistVersion != buttonHeistVersion {
            let message = "server=\(envelope.buttonHeistVersion), client=\(buttonHeistVersion)"
            logger.error("buttonHeistVersion mismatch: \(message)")
            onEvent?(.message(.protocolMismatch(ProtocolMismatchPayload(
                serverButtonHeistVersion: envelope.buttonHeistVersion,
                clientButtonHeistVersion: buttonHeistVersion
            )), requestId: envelope.requestId, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.protocolMismatch(message)))
            return
        }

        switch envelope.message {
        case .serverHello:
            logger.info("Received server hello")
            send(.clientHello)
        case .protocolMismatch(let payload):
            let message = "server=\(payload.serverButtonHeistVersion), client=\(payload.clientButtonHeistVersion)"
            logger.error("buttonHeistVersion mismatch: \(message)")
            onEvent?(.message(.protocolMismatch(payload), requestId: envelope.requestId, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.protocolMismatch(message)))
        case .authRequired:
            if autoRespondToAuthRequired {
                handleAuthRequired()
            } else {
                onEvent?(.message(.authRequired, requestId: nil, backgroundDelta: nil))
            }
        case .error(let serverError) where serverError.kind == .authFailure:
            logger.error("Auth failed: \(serverError.message)")
            onEvent?(.message(.error(serverError), requestId: nil, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.authFailed(serverError.message)))
        case .authApproved(let payload):
            logger.info("Auth approved via UI, received token")
            token = payload.token
            onEvent?(.message(.authApproved(payload), requestId: nil, backgroundDelta: nil))
        case .sessionLocked(let payload):
            logger.warning("Session locked: \(payload.message)")
            onEvent?(.message(.sessionLocked(payload), requestId: nil, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.sessionLocked(payload.message)))
        case .info(let info):
            logger.info("Received server info: \(info.appName)")
            onEvent?(.connected)
            onEvent?(.message(.info(info), requestId: envelope.requestId, backgroundDelta: nil))
        case .pong:
            // Pong must reach TheHandoff so the keepalive task can reset
            // its missed-pong counter. Earlier code logged the pong here
            // and stopped, which meant the counter incremented every 5s
            // but never decremented — TheHandoff would force-disconnect
            // any connection that stayed idle for 30s, including the
            // window while the server was finalizing a recording. The
            // log line stays for diagnostic noise; the message is also
            // propagated so TheHandoff can mark the connection live.
            logger.debug("Received pong")
            onEvent?(.message(envelope.message, requestId: envelope.requestId, backgroundDelta: envelope.backgroundDelta))
        case .recordingStopped:
            // TheHandoff clears its recording phase on this message;
            // dropping it here left the client believing a recording
            // was still in progress after the server had already torn
            // it down (e.g. a max-duration broadcast with no pending
            // stop_recording response).
            logger.debug("Recording stop acknowledged")
            onEvent?(.message(envelope.message, requestId: envelope.requestId, backgroundDelta: envelope.backgroundDelta))
        default:
            onEvent?(.message(envelope.message, requestId: envelope.requestId, backgroundDelta: envelope.backgroundDelta))
        }
    }

    private func handleAuthRequired() {
        if observeMode {
            logger.info("Auth required, sending watch request")
            send(.watch(WatchPayload(token: token ?? "")))
        } else {
            logger.info("Auth required, sending token")
            send(.authenticate(AuthenticatePayload(
                token: token ?? "",
                driverId: driverId
            )))
        }
    }

    private func decodeEnvelope(from data: Data) -> ResponseEnvelope? {
        do {
            return try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            logger.error("Failed to decode server response: \(error)")
            return nil
        }
    }
}

// MARK: - TLS

nonisolated extension DeviceConnection {

    fileprivate static func makeTLSParameters(expectedFingerprint: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let expected = expectedFingerprint
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, trust, completionHandler in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                      let leaf = chain.first else {
                    logger.error("TLS verification failed: no server certificate")
                    completionHandler(false)
                    return
                }
                let derData = SecCertificateCopyData(leaf) as Data
                let hash = SHA256.hash(data: derData)
                let actual = "sha256:" + hash.map { String(format: "%02x", $0) }.joined()

                let matches = actual == expected
                if matches {
                    logger.debug("TLS fingerprint verified")
                } else {
                    logger.error("TLS fingerprint mismatch: expected=\(expected.prefix(20))... actual=\(actual.prefix(20))...")
                }
                completionHandler(matches)
            },
            DispatchQueue(label: "com.buttonheist.tls.verify")
        )

        return NWParameters(tls: tlsOptions)
    }

    fileprivate static func makeLoopbackTLSParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in
                completionHandler(true)
            },
            DispatchQueue(label: "com.buttonheist.tls.loopback")
        )

        return NWParameters(tls: tlsOptions)
    }

    static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }

        switch host {
        case .ipv4(let addr):
            return addr == .loopback || addr.rawValue.first == 127
        case .ipv6(let addr):
            return addr == .loopback
        case .name:
            return false
        @unknown default:
            return false
        }
    }
}

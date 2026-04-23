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
public enum DisconnectReason: Error, LocalizedError {
    case networkError(Error)
    case bufferOverflow
    case serverClosed
    case authFailed(String)
    case sessionLocked(String)
    case protocolMismatch(String)
    case localDisconnect
    case certificateMismatch
    case missingFingerprint

    public var errorDescription: String? {
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

/// Connection client using Network framework.
@ButtonHeistActor
public final class DeviceConnection: DeviceConnecting {

    private static let maxBufferSize = 10_000_000 // 10 MB

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

    public var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    public var onEvent: ((ConnectionEvent) -> Void)?
    public var autoRespondToAuthRequired = true
    var onSend: ((ClientMessage, String?) -> Void)?

    /// When true, send .watch instead of .authenticate on authRequired
    public var observeMode: Bool = false
    /// Driver identity for session locking (set via BUTTONHEIST_DRIVER_ID)
    public var driverId: String?

    private let expectedFingerprint: String?

    public init(device: DiscoveredDevice, token: String? = nil, driverId: String? = nil) {
        self.device = device
        self.token = token
        self.driverId = driverId
        self.expectedFingerprint = device.certFingerprint
    }

    public func connect() {
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

        conn.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateChange(state)
            }
        }

        connectionState = .connecting(connection: conn)
        conn.start(queue: .global())
    }

    public func disconnect() {
        switch connectionState {
        case .connecting(let connection):
            connection.cancel()
        case .connected(let active):
            active.connection.cancel()
        case .disconnected:
            break
        }
        connectionState = .disconnected
    }

    public func send(_ message: ClientMessage, requestId: String? = nil) {
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

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            guard case .connecting(let connection) = connectionState else { return }
            logger.info("Connected")
            connectionState = .connected(ActiveConnection(connection: connection))
            onEvent?(.transportReady)
            startReceiving()
        case .failed(let error):
            logger.error("Connection failed: \(error)")
            connectionState = .disconnected
            onEvent?(.disconnected(.networkError(error)))
        case .cancelled:
            logger.info("Connection cancelled")
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                await self?.handleReceive(content: content, isComplete: isComplete, error: error, connection: connection)
            }
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
            onEvent?(.message(.error("Failed to decode server message: \(detail)"), requestId: nil, backgroundDelta: nil))
            return
        }

        if envelope.protocolVersion != protocolVersion {
            let message = "expected \(protocolVersion), got \(envelope.protocolVersion)"
            logger.error("Protocol mismatch: \(message)")
            onEvent?(.message(.protocolMismatch(ProtocolMismatchPayload(
                expectedProtocolVersion: protocolVersion,
                receivedProtocolVersion: envelope.protocolVersion
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
            let message = "expected \(payload.expectedProtocolVersion), got \(payload.receivedProtocolVersion)"
            logger.error("Protocol mismatch: \(message)")
            onEvent?(.message(.protocolMismatch(payload), requestId: envelope.requestId, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.protocolMismatch(message)))
        case .authRequired:
            if autoRespondToAuthRequired {
                handleAuthRequired()
            } else {
                onEvent?(.message(.authRequired, requestId: nil, backgroundDelta: nil))
            }
        case .authFailed(let reason):
            logger.error("Auth failed: \(reason)")
            onEvent?(.message(.authFailed(reason), requestId: nil, backgroundDelta: nil))
            disconnect()
            onEvent?(.disconnected(.authFailed(reason)))
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
        case .recordingStopped:
            logger.debug("Recording stop acknowledged")
        case .pong:
            logger.debug("Received pong")
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

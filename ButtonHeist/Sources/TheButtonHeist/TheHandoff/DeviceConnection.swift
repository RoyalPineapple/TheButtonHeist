import Foundation
import Network
import Crypto
import Security
import os.log

private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "connection")

private struct ServerMessageEnvelope: Decodable {
    let message: ServerMessage
}

/// Structured reason for why a connection was closed.
public enum DisconnectReason: Error, LocalizedError {
    case networkError(Error)
    case bufferOverflow
    case serverClosed
    case authFailed(String)
    case sessionLocked(String)
    case localDisconnect
    case certificateMismatch

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
        case .localDisconnect:
            return "Disconnected by client"
        case .certificateMismatch:
            return "Server certificate fingerprint does not match expected value"
        }
    }
}

/// Connection client using Network framework.
@ButtonHeistActor
public final class DeviceConnection: DeviceConnecting {

    private static let maxBufferSize = 10_000_000 // 10 MB

    private var connection: NWConnection?
    private let device: DiscoveredDevice
    private(set) var token: String?
    private var receiveBuffer = Data()
    public var isConnected = false

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

        guard let expectedFingerprint else {
            logger.error("No TLS fingerprint available — refusing plain TCP connection")
            onEvent?(.disconnected(.certificateMismatch))
            return
        }

        let parameters = Self.makeTLSParameters(expectedFingerprint: expectedFingerprint)
        logger.info("TLS enabled, verifying fingerprint: \(expectedFingerprint.prefix(20))...")

        let conn = NWConnection(to: device.endpoint, using: parameters)

        conn.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateChange(state)
            }
        }

        self.connection = conn
        conn.start(queue: .global())
    }

    public func disconnect() {
        isConnected = false
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
    }

    public func send(_ message: ClientMessage, requestId: String? = nil) {
        onSend?(message, requestId)
        guard let connection, isConnected else { return }
        let envelope = RequestEnvelope(requestId: requestId, message: message)
        guard var data = try? JSONEncoder().encode(envelope) else {
            logger.error("Failed to encode message: \(String(describing: message).prefix(100))")
            return
        }
        data.append(0x0A)

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                logger.error("Send error: \(error)")
            }
        })
    }

    // MARK: - Private

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            logger.info("Connected")
            isConnected = true
            onEvent?(.transportReady)
            startReceiving()
        case .failed(let error):
            logger.error("Connection failed: \(error)")
            isConnected = false
            onEvent?(.disconnected(.networkError(error)))
        case .cancelled:
            logger.info("Connection cancelled")
            isConnected = false
        default:
            break
        }
    }

    private func startReceiving() {
        guard let connection else { return }
        receiveNext(connection: connection)
    }

    private func receiveNext(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                await self?.handleReceive(content: content, isComplete: isComplete, error: error, connection: connection)
            }
        }
    }

    private func handleReceive(
        content: Data?,
        isComplete: Bool,
        error: NWError?,
        connection: NWConnection
    ) {
        if let error {
            logger.error("Receive error: \(error)")
            isConnected = false
            onEvent?(.disconnected(.networkError(error)))
            return
        }

        if let content {
            receiveBuffer.append(content)

            if receiveBuffer.count > Self.maxBufferSize {
                logger.error("Server exceeded max buffer size, disconnecting")
                disconnect()
                onEvent?(.disconnected(.bufferOverflow))
                return
            }

            processBuffer()
        }

        if isComplete {
            logger.info("Connection closed by server")
            isConnected = false
            onEvent?(.disconnected(.serverClosed))
        } else {
            receiveNext(connection: connection)
        }
    }

    private func processBuffer() {
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let messageData = receiveBuffer.prefix(upTo: newlineIndex)
            receiveBuffer = Data(receiveBuffer.suffix(from: receiveBuffer.index(after: newlineIndex)))

            if !messageData.isEmpty {
                handleMessage(Data(messageData))
            }
        }
    }

    // Internal for testing (see AuthFlowIntegrationTests, AuthFailureTests)
    func handleMessage(_ data: Data) {
        logger.debug("Parsing message: \(data.count) bytes")
        guard let (requestId, message) = decodeEnvelope(from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                logger.error("Failed to decode: \(str.prefix(200))")
            }
            onEvent?(.message(.error("Failed to decode server message"), requestId: nil))
            return
        }

        switch message {
        case .authRequired:
            if autoRespondToAuthRequired {
                handleAuthRequired()
            } else {
                onEvent?(.message(.authRequired, requestId: nil))
            }
        case .authFailed(let reason):
            logger.error("Auth failed: \(reason)")
            onEvent?(.message(.authFailed(reason), requestId: nil))
            disconnect()
            onEvent?(.disconnected(.authFailed(reason)))
        case .authApproved(let payload):
            logger.info("Auth approved via UI, received token")
            token = payload.token
            onEvent?(.message(.authApproved(payload), requestId: nil))
        case .sessionLocked(let payload):
            logger.warning("Session locked: \(payload.message)")
            onEvent?(.message(.sessionLocked(payload), requestId: nil))
            disconnect()
            onEvent?(.disconnected(.sessionLocked(payload.message)))
        case .info(let info):
            logger.info("Received server info: \(info.appName)")
            onEvent?(.connected)
            onEvent?(.message(.info(info), requestId: requestId))
        case .recordingStopped:
            logger.debug("Recording stop acknowledged")
        case .pong:
            logger.debug("Received pong")
        default:
            onEvent?(.message(message, requestId: requestId))
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

    // MARK: - TLS

    private nonisolated static func makeTLSParameters(expectedFingerprint: String) -> NWParameters {
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

    private func decodeEnvelope(from data: Data) -> (requestId: String?, message: ServerMessage)? {
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(ResponseEnvelope.self, from: data) {
            return (envelope.requestId, envelope.message)
        }

        if let envelope = try? decoder.decode(ServerMessageEnvelope.self, from: data) {
            return (nil, envelope.message)
        }

        if let message = try? decoder.decode(ServerMessage.self, from: data) {
            return (nil, message)
        }

        return nil
    }
}

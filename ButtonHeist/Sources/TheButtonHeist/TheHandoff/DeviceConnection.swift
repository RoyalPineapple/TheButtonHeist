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
public final class DeviceConnection {

    private static let maxBufferSize = 10_000_000 // 10 MB

    private var connection: NWConnection?
    private let device: DiscoveredDevice
    private(set) var token: String?
    private var receiveBuffer = Data()
    var isConnected = false

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((DisconnectReason) -> Void)?
    public var onServerInfo: ((ServerInfo) -> Void)?
    public var onInterface: ((Interface, String?) -> Void)?
    public var onActionResult: ((ActionResult, String?) -> Void)?
    public var onScreen: ((ScreenPayload, String?) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    public var onAuthApproved: ((String?) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?
    public var onInteraction: ((InteractionEvent) -> Void)?

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
        } else {
            parameters = .tcp
        }

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
            startReceiving()
            // Don't fire onConnected yet — wait for auth to complete.
            // onConnected is fired when we receive the server info message (post-auth).
        case .failed(let error):
            logger.error("Connection failed: \(error)")
            isConnected = false
            onDisconnected?(.networkError(error))
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
            onDisconnected?(.networkError(error))
            return
        }

        if let content {
            receiveBuffer.append(content)

            if receiveBuffer.count > Self.maxBufferSize {
                logger.error("Server exceeded max buffer size, disconnecting")
                disconnect()
                onDisconnected?(.bufferOverflow)
                return
            }

            processBuffer()
        }

        if isComplete {
            logger.info("Connection closed by server")
            isConnected = false
            onDisconnected?(.serverClosed)
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

    func handleMessage(_ data: Data) {
        logger.debug("Parsing message: \(data.count) bytes")
        guard let (requestId, message) = decodeEnvelope(from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                logger.error("Failed to decode: \(str.prefix(200))")
            }
            onError?("Failed to decode server message")
            return
        }

        switch message {
        case .authRequired, .authFailed, .authApproved, .sessionLocked:
            handleAuthMessage(message)
        case .recordingStarted, .recordingStopped, .recording, .recordingError:
            handleRecordingMessage(message)
        case .info, .interface, .actionResult, .screen, .error, .pong, .interaction:
            handleResponseMessage(message, requestId: requestId)
        }
    }

    private func handleAuthMessage(_ message: ServerMessage) {
        switch message {
        case .authRequired:
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
        case .authFailed(let reason):
            logger.error("Auth failed: \(reason)")
            onAuthFailed?(reason)
            disconnect()
            onDisconnected?(.authFailed(reason))
        case .authApproved(let payload):
            logger.info("Auth approved via UI, received token")
            token = payload.token
            onAuthApproved?(payload.token)
        case .sessionLocked(let payload):
            logger.warning("Session locked: \(payload.message)")
            onSessionLocked?(payload)
            disconnect()
            onDisconnected?(.sessionLocked(payload.message))
        default:
            break
        }
    }

    private func handleRecordingMessage(_ message: ServerMessage) {
        switch message {
        case .recordingStarted:
            logger.info("Recording started")
            onRecordingStarted?()
        case .recordingStopped:
            logger.debug("Recording stop acknowledged")
        case .recording(let payload):
            logger.debug("Received recording: \(payload.frameCount) frames, \(String(format: "%.1f", payload.duration))s")
            onRecording?(payload)
        case .recordingError(let message):
            logger.error("Recording error: \(message)")
            onRecordingError?(message)
        default:
            break
        }
    }

    private func handleResponseMessage(_ message: ServerMessage, requestId: String?) {
        switch message {
        case .info(let info):
            logger.info("Received server info: \(info.appName)")
            onServerInfo?(info)
            onConnected?()
        case .interface(let payload):
            logger.debug("Received interface: \(payload.elements.count) elements")
            onInterface?(payload, requestId)
        case .actionResult(let result):
            logger.debug("Received action result: \(result.success)")
            onActionResult?(result, requestId)
        case .error(let errorMessage):
            logger.error("Received error: \(errorMessage)")
            onError?(errorMessage)
        case .pong:
            logger.debug("Received pong")
        case .screen(let payload):
            logger.debug("Received screen: \(payload.pngData.count) chars base64")
            onScreen?(payload, requestId)
        case .interaction(let event):
            logger.debug("Received interaction: \(event.result.method.rawValue)")
            onInteraction?(event)
        default:
            break
        }
    }

    // MARK: - TLS

    private static func makeTLSParameters(expectedFingerprint: String) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()

        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
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
            .main
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

import Foundation
import Network
import os.log
import TheScore

private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "connection")

/// Connection client using Network framework.
@MainActor
public final class DeviceConnection {

    private static let maxBufferSize = 10_000_000 // 10 MB

    private var connection: NWConnection?
    private let device: DiscoveredDevice
    private(set) var token: String?
    private var receiveBuffer = Data()
    private var isConnected = false

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onServerInfo: ((ServerInfo) -> Void)?
    public var onInterface: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?
    public var onRecordingStarted: (() -> Void)?
    public var onRecording: ((RecordingPayload) -> Void)?
    public var onRecordingError: ((String) -> Void)?
    public var onError: ((String) -> Void)?
    public var onAuthApproved: ((String) -> Void)?
    public var onSessionLocked: ((SessionLockedPayload) -> Void)?
    public var onAuthFailed: ((String) -> Void)?

    /// When true, send forceSession in the auth handshake to take over an existing session
    public var forceSession: Bool
    /// Driver identity for session locking (set via BUTTONHEIST_DRIVER_ID)
    public var driverId: String?

    public init(device: DiscoveredDevice, token: String? = nil, forceSession: Bool = false, driverId: String? = nil) {
        self.device = device
        self.token = token
        self.forceSession = forceSession
        self.driverId = driverId
    }

    public func connect() {
        logger.info("Connecting to \(self.device.name)...")

        let conn = NWConnection(to: device.endpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
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

    public func send(_ message: ClientMessage) {
        guard let connection, isConnected else { return }
        guard var data = try? JSONEncoder().encode(message) else { return }
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
            onDisconnected?(error)
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
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    logger.error("Receive error: \(error)")
                    self.isConnected = false
                    self.onDisconnected?(error)
                    return
                }

                if let content {
                    self.receiveBuffer.append(content)

                    if self.receiveBuffer.count > Self.maxBufferSize {
                        logger.error("Server exceeded max buffer size, disconnecting")
                        self.disconnect()
                        self.onDisconnected?(nil)
                        return
                    }

                    self.processBuffer()
                }

                if isComplete {
                    logger.info("Connection closed by server")
                    self.isConnected = false
                    self.onDisconnected?(nil)
                } else {
                    self.receiveNext(connection: connection)
                }
            }
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

    private func handleMessage(_ data: Data) {
        logger.debug("Parsing message: \(data.count) bytes")
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                logger.error("Failed to decode: \(str.prefix(200))")
            }
            return
        }

        switch message {
        case .authRequired:
            logger.info("Auth required, sending token")
            // Send token if available, otherwise send empty token to request UI approval
            send(.authenticate(AuthenticatePayload(
                token: token ?? "",
                forceSession: forceSession ? true : nil,
                driverId: driverId
            )))
        case .authFailed(let reason):
            logger.error("Auth failed: \(reason)")
            onAuthFailed?(reason)
            disconnect()
            onDisconnected?(nil)
        case .authApproved(let payload):
            logger.info("Auth approved via UI, received token")
            token = payload.token
            onAuthApproved?(payload.token)
        case .info(let info):
            logger.info("Received server info: \(info.appName)")
            onServerInfo?(info)
            onConnected?()
        case .interface(let payload):
            logger.debug("Received interface: \(payload.elements.count) elements")
            onInterface?(payload)
        case .actionResult(let result):
            logger.debug("Received action result: \(result.success)")
            onActionResult?(result)
        case .error(let errorMessage):
            logger.error("Received error: \(errorMessage)")
            onError?(errorMessage)
        case .pong:
            logger.debug("Received pong")
        case .screen(let payload):
            logger.debug("Received screen: \(payload.pngData.count) chars base64")
            onScreen?(payload)
        case .sessionLocked(let payload):
            logger.warning("Session locked: \(payload.message)")
            onSessionLocked?(payload)
            disconnect()
            onDisconnected?(nil)
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
        }
    }
}

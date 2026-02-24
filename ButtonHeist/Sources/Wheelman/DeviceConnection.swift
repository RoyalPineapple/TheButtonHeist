import Foundation
import Network
import TheGoods

private func debug(_ message: String) {
    fputs("[DeviceConnection] \(message)\n", stderr)
}

/// Connection client using Network framework.
@MainActor
public final class DeviceConnection {

    private static let maxBufferSize = 10_000_000 // 10 MB

    private var connection: NWConnection?
    private let device: DiscoveredDevice
    private let token: String?
    private var receiveBuffer = Data()
    private var isConnected = false

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((Error?) -> Void)?
    public var onServerInfo: ((ServerInfo) -> Void)?
    public var onInterface: ((Interface) -> Void)?
    public var onActionResult: ((ActionResult) -> Void)?
    public var onScreen: ((ScreenPayload) -> Void)?
    public var onError: ((String) -> Void)?

    public init(device: DiscoveredDevice, token: String? = nil) {
        self.device = device
        self.token = token
    }

    public func connect() {
        debug("Connecting to \(device.name)...")

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
                debug("Send error: \(error)")
            }
        })
    }

    // MARK: - Private

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            debug("Connected")
            isConnected = true
            onConnected?()
            startReceiving()
        case .failed(let error):
            debug("Connection failed: \(error)")
            isConnected = false
            onDisconnected?(error)
        case .cancelled:
            debug("Connection cancelled")
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
                    debug("Receive error: \(error)")
                    self.isConnected = false
                    self.onDisconnected?(error)
                    return
                }

                if let content {
                    self.receiveBuffer.append(content)

                    if self.receiveBuffer.count > Self.maxBufferSize {
                        debug("Server exceeded max buffer size, disconnecting")
                        self.disconnect()
                        self.onDisconnected?(nil)
                        return
                    }

                    self.processBuffer()
                }

                if isComplete {
                    debug("Connection closed by server")
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
        debug("Parsing message: \(data.count) bytes")
        guard let message = try? JSONDecoder().decode(ServerMessage.self, from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                debug("Failed to decode: \(str.prefix(200))")
            }
            return
        }

        switch message {
        case .authRequired:
            debug("Auth required, sending token")
            if let token {
                send(.authenticate(AuthenticatePayload(token: token)))
            } else {
                debug("No token available, disconnecting")
                disconnect()
                onDisconnected?(nil)
            }
        case .authFailed(let reason):
            debug("Auth failed: \(reason)")
            disconnect()
            onDisconnected?(nil)
        case .info(let info):
            debug("Received server info: \(info.appName)")
            onServerInfo?(info)
        case .interface(let payload):
            debug("Received interface: \(payload.elements.count) elements")
            onInterface?(payload)
        case .actionResult(let result):
            debug("Received action result: \(result.success)")
            onActionResult?(result)
        case .error(let errorMessage):
            debug("Received error: \(errorMessage)")
            onError?(errorMessage)
        case .pong:
            debug("Received pong")
        case .screen(let payload):
            debug("Received screen: \(payload.pngData.count) chars base64")
            onScreen?(payload)
        }
    }
}

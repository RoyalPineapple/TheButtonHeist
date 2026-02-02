import Foundation
import Network
import AccraCore

// Debug helper that writes to stderr (unbuffered)
private func debug(_ message: String) {
    fputs("[DeviceConnection] \(message)\n", stderr)
}

/// Simple socket-based connection client
/// Uses BSD sockets instead of NWConnection for reliability
@MainActor
final class DeviceConnection {

    private var socketFD: Int32 = -1
    private var readQueue: DispatchQueue?
    private let device: DiscoveredDevice
    private var receiveBuffer = Data()
    private var isConnected = false

    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onServerInfo: ((ServerInfo) -> Void)?
    var onHierarchy: ((HierarchyPayload) -> Void)?
    var onActionResult: ((ActionResult) -> Void)?
    var onError: ((String) -> Void)?

    init(device: DiscoveredDevice) {
        self.device = device
    }

    func connect() {
        // Resolve the Bonjour service to get port, then connect to localhost
        if case let .service(name, type, domain, _) = device.endpoint {
            debug("Resolving service: \(name).\(type)\(domain)")
            resolveAndConnect(name: name, type: type, domain: domain)
        } else {
            debug("Non-service endpoint not supported")
            onDisconnected?(NSError(domain: "DeviceConnection", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Only service endpoints are supported"
            ]))
        }
    }

    private func resolveAndConnect(name: String, type: String, domain: String) {
        // Use dns-sd style resolution via NWConnection
        // First, we'll use a connection with a short timeout to resolve and extract port
        let resolverConnection = NWConnection(to: device.endpoint, using: .tcp)

        var resolved = false
        resolverConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !resolved else { return }

            switch state {
            case .ready:
                resolved = true
                // Extract the resolved endpoint
                if let path = resolverConnection.currentPath,
                   let remoteEndpoint = path.remoteEndpoint,
                   case let .hostPort(host, port) = remoteEndpoint {
                    debug("Resolved to: \(host):\(port)")
                    resolverConnection.cancel()

                    // Connect via BSD sockets to localhost:port
                    DispatchQueue.main.async {
                        self.connectSocket(port: port.rawValue)
                    }
                } else {
                    debug("Could not extract remote endpoint")
                    resolverConnection.cancel()
                    DispatchQueue.main.async {
                        self.onDisconnected?(NSError(domain: "DeviceConnection", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Could not resolve service endpoint"
                        ]))
                    }
                }
            case .failed(let error):
                resolved = true
                debug("Resolver failed: \(error)")
                resolverConnection.cancel()
                DispatchQueue.main.async {
                    self.onDisconnected?(error)
                }
            default:
                break
            }
        }

        resolverConnection.start(queue: .global())
    }

    private func connectSocket(port: UInt16) {
        debug("Connecting to localhost:\(port) via BSD socket...")

        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            debug("Failed to create socket: \(String(cString: strerror(errno)))")
            onDisconnected?(NSError(domain: "DeviceConnection", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create socket"
            ]))
            return
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard connectResult >= 0 else {
            debug("Failed to connect: \(String(cString: strerror(errno)))")
            close(socketFD)
            socketFD = -1
            onDisconnected?(NSError(domain: "DeviceConnection", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to connect"
            ]))
            return
        }

        debug("Socket connected!")
        isConnected = true
        onConnected?()

        // Start reading
        readQueue = DispatchQueue(label: "com.accra.client.read")
        readQueue?.async { [weak self] in
            self?.readLoop()
        }
    }

    func disconnect() {
        isConnected = false
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        readQueue = nil
    }

    func send(_ message: ClientMessage) {
        guard socketFD >= 0 else { return }
        guard var data = try? JSONEncoder().encode(message) else { return }
        data.append(0x0A)  // newline delimiter

        data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(socketFD, buffer.baseAddress!.advanced(by: sent), data.count - sent, 0)
                if n < 0 {
                    debug("Send error: \(String(cString: strerror(errno)))")
                    return
                }
                sent += n
            }
        }
    }

    private func readLoop() {
        var buffer = [UInt8](repeating: 0, count: 8192)

        while isConnected && socketFD >= 0 {
            let bytesRead = recv(socketFD, &buffer, buffer.count, 0)

            if bytesRead <= 0 {
                if bytesRead < 0 && errno == EINTR { continue }
                debug("Connection closed (bytesRead=\(bytesRead))")
                DispatchQueue.main.async { [weak self] in
                    self?.isConnected = false
                    self?.onDisconnected?(nil)
                }
                break
            }

            debug("Received \(bytesRead) bytes")

            let receivedData = Data(buffer.prefix(bytesRead))

            DispatchQueue.main.async { [weak self] in
                self?.receiveBuffer.append(receivedData)
                self?.processBuffer()
            }
        }
    }

    private func processBuffer() {
        // Look for newline-delimited JSON messages
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
        case .info(let info):
            debug("Received server info: \(info.appName)")
            onServerInfo?(info)
        case .hierarchy(let payload):
            debug("Received hierarchy: \(payload.elements.count) elements")
            onHierarchy?(payload)
        case .actionResult(let result):
            debug("Received action result: \(result.success)")
            onActionResult?(result)
        case .error(let errorMessage):
            debug("Received error: \(errorMessage)")
            onError?(errorMessage)
        case .pong:
            debug("Received pong")
        }
    }
}

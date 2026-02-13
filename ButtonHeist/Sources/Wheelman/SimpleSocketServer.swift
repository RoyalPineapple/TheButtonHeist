import Foundation
import Network

/// TCP server using Network framework.
/// Manages connections, newline-delimited message framing, and broadcasting.
public final class SimpleSocketServer: @unchecked Sendable {
    public typealias DataHandler = @Sendable (Data, @escaping @Sendable (Data) -> Void) -> Void

    // All mutable state protected by this lock
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var clientCounter = 0
    private var _listeningPort: UInt16 = 0

    public var listeningPort: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return _listeningPort
    }

    public var onClientConnected: (@Sendable (Int) -> Void)?
    public var onClientDisconnected: (@Sendable (Int) -> Void)?
    public var onDataReceived: DataHandler?

    private let queue = DispatchQueue(label: "com.buttonheist.wheelman.server")

    public init() {}

    deinit {
        stop()
    }

    /// Start the server on the specified port.
    /// - Parameter port: Port to listen on (0 = any available)
    /// - Returns: Actual port number bound
    public func start(port: UInt16 = 0) throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv6(.any),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )

        let newListener = try NWListener(using: parameters)

        let readySemaphore = DispatchSemaphore(value: 0)

        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let actualPort = self?.listener?.port?.rawValue {
                    self?.lock.lock()
                    self?._listeningPort = actualPort
                    self?.lock.unlock()
                    NSLog("[SimpleSocketServer] Listening on port \(actualPort)")
                }
                readySemaphore.signal()
            case .failed(let error):
                NSLog("[SimpleSocketServer] Listener failed: \(error)")
                readySemaphore.signal()
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        self.listener = newListener
        newListener.start(queue: queue)

        // Wait for the listener to become ready (up to 5 seconds)
        _ = readySemaphore.wait(timeout: .now() + 5)

        lock.lock()
        if let actualPort = newListener.port?.rawValue {
            _listeningPort = actualPort
        }
        let result = _listeningPort
        lock.unlock()

        return result
    }

    public func stop() {
        lock.lock()
        let conns = connections
        connections.removeAll()
        let l = listener
        listener = nil
        lock.unlock()

        for (_, conn) in conns {
            conn.cancel()
        }
        l?.cancel()
        NSLog("[SimpleSocketServer] Server stopped")
    }

    public func send(_ data: Data, to clientId: Int) {
        lock.lock()
        guard let connection = connections[clientId] else {
            lock.unlock()
            return
        }
        lock.unlock()

        var dataToSend = data
        if !dataToSend.hasSuffix(Data([0x0A])) {
            dataToSend.append(0x0A)
        }

        connection.send(content: dataToSend, completion: .contentProcessed { error in
            if let error {
                NSLog("[SimpleSocketServer] Send error to client \(clientId): \(error)")
            }
        })
    }

    public func broadcastToAll(_ data: Data) {
        lock.lock()
        let clientIds = Array(connections.keys)
        lock.unlock()

        for clientId in clientIds {
            send(data, to: clientId)
        }
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        lock.lock()
        clientCounter += 1
        let clientId = clientCounter
        connections[clientId] = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("[SimpleSocketServer] Client \(clientId) connected")
                self?.onClientConnected?(clientId)
            case .failed(let error):
                NSLog("[SimpleSocketServer] Client \(clientId) failed: \(error)")
                self?.removeClient(clientId)
            case .cancelled:
                self?.removeClient(clientId)
            default:
                break
            }
        }

        connection.start(queue: queue)
        startReceiving(clientId: clientId, connection: connection)
    }

    private func removeClient(_ clientId: Int) {
        lock.lock()
        let conn = connections.removeValue(forKey: clientId)
        lock.unlock()

        conn?.cancel()
        self.onClientDisconnected?(clientId)
    }

    private func startReceiving(clientId: Int, connection: NWConnection) {
        receiveNextChunk(clientId: clientId, connection: connection, buffer: Data())
    }

    private func receiveNextChunk(clientId: Int, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("[SimpleSocketServer] Receive error from client \(clientId): \(error)")
                self.removeClient(clientId)
                return
            }

            var messageBuffer = buffer
            if let content {
                messageBuffer.append(content)
            }

            // Process newline-delimited messages
            while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) {
                let messageData = Data(messageBuffer.prefix(upTo: newlineIndex))
                messageBuffer = Data(messageBuffer.suffix(from: messageBuffer.index(after: newlineIndex)))

                if !messageData.isEmpty {
                    self.onDataReceived?(messageData) { response in
                        self.send(response, to: clientId)
                    }
                }
            }

            if isComplete {
                self.removeClient(clientId)
            } else {
                self.receiveNextChunk(clientId: clientId, connection: connection, buffer: messageBuffer)
            }
        }
    }
}

extension Data {
    func hasSuffix(_ suffixData: Data) -> Bool {
        guard count >= suffixData.count else { return false }
        return self.suffix(suffixData.count) == suffixData
    }
}

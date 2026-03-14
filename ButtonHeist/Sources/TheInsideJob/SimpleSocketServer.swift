import Foundation
import Network
import TheScore
import os

/// TCP server using Network framework.
/// Manages connections, newline-delimited message framing, and broadcasting.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = Logger(subsystem: "com.buttonheist.thewheelman", category: "server")

public actor SimpleSocketServer {
    public typealias DataHandler = @Sendable (Int, Data, @escaping @Sendable (Data) -> Void) -> Void

    private static let maxBufferSize = 10_000_000 // 10 MB
    private static let maxConnections = 5
    private static let maxMessagesPerSecond = 30

    // Actor-isolated mutable state — no locks needed
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]
    private var clientCounter = 0
    private var _listeningPort: UInt16 = 0
    private var authenticatedClients: Set<Int> = []
    private var clientMessageTimestamps: [Int: [Date]] = [:]

    private let _syncListeningPort = OSAllocatedUnfairLock<UInt16>(initialState: 0)

    public nonisolated var listeningPort: UInt16 {
        _syncListeningPort.withLock { $0 }
    }

    // MARK: - Callbacks

    public struct Callbacks: Sendable {
        public var onClientConnected: (@Sendable (Int) -> Void)?
        public var onClientDisconnected: (@Sendable (Int) -> Void)?
        public var onDataReceived: DataHandler?
        public var onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?

        public init(
            onClientConnected: (@Sendable (Int) -> Void)? = nil,
            onClientDisconnected: (@Sendable (Int) -> Void)? = nil,
            onDataReceived: DataHandler? = nil,
            onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)? = nil
        ) {
            self.onClientConnected = onClientConnected
            self.onClientDisconnected = onClientDisconnected
            self.onDataReceived = onDataReceived
            self.onUnauthenticatedData = onUnauthenticatedData
        }
    }

    private var callbacks = Callbacks()

    /// Connection scopes the server will accept. Connections from disallowed scopes are rejected immediately.
    private let allowedScopes: Set<ConnectionScope>

    private let queue = DispatchQueue(label: "com.buttonheist.thewheelman.server")

    public init(allowedScopes: Set<ConnectionScope> = ConnectionScope.all) {
        self.allowedScopes = allowedScopes
    }

    public func configure(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    // MARK: - Public API (async, actor-isolated)

    /// Start the server on the specified port (async version).
    /// Uses structured concurrency to wait for the listener to become ready.
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only (simulator builds)
    ///   - callbacks: Optional callbacks to install before starting
    /// - Returns: Actual port number bound
    public func startAsync(
        port: UInt16 = 0,
        bindToLoopback: Bool = false,
        tlsParameters: NWParameters? = nil,
        callbacks: Callbacks? = nil
    ) async throws -> UInt16 {
        if let callbacks { self.callbacks = callbacks }
        let parameters: NWParameters = tlsParameters ?? NWParameters.tcp
        if tlsParameters != nil {
            logger.info("TLS configured for server")
        }
        let host: NWEndpoint.Host = bindToLoopback ? .ipv6(.loopback) : .ipv6(.any)
        parameters.requiredLocalEndpoint = .hostPort(
            host: host,
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )

        let newListener = try NWListener(using: parameters)

        let actualPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    if let port = newListener.port?.rawValue {
                        logger.info("Listening on port \(port)")
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: ServerError.failedToBindPort)
                    }
                case .failed(let error):
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    logger.error("Listener failed: \(error)")
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                Task { await self.handleNewConnection(connection) }
            }

            newListener.start(queue: self.queue)
        }

        self.listener = newListener
        self._listeningPort = actualPort
        self._syncListeningPort.withLock { $0 = actualPort }

        return actualPort
    }

    /// Stop the server (actor-isolated).
    private func _stop() {
        let conns = connections
        connections.removeAll()
        authenticatedClients.removeAll()
        clientMessageTimestamps.removeAll()
        let l = listener
        listener = nil

        for (_, conn) in conns {
            conn.cancel()
        }
        l?.cancel()
        logger.info("Server stopped")
    }

    /// Send data to a specific client (actor-isolated).
    private func _send(_ data: Data, to clientId: Int) {
        guard let connection = connections[clientId] else { return }

        var dataToSend = data
        if !dataToSend.hasSuffix(Data([0x0A])) {
            dataToSend.append(0x0A)
        }

        connection.send(content: dataToSend, completion: .contentProcessed { error in
            if let error {
                logger.error("Send error to client \(clientId): \(error)")
            }
        })
    }

    /// Remove a client and clean up (actor-isolated).
    private func _disconnect(clientId: Int) {
        removeClient(clientId)
    }

    /// Mark a client as authenticated (actor-isolated).
    private func _markAuthenticated(_ clientId: Int) {
        authenticatedClients.insert(clientId)
    }

    /// Check if a client is authenticated (actor-isolated).
    private func _isAuthenticated(_ clientId: Int) -> Bool {
        authenticatedClients.contains(clientId)
    }

    /// Broadcast data to all authenticated clients (actor-isolated).
    private func _broadcastToAll(_ data: Data) {
        let clientIds = Array(connections.keys).filter { authenticatedClients.contains($0) }
        for clientId in clientIds {
            _send(data, to: clientId)
        }
    }

    // MARK: - Public API (nonisolated, for synchronous callers)
    // These dispatch to the actor via Task for fire-and-forget operations.

    /// Start the server on the specified port (synchronous version).
    /// Bridges to async start using a semaphore (acceptable for one-time startup).
    /// - Parameters:
    ///   - port: Port to listen on (0 = any available)
    ///   - bindToLoopback: If true, bind to loopback only (simulator builds)
    /// - Returns: Actual port number bound
    nonisolated public func start(port: UInt16 = 0, bindToLoopback: Bool = false, tlsParameters: NWParameters? = nil) throws -> UInt16 {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = OSAllocatedUnfairLock<Result<UInt16, Error>?>(initialState: nil)
        let server = self
        let portValue = port
        let loopback = bindToLoopback
        let params = tlsParameters
        Task.detached { @Sendable in
            do {
                let port = try await server.startAsync(port: portValue, bindToLoopback: loopback, tlsParameters: params)
                resultBox.withLock { $0 = .success(port) }
            } catch {
                resultBox.withLock { $0 = .failure(error) }
            }
            semaphore.signal()
        }
        semaphore.wait()
        switch resultBox.withLock({ $0 })! {
        case .success(let port): return port
        case .failure(let error): throw error
        }
    }

    /// Stop the server. Dispatches to actor isolation.
    nonisolated public func stop() {
        Task { await self._stop() }
    }

    /// Send data to a specific client. Dispatches to actor isolation.
    nonisolated public func send(_ data: Data, to clientId: Int) {
        Task { await self._send(data, to: clientId) }
    }

    /// Disconnect a client. Dispatches to actor isolation.
    nonisolated public func disconnect(clientId: Int) {
        Task { await self._disconnect(clientId: clientId) }
    }

    /// Mark a client as authenticated. Dispatches to actor isolation.
    nonisolated public func markAuthenticated(_ clientId: Int) {
        Task { await self._markAuthenticated(clientId) }
    }

    /// Check if a client is authenticated.
    public func isAuthenticated(_ clientId: Int) -> Bool {
        _isAuthenticated(clientId)
    }

    /// Broadcast data to all authenticated clients. Dispatches to actor isolation.
    nonisolated public func broadcastToAll(_ data: Data) {
        Task { await self._broadcastToAll(data) }
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let currentCount = connections.count

        if currentCount >= Self.maxConnections {
            logger.warning("Max connections (\(Self.maxConnections)) reached, rejecting")
            connection.cancel()
            return
        }

        clientCounter += 1
        let clientId = clientCounter
        connections[clientId] = connection
        let scopeFilter = allowedScopes != ConnectionScope.all ? allowedScopes : nil

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // Scope filtering at .ready: interface info is now available for precise USB detection
                if let scopeFilter {
                    guard let host = Self.extractRemoteHost(from: connection) else {
                        logger.warning("Cannot classify connection endpoint, rejecting (scope filter active)")
                        Task { await self.removeClient(clientId) }
                        return
                    }
                    let interfaces = connection.currentPath?.availableInterfaces ?? []
                    let scope = ConnectionScope.classify(host: host, interfaces: interfaces)
                    let hostDescription = "\(host)"
                    let interfaceNames = interfaces.map(\.name).joined(separator: ", ")
                    if !scopeFilter.contains(scope) {
                        logger.warning("Rejecting \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
                        Task { await self.removeClient(clientId) }
                        return
                    }
                    logger.info("Accepted \(scope.rawValue) connection from \(hostDescription) via [\(interfaceNames)]")
                }
                logger.info("Client \(clientId) connected")
                Task { await self.notifyClientConnected(clientId) }
            case .failed(let error):
                logger.error("Client \(clientId) failed: \(error)")
                Task { await self.removeClient(clientId) }
            case .cancelled:
                Task { await self.removeClient(clientId) }
            default:
                break
            }
        }

        connection.start(queue: queue)
        startReceiving(clientId: clientId, connection: connection)
    }

    private func notifyClientConnected(_ clientId: Int) {
        callbacks.onClientConnected?(clientId)
    }

    private func removeClient(_ clientId: Int) {
        let conn = connections.removeValue(forKey: clientId)
        authenticatedClients.remove(clientId)
        clientMessageTimestamps.removeValue(forKey: clientId)

        conn?.cancel()
        callbacks.onClientDisconnected?(clientId)
    }

    private func isRateLimited(_ clientId: Int) -> Bool {
        let now = Date()
        var timestamps = clientMessageTimestamps[clientId] ?? []
        timestamps = timestamps.filter { now.timeIntervalSince($0) < 1.0 }
        let limited = timestamps.count >= Self.maxMessagesPerSecond
        if !limited {
            timestamps.append(now)
        }
        clientMessageTimestamps[clientId] = timestamps
        return limited
    }

    private func startReceiving(clientId: Int, connection: NWConnection) {
        receiveNextChunk(clientId: clientId, connection: connection, buffer: Data())
    }

    private func receiveNextChunk(clientId: Int, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            Task { await self.handleReceivedData(
                clientId: clientId,
                connection: connection,
                content: content,
                isComplete: isComplete,
                error: error,
                buffer: buffer
            )}
        }
    }

    /// Process received data within actor isolation.
    private func handleReceivedData(
        clientId: Int,
        connection: NWConnection,
        content: Data?,
        isComplete: Bool,
        error: NWError?,
        buffer: Data
    ) {
        if let error {
            logger.error("Receive error from client \(clientId): \(error)")
            removeClient(clientId)
            return
        }

        var messageBuffer = buffer
        if let content {
            messageBuffer.append(content)
        }

        if messageBuffer.count > Self.maxBufferSize {
            logger.error("Client \(clientId) exceeded max buffer size, disconnecting")
            removeClient(clientId)
            return
        }

        // Process newline-delimited messages
        while let newlineIndex = messageBuffer.firstIndex(of: 0x0A) {
            let messageData = Data(messageBuffer.prefix(upTo: newlineIndex))
            messageBuffer = Data(messageBuffer.suffix(from: messageBuffer.index(after: newlineIndex)))

            if !messageData.isEmpty {
                if _isAuthenticated(clientId) {
                    if isRateLimited(clientId) {
                        logger.warning("Client \(clientId) rate limited, dropping message")
                    } else {
                        callbacks.onDataReceived?(clientId, messageData) { [weak self] response in
                            guard let self else { return }
                            Task { await self._send(response, to: clientId) }
                        }
                    }
                } else {
                    if isRateLimited(clientId) {
                        logger.warning("Unauthenticated client \(clientId) rate limited, dropping message")
                    } else {
                        callbacks.onUnauthenticatedData?(clientId, messageData) { [weak self] response in
                            guard let self else { return }
                            Task { await self._send(response, to: clientId) }
                        }
                    }
                }
            }
        }

        if isComplete {
            removeClient(clientId)
        } else {
            receiveNextChunk(clientId: clientId, connection: connection, buffer: messageBuffer)
        }
    }

    /// Extract the remote host from an NWConnection using typed Network framework values.
    /// Checks the connection endpoint directly (always available), with currentPath as fallback.
    nonisolated private static func extractRemoteHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case .hostPort(let host, _) = connection.endpoint {
            return host
        }
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
            return host
        }
        return nil
    }

    // MARK: - Errors

    enum ServerError: Error, LocalizedError {
        case failedToBindPort

        var errorDescription: String? {
            switch self {
            case .failedToBindPort:
                return "Server failed to bind to a port"
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

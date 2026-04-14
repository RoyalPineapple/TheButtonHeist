import Foundation
import Network
import os

import TheScore

/// TCP server using Network framework.
/// Manages connections, newline-delimited message framing, and broadcasting.
/// Actor-isolated — all mutable state is protected by Swift concurrency.
private let logger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")

public actor SimpleSocketServer {
    public typealias DataHandler = @Sendable (Int, Data, @escaping @Sendable (Data) -> Void) -> Void

    private static let maxBufferSize = 10_000_000 // 10 MB
    private static let maxConnections = 5
    private static let maxMessagesPerSecond = 30

    // MARK: - State Machines

    private enum ServerPhase {
        case stopped
        case listening(listener: NWListener, port: UInt16)
    }

    private enum ClientPhase {
        case unauthenticated(connection: NWConnection, timestamps: [Date])
        case authenticated(connection: NWConnection, timestamps: [Date])

        var connection: NWConnection {
            switch self {
            case .unauthenticated(let connection, _),
                 .authenticated(let connection, _):
                return connection
            }
        }

        var timestamps: [Date] {
            get {
                switch self {
                case .unauthenticated(_, let timestamps),
                     .authenticated(_, let timestamps):
                    return timestamps
                }
            }
            set {
                switch self {
                case .unauthenticated(let connection, _):
                    self = .unauthenticated(connection: connection, timestamps: newValue)
                case .authenticated(let connection, _):
                    self = .authenticated(connection: connection, timestamps: newValue)
                }
            }
        }

        var isAuthenticated: Bool {
            if case .authenticated = self { return true }
            return false
        }
    }

    // MARK: - Actor-isolated mutable state

    private static let authDeadlineSeconds: UInt64 = 10

    private var serverPhase: ServerPhase = .stopped
    private var clients: [Int: ClientPhase] = [:]
    private var clientCounter = 0
    private var authDeadlineTasks: [Int: Task<Void, Never>] = [:]

    private let _syncListeningPort = OSAllocatedUnfairLock<UInt16>(initialState: 0)

    public nonisolated var listeningPort: UInt16 {
        _syncListeningPort.withLock { $0 }
    }

    // MARK: - Callbacks

    public struct Callbacks: Sendable {
        public var onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)?
        public var onClientDisconnected: (@Sendable (Int) -> Void)?
        public var onDataReceived: DataHandler?
        public var onUnauthenticatedData: (@Sendable (_ clientId: Int, _ data: Data, _ respond: @escaping @Sendable (Data) -> Void) -> Void)?

        public init(
            onClientConnected: (@Sendable (_ clientId: Int, _ remoteAddress: String?) -> Void)? = nil,
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

    private let queue = DispatchQueue(label: "com.buttonheist.thehandoff.server")

    public init(allowedScopes: Set<ConnectionScope> = ConnectionScope.all) {
        self.allowedScopes = allowedScopes
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
        guard case .stopped = serverPhase else {
            throw ServerError.alreadyRunning
        }

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
                    newListener.cancel()
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

        self.serverPhase = .listening(listener: newListener, port: actualPort)
        self._syncListeningPort.withLock { $0 = actualPort }

        return actualPort
    }

    /// Stop the server (actor-isolated).
    private func _stop() {
        guard case .listening(let listener, _) = serverPhase else { return }

        let allClients = clients
        clients.removeAll()
        for task in authDeadlineTasks.values { task.cancel() }
        authDeadlineTasks.removeAll()
        serverPhase = .stopped
        _syncListeningPort.withLock { $0 = 0 }

        for (_, phase) in allClients {
            phase.connection.cancel()
        }
        listener.cancel()
        logger.info("Server stopped")
    }

    /// Send data to a specific client (actor-isolated).
    private func _send(_ data: Data, to clientId: Int) {
        guard let phase = clients[clientId] else { return }

        var dataToSend = data
        if !dataToSend.hasSuffix(Data([0x0A])) {
            dataToSend.append(0x0A)
        }

        phase.connection.send(content: dataToSend, completion: .contentProcessed { error in
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
        guard case .unauthenticated(let connection, let timestamps) = clients[clientId] else { return }
        clients[clientId] = .authenticated(connection: connection, timestamps: timestamps)
        authDeadlineTasks[clientId]?.cancel()
        authDeadlineTasks[clientId] = nil
    }

    /// Check if a client is authenticated (actor-isolated).
    private func _isAuthenticated(_ clientId: Int) -> Bool {
        clients[clientId]?.isAuthenticated ?? false
    }

    /// Broadcast data to all authenticated clients (actor-isolated).
    private func _broadcastToAll(_ data: Data) {
        for (clientId, phase) in clients where phase.isAuthenticated {
            _send(data, to: clientId)
        }
    }

    // MARK: - Synchronous start bridge

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
        guard let result = resultBox.withLock({ $0 }) else {
            throw ServerError.failedToBindPort
        }
        switch result {
        case .success(let port): return port
        case .failure(let error): throw error
        }
    }

    /// Stop the server.
    public func stop() {
        _stop()
    }

    /// Send data to a specific client.
    public func send(_ data: Data, to clientId: Int) {
        _send(data, to: clientId)
    }

    /// Disconnect a client.
    public func disconnect(clientId: Int) {
        _disconnect(clientId: clientId)
    }

    /// Mark a client as authenticated.
    public func markAuthenticated(_ clientId: Int) {
        _markAuthenticated(clientId)
    }

    /// Check if a client is authenticated.
    public func isAuthenticated(_ clientId: Int) -> Bool {
        _isAuthenticated(clientId)
    }

    /// Broadcast data to all authenticated clients.
    public func broadcastToAll(_ data: Data) {
        _broadcastToAll(data)
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let currentCount = clients.count

        if currentCount >= Self.maxConnections {
            logger.warning("Max connections (\(Self.maxConnections)) reached, rejecting")
            connection.cancel()
            return
        }

        clientCounter += 1
        let clientId = clientCounter
        clients[clientId] = .unauthenticated(connection: connection, timestamps: [])
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
                let remoteAddress = Self.extractRemoteHost(from: connection).map { "\($0)" }
                logger.info("Client \(clientId) connected")
                Task { await self.notifyClientConnected(clientId, address: remoteAddress) }
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
        scheduleAuthDeadline(for: clientId)
    }

    private func scheduleAuthDeadline(for clientId: Int) {
        authDeadlineTasks[clientId] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.authDeadlineSeconds))
            } catch {
                return
            }
            guard let self else { return }
            if let phase = await self.clients[clientId], !phase.isAuthenticated {
                logger.warning("Client \(clientId) did not authenticate within \(Self.authDeadlineSeconds)s deadline")
                await self.removeClient(clientId)
            }
        }
    }

    private func notifyClientConnected(_ clientId: Int, address: String?) {
        callbacks.onClientConnected?(clientId, address)
    }

    private func notifyClientDisconnected(_ clientId: Int) {
        callbacks.onClientDisconnected?(clientId)
    }

    private func removeClient(_ clientId: Int) {
        guard let phase = clients.removeValue(forKey: clientId) else { return }
        authDeadlineTasks[clientId]?.cancel()
        authDeadlineTasks[clientId] = nil
        phase.connection.cancel()
        notifyClientDisconnected(clientId)
    }

    // ClientPhase is a value type — copy, mutate timestamps, write back.
    private func isRateLimited(_ clientId: Int) -> Bool {
        guard var phase = clients[clientId] else { return true }
        let now = Date()
        var timestamps = phase.timestamps.filter { now.timeIntervalSince($0) < 1.0 }
        let limited = timestamps.count >= Self.maxMessagesPerSecond
        if !limited {
            timestamps.append(now)
        }
        phase.timestamps = timestamps
        clients[clientId] = phase
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

    enum ServerError: Error, LocalizedError, Equatable {
        case failedToBindPort
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .failedToBindPort:
                return "Server failed to bind to a port"
            case .alreadyRunning:
                return "Server is already running"
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

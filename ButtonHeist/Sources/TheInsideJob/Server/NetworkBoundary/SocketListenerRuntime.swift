import Foundation
import Network
import os

import TheScore

private let listenerLogger = ButtonHeistLog.logger(.handoff(.server))

struct SocketListenerGeneration: Equatable, Sendable {
    let attemptID: UUID
    let runtime: SocketListenerRuntime

    func own(_ connection: NWConnection) -> Bool {
        runtime.own(connection)
    }

    @discardableResult
    func cancelIfOwned(_ connection: NWConnection) -> Bool {
        runtime.cancelIfOwned(connection)
    }

    func transferToClientRegistry(_ connection: NWConnection) -> Bool {
        runtime.transferToClientRegistry(connection)
    }

    #if DEBUG
    var pendingConnectionCountForTesting: Int {
        runtime.pendingConnectionCountForTesting
    }

    func waitUntilStoppedForTesting() async {
        await runtime.waitUntilStoppedForTesting()
    }
    #endif
}

private final class PendingSocketConnections: Sendable {
    private enum Phase {
        case accepting([ObjectIdentifier: NWConnection])
        case stopped
    }

    private let phase = OSAllocatedUnfairLock<Phase>(initialState: .accepting([:]))

    func own(_ connection: NWConnection) -> Bool {
        let accepted = phase.withLock { phase -> Bool in
            guard case .accepting(var connections) = phase else { return false }
            connections[ObjectIdentifier(connection)] = connection
            phase = .accepting(connections)
            return true
        }
        if !accepted {
            connection.cancel()
        }
        return accepted
    }

    func transfer(_ connection: NWConnection) -> Bool {
        phase.withLock { phase in
            guard case .accepting(var connections) = phase else { return false }
            let transferred = connections.removeValue(forKey: ObjectIdentifier(connection)) != nil
            phase = .accepting(connections)
            return transferred
        }
    }

    @discardableResult
    func cancelIfOwned(_ connection: NWConnection) -> Bool {
        let ownedConnection = phase.withLock { phase -> NWConnection? in
            guard case .accepting(var connections) = phase else { return nil }
            let owned = connections.removeValue(forKey: ObjectIdentifier(connection))
            phase = .accepting(connections)
            return owned
        }
        ownedConnection?.cancel()
        return ownedConnection != nil
    }

    func cancelAll() {
        let connections = phase.withLock { phase -> [NWConnection] in
            guard case .accepting(let connections) = phase else { return [] }
            phase = .stopped
            return Array(connections.values)
        }
        connections.forEach { $0.cancel() }
    }

    #if DEBUG
    var count: Int {
        phase.withLock { phase in
            guard case .accepting(let connections) = phase else { return 0 }
            return connections.count
        }
    }
    #endif
}

private actor SocketListenerStopSignal {
    private enum State {
        case pending([CheckedContinuation<Void, Never>])
        case stopped
    }

    private var state = State.pending([])

    func wait() async {
        guard case .pending = state else { return }
        await withCheckedContinuation { continuation in
            switch state {
            case .pending(var waiters):
                waiters.append(continuation)
                state = .pending(waiters)
            case .stopped:
                continuation.resume()
            }
        }
    }

    func finish() {
        switch state {
        case .pending(let waiters):
            state = .stopped
            waiters.forEach { $0.resume() }
        case .stopped:
            return
        }
    }
}

actor SocketListenerRuntime: Equatable {
    private enum Phase {
        case idle
        case starting([NWListener])
        case listening([NWListener], port: UInt16)
        case stopped
    }

    nonisolated private let pendingConnections = PendingSocketConnections()
    private let stopSignal = SocketListenerStopSignal()
    private var phase = Phase.idle

    #if DEBUG
    private let stopOverride: (@Sendable () async -> Void)?

    init(stopOverride: (@Sendable () async -> Void)? = nil) {
        self.stopOverride = stopOverride
    }
    #else
    init() {}
    #endif

    nonisolated static func == (lhs: SocketListenerRuntime, rhs: SocketListenerRuntime) -> Bool {
        lhs === rhs
    }

    nonisolated fileprivate func own(_ connection: NWConnection) -> Bool {
        pendingConnections.own(connection)
    }

    @discardableResult
    nonisolated fileprivate func cancelIfOwned(_ connection: NWConnection) -> Bool {
        pendingConnections.cancelIfOwned(connection)
    }

    nonisolated fileprivate func transferToClientRegistry(_ connection: NWConnection) -> Bool {
        pendingConnections.transfer(connection)
    }

    #if DEBUG
    nonisolated fileprivate var pendingConnectionCountForTesting: Int {
        pendingConnections.count
    }
    #endif

    func stop() async {
        let listeners: [NWListener]
        switch phase {
        case .idle:
            listeners = []
        case .starting(let startingListeners), .listening(let startingListeners, _):
            listeners = startingListeners
        case .stopped:
            await stopSignal.wait()
            return
        }
        phase = .stopped
        pendingConnections.cancelAll()
        listeners.forEach { $0.cancel() }
        #if DEBUG
        if let stopOverride {
            await stopOverride()
        }
        #endif
        await stopSignal.finish()
    }

    func isAcceptingConnections() -> Bool {
        guard case .listening = phase else { return false }
        return true
    }

    func start(
        port: UInt16,
        bindToLoopback: Bool,
        addressFamily: ListenerAddressFamily,
        parameters: NWParameters,
        queue: DispatchQueue,
        newConnectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) async throws -> UInt16 {
        try beginStarting()

        let hosts = addressFamily.hosts(bindToLoopback: bindToLoopback)
        var requestedPort = port

        do {
            for host in hosts {
                let listener = try makeListener(
                    host: host,
                    port: requestedPort,
                    parameters: parameters,
                    allowEndpointReuse: hosts.count > 1,
                    newConnectionHandler: newConnectionHandler
                )
                try append(listener)
                let actualPort = try await startAndWaitForReady(listener, queue: queue)
                try requireStarting()
                if requestedPort == 0 {
                    requestedPort = actualPort
                } else if actualPort != requestedPort {
                    throw SimpleSocketServer.ServerError.failedToBindPort
                }
            }

            guard requestedPort != 0 else {
                throw SimpleSocketServer.ServerError.failedToBindPort
            }
            try finishStarting(port: requestedPort)
            return requestedPort
        } catch {
            await stop()
            throw error
        }
    }

    #if DEBUG
    func startForTesting(
        _ operation: @escaping @Sendable () async throws -> UInt16
    ) async throws -> UInt16 {
        try beginStarting()
        do {
            let port = try await operation()
            try finishStarting(port: port)
            return port
        } catch {
            await stop()
            throw error
        }
    }

    var phaseForTesting: SocketListenerRuntimePhase {
        switch phase {
        case .idle:
            return .idle
        case .starting:
            return .starting
        case .listening(_, let port):
            return .listening(port: port)
        case .stopped:
            return .stopped
        }
    }

    func waitUntilStoppedForTesting() async {
        await stopSignal.wait()
    }
    #endif

    private func beginStarting() throws {
        guard case .idle = phase else { throw CancellationError() }
        phase = .starting([])
    }

    private func finishStarting(port: UInt16) throws {
        guard case .starting(let listeners) = phase else { throw CancellationError() }
        phase = .listening(listeners, port: port)
    }

    private func append(_ listener: NWListener) throws {
        guard case .starting(var listeners) = phase else {
            listener.cancel()
            throw CancellationError()
        }
        listeners.append(listener)
        phase = .starting(listeners)
    }

    private func requireStarting() throws {
        guard case .starting = phase else { throw CancellationError() }
    }

    private func makeListener(
        host: NWEndpoint.Host,
        port: UInt16,
        parameters: NWParameters,
        allowEndpointReuse: Bool,
        newConnectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) throws -> NWListener {
        let listenerParameters = parameters.copy()
        listenerParameters.allowLocalEndpointReuse = allowEndpointReuse
        listenerParameters.requiredLocalEndpoint = .hostPort(
            host: host,
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        let listener = try NWListener(using: listenerParameters)
        listener.newConnectionHandler = newConnectionHandler
        return listener
    }

    private func startAndWaitForReady(
        _ listener: NWListener,
        queue: DispatchQueue
    ) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    if let port = listener.port?.rawValue {
                        listenerLogger.info("Listening on port \(port)")
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: SimpleSocketServer.ServerError.failedToBindPort)
                    }
                case .failed(let error):
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    listenerLogger.error("Listener failed: \(error)")
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    let shouldResume = resumed.withLock { flag -> Bool in
                        guard !flag else { return false }
                        flag = true
                        return true
                    }
                    guard shouldResume else { return }
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}

#if DEBUG
enum SocketListenerRuntimePhase: Equatable, Sendable {
    case idle
    case starting
    case listening(port: UInt16)
    case stopped
}
#endif

private extension ListenerAddressFamily {
    func hosts(bindToLoopback: Bool) -> [NWEndpoint.Host] {
        switch self {
        case .ipv4:
            return [bindToLoopback ? .ipv4(.loopback) : .ipv4(.any)]
        case .ipv6:
            return [bindToLoopback ? .ipv6(.loopback) : .ipv6(.any)]
        case .dualStack:
            if !bindToLoopback {
                // An all-interface Network listener is already dual-stack; a
                // second any-address listener on the same port collides.
                return [.ipv4(.any)]
            }
            return [
                .ipv4(.loopback),
                .ipv6(.loopback),
            ]
        }
    }
}

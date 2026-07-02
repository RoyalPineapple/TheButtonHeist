import Foundation
import Network
import os

import TheScore

private let listenerLogger = ButtonHeistLog.logger(.handoff(.server))

struct SocketListenerStartup {
    let listeners: [NWListener]
    let port: UInt16

    static func start(
        port: UInt16,
        bindToLoopback: Bool,
        addressFamily: ListenerAddressFamily,
        parameters: NWParameters,
        queue: DispatchQueue,
        newConnectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) async throws -> SocketListenerStartup {
        let hosts = addressFamily.hosts(bindToLoopback: bindToLoopback)
        var requestedPort = port
        var listeners: [NWListener] = []

        do {
            for host in hosts {
                let listener = try makeListener(
                    host: host,
                    port: requestedPort,
                    parameters: parameters,
                    allowEndpointReuse: hosts.count > 1,
                    newConnectionHandler: newConnectionHandler
                )
                let actualPort = try await startAndWaitForReady(listener, queue: queue)
                if requestedPort == 0 {
                    requestedPort = actualPort
                } else if actualPort != requestedPort {
                    listener.cancel()
                    throw SimpleSocketServer.ServerError.failedToBindPort
                }
                listeners.append(listener)
            }
        } catch {
            for listener in listeners {
                listener.cancel()
            }
            throw error
        }

        guard requestedPort != 0 else {
            throw SimpleSocketServer.ServerError.failedToBindPort
        }

        return SocketListenerStartup(listeners: listeners, port: requestedPort)
    }

    private static func makeListener(
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

    private static func startAndWaitForReady(_ listener: NWListener, queue: DispatchQueue) async throws -> UInt16 {
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
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}

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

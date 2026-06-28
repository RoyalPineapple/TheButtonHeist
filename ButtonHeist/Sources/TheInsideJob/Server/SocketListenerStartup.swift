import Foundation
import Network
import os

import TheScore

private let listenerLogger = ButtonHeistLog.logger(.handoff(.server))

struct SocketListenerStartup {
    let listener: NWListener
    let port: UInt16

    static func start(
        port: UInt16,
        bindToLoopback: Bool,
        parameters: NWParameters,
        queue: DispatchQueue,
        newConnectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) async throws -> SocketListenerStartup {
        let host: NWEndpoint.Host = bindToLoopback ? .ipv6(.loopback) : .ipv6(.any)
        parameters.requiredLocalEndpoint = .hostPort(
            host: host,
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = newConnectionHandler
        let actualPort = try await startAndWaitForReady(listener, queue: queue)

        return SocketListenerStartup(listener: listener, port: actualPort)
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

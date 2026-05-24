import Foundation
import Network
import os

import TheScore

private let receiveLogger = Logger(subsystem: "com.buttonheist.thehandoff", category: "server")

extension SimpleSocketServer {
    static let maxMessagesPerSecond = SocketRateLimiter.defaultMaxMessagesPerSecond

    func startReceiving(clientId: Int, connection: NWConnection) {
        receiveNextChunk(clientId: clientId, connection: connection, framer: SocketReceiveFramer())
    }

    private func receiveNextChunk(clientId: Int, connection: NWConnection, framer: SocketReceiveFramer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            self.spawnTrackedTask { server in
                await server.handleReceivedData(
                    clientId: clientId,
                    connection: connection,
                    content: content,
                    isComplete: isComplete,
                    error: error,
                    framer: framer
                )
            }
        }
    }

    /// Process received data within actor isolation.
    private func handleReceivedData(
        clientId: Int,
        connection: NWConnection,
        content: Data?,
        isComplete: Bool,
        error: NWError?,
        framer: SocketReceiveFramer
    ) {
        if let error {
            receiveLogger.error("Receive error from client \(clientId): \(error)")
            removeClient(clientId)
            return
        }

        var receiveFramer = framer
        let messageFrames: [Data]
        do {
            messageFrames = try receiveFramer.append(content)
        } catch {
            receiveLogger.error("Client \(clientId) exceeded max buffer size, disconnecting")
            rejectClientWithServerError(
                clientId,
                kind: .validationError,
                message: "Inbound message exceeded the server buffer limit."
            )
            return
        }

        for messageData in messageFrames {
            guard routeMessageFrame(clientId: clientId, messageData: messageData) else { return }
        }

        if isComplete {
            removeClient(clientId)
        } else {
            receiveNextChunk(clientId: clientId, connection: connection, framer: receiveFramer)
        }
    }

    private func routeMessageFrame(clientId: Int, messageData: Data) -> Bool {
        switch clientRegistry.recordInboundMessage(clientId: clientId) {
        case .missingClient:
            return false
        case .rateLimited(let authenticated, let shouldNotify):
            if authenticated {
                receiveLogger.warning("Client \(clientId) rate limited, dropping message")
            } else {
                receiveLogger.warning("Unauthenticated client \(clientId) rate limited, dropping message")
            }
            if shouldNotify {
                notifyRateLimit(clientId)
            }
        case .accepted(let authenticated):
            clientLifecycle.receivedData(clientId: clientId, data: messageData, authenticated: authenticated) { [weak self] response in
                guard let self else { return }
                self.spawnTrackedTask { server in await server.send(response, to: clientId) }
            }
        }
        return true
    }

    private func notifyRateLimit(_ clientId: Int) {
        clientLifecycle.rateLimited(clientId) { [weak self] response in
            guard let self else { return }
            self.spawnTrackedTask { server in await server.send(response, to: clientId) }
        }
    }
}

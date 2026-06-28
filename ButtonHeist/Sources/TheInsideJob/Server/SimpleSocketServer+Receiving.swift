import Foundation
import Network
import os

import TheScore

private let receiveLogger = ButtonHeistLog.logger(.handoff(.server))

extension SimpleSocketServer {
    func startReceiving(clientId: Int, connection: NWConnection) {
        receiveNextChunk(clientId: clientId, connection: connection, framer: SocketReceiveFramer())
    }

    private func receiveNextChunk(clientId: Int, connection: NWConnection, framer: SocketReceiveFramer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: WireFrameLimits.receiveChunkBytes) { [weak self] content, _, isComplete, error in
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
        guard clientRegistry.client(clientId) != nil else { return false }
        clientLifecycle.receivedData(clientId: clientId, data: messageData) { [weak self] response in
            guard let self else { return }
            self.spawnTrackedTask { server in await server.send(response, to: clientId) }
        }
        return true
    }
}

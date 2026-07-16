import Foundation
import Network
import os

import ButtonHeistSupport
import TheScore

private let sendLogger = ButtonHeistLog.logger(.handoff(.server))

extension SimpleSocketServer {
    /// Send data to a specific client.
    @discardableResult
    func send(_ data: Data, to clientId: Int) async -> ServerSendOutcome {
        var dataToSend = data
        if !dataToSend.hasSuffix(Data([WireFrameLimits.newlineDelimiterByte])) {
            dataToSend.append(WireFrameLimits.newlineDelimiterByte)
        }

        let byteCount = dataToSend.count
        guard clientRegistry.client(clientId) != nil else {
            return .failed(.clientNotFound(clientId))
        }
        guard let generation = currentListener else {
            return .failed(.transportUnavailable)
        }

        let connection: NWConnection
        switch clientRegistry.reserveSend(clientId: clientId, byteCount: byteCount) {
        case .missingClient:
            return .failed(.clientNotFound(clientId))
        case .accepted(let acceptedConnection):
            connection = acceptedConnection
        case .rejected(let rejection, let state):
            switch rejection {
            case .payloadTooLarge:
                sendLogger.warning("Client \(clientId) send payload exceeds cap (\(byteCount) bytes), failing the originating request")
                sendOversizedResponseError(clientId: clientId, originalData: data, byteCount: byteCount, state: state)
            case .bufferFull(let pendingBytes, _, _):
                sendLogger.warning("Client \(clientId) send buffer full (\(pendingBytes) bytes pending), dropping \(byteCount) bytes")
            }
            return .failed(rejection.sendFailure)
        }

        return await withCheckedContinuation { continuation in
            sendContent(connection, dataToSend, .contentProcessed { [weak self] error in
                if let error {
                    sendLogger.error("Send error to client \(clientId): \(error)")
                }
                guard let self else {
                    continuation.resume(returning: .failed(.transportUnavailable))
                    return
                }
                let admission = self.spawnTrackedTask(in: generation) { server in
                    let outcome = await server.completedSend(
                        clientId: clientId,
                        byteCount: byteCount,
                        error: error
                    )
                    continuation.resume(returning: outcome)
                }
                if case .rejected = admission {
                    continuation.resume(returning: .failed(.transportUnavailable))
                }
            })
        }
    }

    /// Called when NWConnection finishes processing a send.
    private func completedSend(clientId: Int, byteCount: Int, error: NWError?) -> ServerSendOutcome {
        let clientWasStillConnected = clientRegistry.completeSend(clientId: clientId, byteCount: byteCount)
        if let error {
            let failure = ServerSendFailure.transportFailed(
                clientId: clientId,
                diagnostic: NetworkTransportFailure(error)
            )
            if clientWasStillConnected {
                removeClient(clientId)
            }
            return .failed(failure)
        }

        guard clientWasStillConnected else {
            return .failed(.clientNotFound(clientId))
        }
        return .delivered
    }

    /// Try to fail the originating request explicitly when a response exceeds the send cap.
    private func sendOversizedResponseError(
        clientId: Int,
        originalData: Data,
        byteCount: Int,
        state: SocketClientRegistry.Client
    ) {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: originalData)
        } catch {
            sendLogger.error("Failed to decode oversized response envelope for client \(clientId): \(error.localizedDescription); dropping")
            return
        }
        let message = "Response too large to send over the socket (\(byteCount) bytes)"
        sendErrorEnvelope(
            clientId: clientId,
            envelope: ResponseEnvelope(
                requestId: envelope.requestId,
                message: .error(TheScore.ServerError(kind: .general, message: message))
            ),
            state: state
        )
    }

    func sendErrorEnvelope(clientId: Int, envelope: ResponseEnvelope, state: SocketClientRegistry.Client) {
        let response: Data
        do {
            response = try envelope.encoded()
        } catch {
            sendLogger.error("Failed to encode oversized-response error for client \(clientId): \(error.localizedDescription)")
            return
        }
        var errorData = response
        if !errorData.hasSuffix(Data([WireFrameLimits.newlineDelimiterByte])) {
            errorData.append(WireFrameLimits.newlineDelimiterByte)
        }
        sendContent(state.connection, errorData, .contentProcessed { error in
            if let error {
                sendLogger.error("Send error to client \(clientId): \(error)")
            }
        })
    }
}

extension Data {
    func hasSuffix(_ suffixData: Data) -> Bool {
        guard count >= suffixData.count else { return false }
        return self.suffix(suffixData.count) == suffixData
    }
}

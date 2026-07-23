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
        guard let generation = currentListener else {
            return .failed(.transportUnavailable)
        }

        let reservation: SocketClientRegistry.SendReservation
        switch clientRegistry.reserveSend(clientId: clientId, byteCount: byteCount) {
        case .missingClient:
            return .failed(.clientNotFound(clientId))
        case .accepted(let acceptedReservation):
            reservation = acceptedReservation
        case .rejected(let rejection):
            switch rejection {
            case .payloadTooLarge:
                await sendOversizedResponseError(clientId: clientId, originalData: data, byteCount: byteCount)
            case .bufferFull:
                break
            }
            return .failed(rejection.sendFailure)
        }

        return await withCheckedContinuation { continuation in
            dependencies.sendContent(reservation.connection, dataToSend, .contentProcessed { [weak self] error in
                guard let self else {
                    continuation.resume(returning: .failed(.transportUnavailable))
                    return
                }
                let admission = self.spawnTrackedTask(in: generation) { server in
                    let outcome = await server.completedSend(
                        reservation,
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
    private func completedSend(
        _ reservation: SocketClientRegistry.SendReservation,
        error: NWError?
    ) -> ServerSendOutcome {
        let completion = clientRegistry.completeSend(reservation)
        if let error {
            let failure = ServerSendFailure.transportFailed(
                clientId: reservation.clientId,
                diagnostic: NetworkTransportFailure(error)
            )
            if completion == .completed {
                removeClient(reservation.clientId)
            }
            return .failed(failure)
        }

        guard completion == .completed else {
            return .failed(.clientNotFound(reservation.clientId))
        }
        return .delivered
    }

    /// Try to fail the originating request explicitly when a response exceeds the send cap.
    private func sendOversizedResponseError(
        clientId: Int,
        originalData: Data,
        byteCount: Int
    ) async {
        let envelope: ResponseEnvelope
        do {
            envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: originalData)
        } catch {
            sendLogger.error("Failed to decode oversized response envelope for client \(clientId): \(error.localizedDescription); dropping")
            return
        }
        let message: ServerErrorMessage
        do {
            message = try ServerErrorMessage(
                validating: "Response too large to send over the socket (\(byteCount) bytes)"
            )
        } catch {
            sendLogger.error("Failed to admit oversized-response error for client \(clientId): \(error)")
            return
        }
        await sendErrorEnvelope(
            clientId: clientId,
            envelope: ResponseEnvelope(
                requestId: envelope.requestId,
                message: .error(TheScore.ServerError(kind: .general, message: message))
            )
        )
    }

    func sendErrorEnvelope(clientId: Int, envelope: ResponseEnvelope) async {
        let response: Data
        do {
            response = try envelope.encoded()
        } catch {
            sendLogger.error("Failed to encode server error for client \(clientId): \(error.localizedDescription)")
            return
        }
        _ = await send(response, to: clientId)
    }
}

extension Data {
    func hasSuffix(_ suffixData: Data) -> Bool {
        guard count >= suffixData.count else { return false }
        return self.suffix(suffixData.count) == suffixData
    }
}

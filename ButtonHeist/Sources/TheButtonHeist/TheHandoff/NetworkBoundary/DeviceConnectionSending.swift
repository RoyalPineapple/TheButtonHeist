import ButtonHeistSupport
import Foundation
import Network
@_spi(ButtonHeistInternals) import TheScore

extension DeviceConnection {
    @discardableResult
    func send(_ message: ClientMessage, requestId: RequestID? = nil) -> DeviceSendOutcome {
        guard let sessionID = currentSessionID,
              let session = connectedSession(matching: sessionID) else {
            return .failed(.notConnected)
        }
        let envelope = RequestEnvelope(
            requestId: requestId,
            message: message
        )
        let data: Data
        do {
            var encoded = try JSONEncoder().encode(envelope)
            encoded.append(WireFrameLimits.newlineDelimiterByte)
            data = encoded
        } catch {
            return .failed(.encodingFailed(DeviceEncodingFailure(error)))
        }

        let connection = session.connection
        let eventStream = session.eventStream
        sendContent(connection, data, .contentProcessed { error in
            if let error {
                eventStream.yield(.sendFailed(
                    error,
                    requestId: requestId,
                    sessionID: sessionID,
                    connection: connection
                ))
            }
        })
        return .enqueued
    }

    func handleSendFailure(_ error: NWError, requestId: RequestID?, connection: NWConnection) {
        handleSendFailure(error, requestId: requestId, connection: connection, sessionID: nil)
    }

    func handleSendFailure(_ error: NWError, requestId: RequestID?, connection: NWConnection, sessionID: UUID?) {
        guard isCurrentSession(sessionID, connection: connection) else { return }
        onEvent?(.sendFailed(.transportFailed(NetworkTransportFailure(error)), requestId: requestId))
    }
}

import ButtonHeistSupport
import Foundation
import Network
@_spi(ButtonHeistInternals) import TheScore

extension DeviceConnection {
    @discardableResult
    func send(_ message: ClientMessage, requestId: String? = nil) -> DeviceSendOutcome {
        guard case .connected(let active) = connectionState,
              let sessionID = currentSessionID else {
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
            deviceConnectionLogger.error("Failed to encode message: \(error)")
            return .failed(.encodingFailed(DeviceEncodingFailure(error)))
        }

        let connection = active.connection
        sendContent(connection, data, .contentProcessed { [weak self] error in
            if let error {
                deviceConnectionLogger.error("Send error: \(error)")
                Task { @ButtonHeistActor [weak self] in
                    self?.handleSendFailure(error, requestId: requestId, connection: connection, sessionID: sessionID)
                }
            }
        })
        return .enqueued
    }

    func handleSendFailure(_ error: NWError, requestId: String?, connection: NWConnection) {
        handleSendFailure(error, requestId: requestId, connection: connection, sessionID: nil)
    }

    func handleSendFailure(_ error: NWError, requestId: String?, connection: NWConnection, sessionID: UUID?) {
        guard isCurrentSession(sessionID, connection: connection) else { return }
        onEvent?(.sendFailed(.transportFailed(NetworkTransportFailure(error)), requestId: requestId))
    }
}

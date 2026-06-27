import Foundation
import Network
import TheScore

extension DeviceConnection {
    @discardableResult
    func send(_ message: ClientMessage, requestId: String? = nil) -> DeviceSendOutcome {
        guard case .connected(let active) = connectionState else {
            return .failed(.notConnected)
        }
        let envelope = RequestEnvelope(requestId: requestId, message: message)
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
                    self?.handleSendFailure(error, requestId: requestId, connection: connection)
                }
            }
        })
        return .enqueued
    }

    func handleSendFailure(_ error: NWError, requestId: String?, connection: NWConnection) {
        if let current = currentConnection, current !== connection {
            return
        }
        onEvent?(.sendFailed(.transportFailed(DeviceTransportFailure(error)), requestId: requestId))
    }
}

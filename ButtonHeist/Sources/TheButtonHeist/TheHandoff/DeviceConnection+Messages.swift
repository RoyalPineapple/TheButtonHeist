import Foundation

@ButtonHeistActor
extension DeviceConnection {

    // Internal for testing (see AuthFlowTests, AuthFailureTests)
    func handleMessage(_ data: Data) {
        deviceConnectionLogger.debug("Parsing message: \(data.count) bytes")
        if let legacyAuthResponse = unsupportedLegacyAuthResponse(in: data) {
            deviceConnectionLogger.error("Unsupported legacy auth response: \(legacyAuthResponse, privacy: .public)")
            emitMessage(.error(ServerError(
                kind: .authFailure,
                message: Self.unsupportedLegacyAuthResponseMessage(type: legacyAuthResponse)
            )), requestId: nil)
            return
        }

        guard let envelope = decodeEnvelope(from: data) else {
            if let str = String(data: data, encoding: .utf8) {
                deviceConnectionLogger.error("Failed to decode: \(str.prefix(200))")
            }
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? "<binary data>"
            let error = ServerError(kind: .general, message: "Failed to decode server message: \(detail)")
            emitMessage(.error(error), requestId: nil)
            return
        }

        if envelope.buttonHeistVersion != buttonHeistVersion {
            let message = DisconnectReason.buttonHeistVersionMismatchMessage(
                serverVersion: envelope.buttonHeistVersion,
                clientVersion: buttonHeistVersion
            )
            deviceConnectionLogger.error("buttonHeistVersion mismatch: \(message)")
            emitMessage(.protocolMismatch(ProtocolMismatchPayload(
                serverButtonHeistVersion: envelope.buttonHeistVersion,
                clientButtonHeistVersion: buttonHeistVersion
            )), requestId: envelope.requestId)
            return
        }

        switch envelope.message {
        case .serverHello:
            deviceConnectionLogger.info("Received server hello")
            emitEnvelopeMessage(envelope)
        case .protocolMismatch(let payload):
            let message = DisconnectReason.buttonHeistVersionMismatchMessage(
                serverVersion: payload.serverButtonHeistVersion,
                clientVersion: payload.clientButtonHeistVersion
            )
            deviceConnectionLogger.error("buttonHeistVersion mismatch: \(message)")
            emitMessage(.protocolMismatch(payload), requestId: envelope.requestId)
        case .authRequired:
            emitMessage(.authRequired, requestId: nil)
        case .error(let serverError) where serverError.kind == .authFailure:
            deviceConnectionLogger.error("Auth failed: \(serverError.message)")
            emitMessage(.error(serverError), requestId: nil)
        case .sessionLocked(let payload):
            deviceConnectionLogger.warning("Session locked: \(payload.message, privacy: .public)")
            emitMessage(.sessionLocked(payload), requestId: nil)
        case .info(let info):
            deviceConnectionLogger.info("Received server info: \(info.appName)")
            onEvent?(.connected)
            emitMessage(.info(info), requestId: envelope.requestId)
        case .pong:
            // Pong must reach TheHandoff so the keepalive task can reset
            // its missed-pong counter. Earlier code logged the pong here and
            // stopped, which meant the counter incremented every 5s but never
            // decremented.
            deviceConnectionLogger.debug("Received pong")
            emitEnvelopeMessage(envelope)
        default:
            emitEnvelopeMessage(envelope)
        }
    }

    private func emitEnvelopeMessage(_ envelope: ResponseEnvelope) {
        emitMessage(
            envelope.message,
            requestId: envelope.requestId
        )
    }

    private func emitMessage(
        _ message: ServerMessage,
        requestId: String?
    ) {
        onEvent?(.message(
            message,
            requestId: requestId
        ))
    }

    private func decodeEnvelope(from data: Data) -> ResponseEnvelope? {
        do {
            return try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            deviceConnectionLogger.error("Failed to decode server response: \(error)")
            return nil
        }
    }

    private func unsupportedLegacyAuthResponse(in data: Data) -> String? {
        guard let probe = try? JSONDecoder().decode(ServerWireTypeProbe.self, from: data) else {
            return nil
        }
        switch (probe.type, probe.payload?.kind) {
        case ("authApprovalPending", _),
             ("authApproved", _):
            return probe.type
        case ("error", "authApprovalPending"):
            return "error.authApprovalPending"
        default:
            return nil
        }
    }

    private static func unsupportedLegacyAuthResponseMessage(type: String) -> String {
        "Unsupported auth response '\(type)'. Button Heist now authenticates with token-derived TLS PSK. " +
            "Rebuild or reinstall the app and retry with the configured token."
    }
}

private struct ServerWireTypeProbe: Decodable {
    let type: String
    let payload: Payload?

    struct Payload: Decodable {
        let kind: String?
    }
}

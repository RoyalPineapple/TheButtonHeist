import Foundation

@ButtonHeistActor
extension DeviceConnection {

    // Internal for testing (see AuthFlowTests, AuthFailureTests)
    func handleMessage(_ data: Data) {
        deviceConnectionLogger.debug("Parsing message: \(data.count) bytes")
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
            disconnect()
            onEvent?(.disconnected(.protocolMismatch(message)))
            return
        }

        switch envelope.message {
        case .serverHello:
            deviceConnectionLogger.info("Received server hello")
            send(.clientHello)
        case .protocolMismatch(let payload):
            let message = DisconnectReason.buttonHeistVersionMismatchMessage(
                serverVersion: payload.serverButtonHeistVersion,
                clientVersion: payload.clientButtonHeistVersion
            )
            deviceConnectionLogger.error("buttonHeistVersion mismatch: \(message)")
            emitMessage(.protocolMismatch(payload), requestId: envelope.requestId)
            disconnect()
            onEvent?(.disconnected(.protocolMismatch(message)))
        case .authRequired:
            if autoRespondToAuthRequired {
                handleAuthRequired()
            } else {
                emitMessage(.authRequired, requestId: nil)
            }
        case .authApprovalPending(let payload):
            deviceConnectionLogger.info("Auth approval pending: \(payload.message, privacy: .public)")
            emitMessage(.authApprovalPending(payload), requestId: envelope.requestId)
        case .error(let serverError) where serverError.kind == .authFailure:
            deviceConnectionLogger.error("Auth failed: \(serverError.message)")
            emitMessage(.error(serverError), requestId: nil)
            disconnect()
            onEvent?(.disconnected(.authFailed(serverError.message)))
        case .error(let serverError) where serverError.kind == .authApprovalPending:
            deviceConnectionLogger.error("Auth approval timed out: \(serverError.message)")
            emitMessage(.error(serverError), requestId: nil)
            disconnect()
            onEvent?(.disconnected(.authApprovalPending(serverError.message)))
        case .authApproved(let payload):
            deviceConnectionLogger.info("Auth approved via UI, received token")
            updateToken(payload.token)
            emitMessage(.authApproved(payload), requestId: nil)
        case .sessionLocked(let payload):
            deviceConnectionLogger.warning("Session locked: \(payload.message, privacy: .public)")
            emitMessage(.sessionLocked(payload), requestId: nil)
            disconnect()
            onEvent?(.disconnected(.sessionLocked(payload.message)))
        case .info(let info):
            deviceConnectionLogger.info("Received server info: \(info.appName)")
            onEvent?(.connected)
            emitMessage(.info(info), requestId: envelope.requestId)
        case .pong:
            // Pong must reach TheHandoff so the keepalive task can reset
            // its missed-pong counter. Earlier code logged the pong here
            // and stopped, which meant the counter incremented every 5s
            // but never decremented — TheHandoff would force-disconnect
            // any connection that stayed idle for 30s, including the
            // window while the server was finalizing a recording. The
            // log line stays for diagnostic noise; the message is also
            // propagated so TheHandoff can mark the connection live.
            deviceConnectionLogger.debug("Received pong")
            emitEnvelopeMessage(envelope)
        case .recordingStopped:
            // TheHandoff clears its recording phase on this message;
            // dropping it here left the client believing a recording
            // was still in progress after the server had already torn
            // it down (e.g. a max-duration broadcast with no pending
            // stop_recording response).
            deviceConnectionLogger.debug("Recording stop acknowledged")
            emitEnvelopeMessage(envelope)
        default:
            emitEnvelopeMessage(envelope)
        }
    }

    private func emitEnvelopeMessage(_ envelope: ResponseEnvelope) {
        emitMessage(
            envelope.message,
            requestId: envelope.requestId,
            accessibilityTrace: envelope.accessibilityTrace
        )
    }

    private func emitMessage(
        _ message: ServerMessage,
        requestId: String?,
        accessibilityTrace: AccessibilityTrace? = nil
    ) {
        onEvent?(.message(
            message,
            requestId: requestId,
            accessibilityTrace: accessibilityTrace
        ))
    }

    private func handleAuthRequired() {
        deviceConnectionLogger.info("Auth required, sending token")
        send(.authenticate(AuthenticatePayload(
            token: token ?? "",
            driverId: driverId
        )))
    }

    private func decodeEnvelope(from data: Data) -> ResponseEnvelope? {
        do {
            return try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        } catch {
            deviceConnectionLogger.error("Failed to decode server response: \(error)")
            return nil
        }
    }
}

import TheScore

/// Client-side admission protocol: respond to server handshake/auth messages
/// and name terminal admission failures.
struct HandoffAdmission {
    var authToken: SessionAuthToken?
    var driverId: DriverID?

    init(token: SessionAuthToken? = nil, driverId: DriverID? = nil) {
        self.authToken = token
        self.driverId = driverId
    }

    var effectiveDriverId: DriverID {
        HandoffDriverIdentity.effectiveDriverId(explicit: driverId)
    }

    func decision(for message: ServerMessage) -> HandoffAdmissionDecision? {
        switch message {
        case .serverHello:
            return .send(.clientHello)
        case .authRequired:
            guard let authToken else {
                return .terminalFailure(.disconnected(.missingToken))
            }
            return .send(.authenticate(AuthenticatePayload(
                token: authToken,
                driverId: effectiveDriverId
            )))
        case .sessionLocked(let payload):
            return .terminalFailure(.disconnected(.sessionLocked(payload.message)))
        case .protocolMismatch(let payload):
            return .terminalFailure(.disconnected(.buttonHeistVersionMismatch(
                serverVersion: payload.serverButtonHeistVersion,
                clientVersion: payload.clientButtonHeistVersion
            )))
        case .error(let serverError):
            switch serverError.kind {
            case .authFailure:
                return .terminalFailure(.disconnected(.authFailed(
                    serverError.message.description,
                    hint: serverError.recoveryHint?.description
                )))
            default:
                return nil
            }
        case .info, .interface, .actionResult, .screen, .announcements, .status, .pong:
            return nil
        }
    }
}

enum HandoffAdmissionDecision {
    case send(ClientMessage)
    case terminalFailure(HandoffConnectionError)
}

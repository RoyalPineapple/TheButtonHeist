import Foundation

/// Client-side admission protocol: respond to server handshake/auth messages
/// and name terminal admission failures.
struct HandoffAdmission {
    var token: String?
    var driverId: String?

    var effectiveDriverId: String {
        HandoffDriverIdentity.effectiveDriverId(explicit: driverId)
    }

    func decision(for message: ServerMessage) -> HandoffAdmissionDecision? {
        switch message {
        case .serverHello:
            return .send(.clientHello)
        case .authRequired:
            guard let token = validToken(token) else {
                return .terminalFailure(.disconnected(.missingToken))
            }
            return .send(.authenticate(AuthenticatePayload(
                token: token,
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
                return .terminalFailure(.disconnected(.authFailed(serverError.message)))
            default:
                return nil
            }
        case .info, .interface, .actionResult, .screen, .status, .pong:
            return nil
        }
    }

    private func validToken(_ token: String?) -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }
}

enum HandoffAdmissionDecision {
    case send(ClientMessage)
    case terminalFailure(HandoffConnectionError)
}

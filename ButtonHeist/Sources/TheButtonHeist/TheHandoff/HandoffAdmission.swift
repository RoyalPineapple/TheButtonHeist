import Foundation

struct HandoffAuthToken: Sendable, Equatable {
    let rawValue: String

    init?(_ token: String?) {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = token
    }
}

/// Client-side admission protocol: respond to server handshake/auth messages
/// and name terminal admission failures.
struct HandoffAdmission {
    private var authToken: HandoffAuthToken?
    var driverId: String?

    var token: String? {
        get { authToken?.rawValue }
        set { authToken = HandoffAuthToken(newValue) }
    }

    init(token: String? = nil, driverId: String? = nil) {
        self.authToken = HandoffAuthToken(token)
        self.driverId = driverId
    }

    var effectiveDriverId: String {
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
                token: authToken.rawValue,
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
                    serverError.message,
                    hint: serverError.recoveryHint
                )))
            default:
                return nil
            }
        case .info, .interface, .actionResult, .screen, .status, .pong:
            return nil
        }
    }
}

enum HandoffAdmissionDecision {
    case send(ClientMessage)
    case terminalFailure(HandoffConnectionError)
}

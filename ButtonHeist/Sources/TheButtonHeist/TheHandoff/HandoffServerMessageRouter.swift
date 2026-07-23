import Foundation

import TheScore

struct HandoffServerMessageRouter {
    var admission = HandoffAdmission()

    var authToken: SessionAuthToken? {
        get { admission.authToken }
        set { admission.authToken = newValue }
    }

    var driverId: DriverID? {
        get { admission.driverId }
        set { admission.driverId = newValue }
    }

    mutating func route(_ message: ServerMessage, requestId: RequestID?) -> HandoffServerMessageRoute {
        if let decision = admission.decision(for: message) {
            return .admission(decision)
        }

        switch message {
        case .info(let info):
            return .serverInfo(info)
        case .interface, .actionResult, .screen, .announcements:
            return .forward(message, requestId)
        case .error(let serverError):
            if let requestId {
                return .forward(message, requestId)
            }
            return .serverFailure(serverError)
        case .status:
            return .handled
        case .pong(let payload):
            return .pong(payload, requestId: requestId)
        case .sessionLocked, .protocolMismatch, .serverHello, .authRequired:
            assertionFailure("HandoffAdmission must consume admission messages before routing")
            return .handled
        }
    }
}

enum HandoffServerMessageRoute {
    case admission(HandoffAdmissionDecision)
    case serverInfo(ServerInfo)
    case forward(ServerMessage, RequestID?)
    case serverFailure(ServerError)
    case pong(PongPayload, requestId: RequestID?)
    case handled
}

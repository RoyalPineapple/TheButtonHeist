import Foundation
import os.log

import TheScore

private let serverMessageLogger = ButtonHeistLog.logger(.handoff(.serverMessage))

struct HandoffServerMessageRouter {
    var admission = HandoffAdmission()

    var token: String? {
        get { admission.token }
        set { admission.token = newValue }
    }

    var driverId: String? {
        get { admission.driverId }
        set { admission.driverId = newValue }
    }

    mutating func route(_ message: ServerMessage, requestId: String?) -> HandoffServerMessageRoute {
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
        case .status(let payload):
            serverMessageLogger.info("Received status payload: appName=\(payload.identity.appName, privacy: .public)")
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
    case forward(ServerMessage, String?)
    case serverFailure(ServerError)
    case pong(PongPayload, requestId: String?)
    case handled
}

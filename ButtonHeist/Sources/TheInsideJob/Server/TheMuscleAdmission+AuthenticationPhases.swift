#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

struct MuscleTokenAuthenticationPhase {
    static func authenticate(
        _ clientId: Int,
        address: String,
        payload: AuthenticatePayload,
        tokenAdmission: inout SessionAdmission,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionDecision {
        switch tokenAdmission.decideToken(payload.token, driverId: payload.driverId, address: address) {
        case .lockedOut(let error):
            return .handled([
                .log(.lockedOut(clientId: clientId, address: address)),
                .sendResponse(.error(error), requestId: nil, respond: respond),
                .delayedDisconnect(clientId: clientId),
            ])

        case .rejected(let rejection):
            switch rejection {
            case .invalidToken(let error, let attempts):
                return .handled([
                    .log(.invalidToken(clientId: clientId, attempts: attempts)),
                    .sendResponse(.error(error), requestId: nil, respond: respond),
                    .delayedDisconnect(clientId: clientId),
                ])

            case .lockoutStarted(let error, let attempts):
                return .handled([
                    .log(.lockoutStarted(address: address, attempts: attempts)),
                    .log(.invalidToken(clientId: clientId, attempts: attempts)),
                    .sendResponse(.error(error), requestId: nil, respond: respond),
                    .delayedDisconnect(clientId: clientId),
                ])
            }

        case .accepted(let driverIdentity):
            return .authenticate(MuscleAuthentication(
                clientId: clientId,
                address: address,
                driverIdentity: driverIdentity,
                respond: respond,
                source: .token
            ))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

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
            muscleAuthenticationLogger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
            return .handled(.response(.error(error), respond: respond, disconnect: clientId))

        case .rejected(let retryMessage, let attempts, let lockedOut):
            if lockedOut {
                muscleAuthenticationLogger.warning("Address \(address) locked out after \(attempts) failed attempts")
            }
            muscleAuthenticationLogger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
            return .handled(.response(
                .error(ServerError(kind: .authFailure, message: retryMessage)),
                respond: respond,
                disconnect: clientId
            ))

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

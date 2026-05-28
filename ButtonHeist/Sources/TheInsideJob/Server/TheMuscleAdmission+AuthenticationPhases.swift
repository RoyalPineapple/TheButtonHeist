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

struct MuscleUIApprovalPhase {
    static func request(
        _ clientId: Int,
        address: String,
        driverId: String?,
        clientRegistry: inout TheMuscleClientRegistry,
        tokenAdmission: SessionAdmission,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        switch tokenAdmission.decideEmptyToken() {
        case .rejectExplicitTokenRequired(let error):
            muscleAuthenticationLogger.warning("Client \(clientId) requested UI approval while an explicit token is configured")
            return .handled(.response(.error(error), respond: respond, disconnect: clientId))
        case .requestUIApproval:
            break
        }

        if let diagnostic = uiApprovalUnavailableDiagnostic {
            let payload = diagnostic.payload()
            muscleAuthenticationLogger.warning("Client \(clientId) rejected - \(payload.message, privacy: .public)")
            return .handled(.response(.sessionLocked(payload), respond: respond, disconnect: clientId))
        }

        guard !clientRegistry.hasPendingApproval else {
            muscleAuthenticationLogger.warning("Client \(clientId) requested UI approval while approval is already pending")
            return .handled(.response(
                .error(ServerError(
                    kind: .authFailure,
                    message: "UI approval is available only when no approval request is already active."
                )),
                respond: respond,
                disconnect: clientId
            ))
        }

        muscleAuthenticationLogger.info("Client \(clientId) requesting UI approval (no token)")
        clientRegistry.beginApproval(clientId, address: address, respond: respond, driverId: driverId)
        var effect = MuscleAdmissionEffect.response(.authApprovalPending(AuthApprovalPendingPayload()), respond: respond)
        effect.approvalPromptClientId = clientId
        return .handled(effect)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

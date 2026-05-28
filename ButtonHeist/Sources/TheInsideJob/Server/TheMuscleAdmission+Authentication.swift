#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

private let authenticationLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

extension TheMuscleAdmission {
    mutating func handleUnauthenticatedMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard envelope.buttonHeistVersion == buttonHeistVersion else {
            authenticationLogger.warning(
                "Client \(clientId) buttonHeistVersion mismatch: server=\(buttonHeistVersion), client=\(envelope.buttonHeistVersion)"
            )
            return .handled(.response(
                .protocolMismatch(ProtocolMismatchPayload(
                    serverButtonHeistVersion: buttonHeistVersion,
                    clientButtonHeistVersion: envelope.buttonHeistVersion
                )),
                respond: respond,
                disconnect: clientId
            ))
        }

        switch envelope.message {
        case .clientHello:
            return handleClientHello(clientId, envelope: envelope, respond: respond)
        case .authenticate(let payload):
            return handleAuthenticate(
                clientId,
                envelope: envelope,
                payload: payload,
                respond: respond,
                uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
            )
        default:
            return .handled(rejectUnauthenticatedMessage(
                clientId,
                message: "Authentication required before \(envelope.message.canonicalName).",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
    }

    private mutating func handleClientHello(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler
    ) -> MuscleAdmissionDecision {
        guard clientRegistry.markHelloValidated(clientId) != nil else {
            return .handled(rejectUnauthenticatedMessage(
                clientId,
                message: "Connection is not registered; reconnect before starting the auth handshake.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
        return .handled(.response(.authRequired, respond: respond))
    }

    private mutating func handleAuthenticate(
        _ clientId: Int,
        envelope: RequestEnvelope,
        payload: AuthenticatePayload,
        respond: @escaping ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard clientRegistry.phase(for: clientId)?.hasCompletedHello == true else {
            return .handled(rejectUnauthenticatedMessage(
                clientId,
                message: "Authentication requires clientHello first.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
        return processAuthentication(
            clientId,
            payload: payload,
            respond: respond,
            uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
        )
    }

    private mutating func processAuthentication(
        _ clientId: Int,
        payload: AuthenticatePayload,
        respond: @escaping ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard let phase = clientRegistry.phase(for: clientId) else {
            authenticationLogger.warning("Client \(clientId) has no registered address, rejecting auth")
            return .handled(.response(
                .error(ServerError(kind: .authFailure, message: "Connection rejected.")),
                respond: respond,
                disconnect: clientId
            ))
        }

        if payload.token.isEmpty {
            return requestUIApproval(
                clientId,
                address: phase.address,
                driverId: payload.driverId,
                respond: respond,
                uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
            )
        }

        return authenticateWithToken(
            clientId,
            address: phase.address,
            payload: payload,
            respond: respond
        )
    }

    private mutating func requestUIApproval(
        _ clientId: Int,
        address: String,
        driverId: String?,
        respond: @escaping ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        switch tokenAdmission.decideEmptyToken() {
        case .rejectExplicitTokenRequired(let error):
            authenticationLogger.warning("Client \(clientId) requested UI approval while an explicit token is configured")
            return .handled(.response(.error(error), respond: respond, disconnect: clientId))
        case .requestUIApproval:
            break
        }

        if let diagnostic = uiApprovalUnavailableDiagnostic {
            return .handled(rejectForSessionLock(clientId, diagnostic: diagnostic, respond: respond))
        }

        guard !clientRegistry.hasPendingApproval else {
            authenticationLogger.warning("Client \(clientId) requested UI approval while approval is already pending")
            return .handled(.response(
                .error(ServerError(
                    kind: .authFailure,
                    message: "UI approval is available only when no approval request is already active."
                )),
                respond: respond,
                disconnect: clientId
            ))
        }

        authenticationLogger.info("Client \(clientId) requesting UI approval (no token)")
        clientRegistry.beginApproval(clientId, address: address, respond: respond, driverId: driverId)
        var effect = MuscleAdmissionEffect.response(.authApprovalPending(AuthApprovalPendingPayload()), respond: respond)
        effect.approvalPromptClientId = clientId
        return .handled(effect)
    }

    private mutating func authenticateWithToken(
        _ clientId: Int,
        address: String,
        payload: AuthenticatePayload,
        respond: @escaping ResponseHandler
    ) -> MuscleAdmissionDecision {
        switch tokenAdmission.decideToken(payload.token, driverId: payload.driverId, address: address) {
        case .lockedOut(let error):
            authenticationLogger.warning("Client \(clientId) locked out (address: \(address)), rejecting")
            return .handled(.response(.error(error), respond: respond, disconnect: clientId))

        case .rejected(let retryMessage, let attempts, let lockedOut):
            if lockedOut {
                authenticationLogger.warning("Address \(address) locked out after \(attempts) failed attempts")
            }
            authenticationLogger.warning("Client \(clientId) sent invalid token, rejected (attempt \(attempts))")
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

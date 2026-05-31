#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

let muscleAuthenticationLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

/// Owns the authentication phases inside TheMuscle admission.
struct MuscleAuthenticationFlow {
    private var clientRegistry = TheMuscleClientRegistry()
    private var tokenAdmission: SessionAdmission
    private let tokenSource: SessionTokenSource

    init(tokenSource: SessionTokenSource, maxFailedAttempts: Int, lockoutDuration: TimeInterval) {
        self.tokenSource = tokenSource
        self.tokenAdmission = SessionAdmission(
            tokenSource: tokenSource,
            maxFailedAttempts: maxFailedAttempts,
            lockoutDuration: lockoutDuration
        )
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        clientRegistry.registerAddress(clientId, address: address)
    }

    mutating func removeAllClients() {
        clientRegistry.removeAll()
    }

    func contains(_ clientId: Int) -> Bool {
        clientRegistry.contains(clientId)
    }

    mutating func admitClientMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard let envelope = MuscleAuthenticationRequestDecoder.decode(data) else {
            let effect = clientRegistry.phase(for: clientId)?.isAuthenticated == true
                ? MuscleAuthenticationRejection.undecodableAuthenticatedMessage(clientId, respond: respond)
                : MuscleAuthenticationRejection.undecodableUnauthenticatedMessage(clientId, respond: respond)
            return .handled(effect)
        }

        guard clientRegistry.phase(for: clientId)?.isAuthenticated != true else {
            return MuscleAuthenticatedCommandPhase.admit(clientId, envelope: envelope, respond: respond)
        }

        return MuscleHandshakePhase.handle(
            clientId,
            envelope: envelope,
            respond: respond,
            clientRegistry: &clientRegistry,
            tokenAdmission: &tokenAdmission,
            uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
        )
    }

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> MuscleAdmissionEffect {
        clientRegistry.authenticate(
            authentication.clientId,
            address: authentication.address
        )

        switch authentication.source {
        case .token:
            muscleAuthenticationLogger.info("Client \(authentication.clientId) authenticated with token")
            return .none
        case .uiApproval(let approvedToken):
            muscleAuthenticationLogger.info("Client \(authentication.clientId) approved via UI")
            return .response(
                .authApproved(AuthApprovedPayload(token: approvedToken)),
                respond: authentication.respond
            )
        }
    }

    func rejectForSessionLock(
        _ clientId: Int,
        diagnostic: SessionLease.SessionLockDiagnostic,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        let payload = diagnostic.payload()
        muscleAuthenticationLogger.warning("Client \(clientId) rejected - \(payload.message, privacy: .public)")
        return .response(.sessionLocked(payload), respond: respond, disconnect: clientId)
    }

    mutating func denyClient(_ clientId: Int) -> MuscleAdmissionEffect {
        guard case .pendingApproval(let address, let respond, _) = clientRegistry.phase(for: clientId) else {
            return .none
        }

        clientRegistry.restoreHelloValidated(clientId, address: address)
        muscleAuthenticationLogger.info("Client \(clientId) denied via UI")
        return .response(
            .error(ServerError(kind: .authFailure, message: "Connection denied by user")),
            respond: respond,
            disconnect: clientId
        )
    }

    mutating func approvalAuthentication(_ clientId: Int) -> MuscleAuthentication? {
        guard case .pendingApproval(let address, let respond, let driverId) = clientRegistry.phase(for: clientId) else {
            return nil
        }
        guard let approvedToken = tokenSource.uiApprovalPayload else {
            return nil
        }

        return MuscleAuthentication(
            clientId: clientId,
            address: address,
            driverIdentity: tokenSource.effectiveDriverId(driverId: driverId),
            respond: respond,
            source: .uiApproval(approvedToken: approvedToken)
        )
    }

    mutating func removeClient(_ clientId: Int) -> MuscleAdmissionEffect {
        let removed = clientRegistry.remove(clientId)
        guard case .pendingApproval = removed else { return .none }
        var effect = MuscleAdmissionEffect.none
        effect.dismissApprovalPrompt = true
        return effect
    }

    func authenticationDeadline(_ clientId: Int, deadlineSeconds: UInt64) -> MuscleAdmissionEffect {
        MuscleAuthenticationDeadlinePhase.effect(
            clientId: clientId,
            phase: clientRegistry.phase(for: clientId),
            deadlineSeconds: deadlineSeconds
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import Foundation
import os

import TheScore

let muscleAuthenticationLogger = Logger(subsystem: "com.buttonheist.theinsidejob", category: "auth")

/// Owns the authentication phases inside TheMuscle admission:
/// hello validation, token auth, UI approval, and lockout.
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

    var authenticatedClientIDs: Set<Int> {
        clientRegistry.authenticatedClientIDs
    }

    mutating func registerClientAddress(_ clientId: Int, address: String) {
        clientRegistry.registerAddress(clientId, address: address)
    }

    mutating func installAuthenticatedForTest(_ clientId: Int, address: String, driverIdentity: String) {
        clientRegistry.installAuthenticatedForTest(clientId, address: address, driverIdentity: driverIdentity)
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
        guard let envelope = decodeRequest(data) else {
            guard clientRegistry.phase(for: clientId)?.isAuthenticated == true else {
                return .handled(rejectUndecodableUnauthenticatedMessage(clientId, respond: respond))
            }
            return .handled(rejectUndecodableAuthenticatedMessage(clientId, respond: respond))
        }

        guard clientRegistry.phase(for: clientId)?.isAuthenticated == true else {
            return handleUnauthenticatedMessage(
                clientId,
                envelope: envelope,
                respond: respond,
                uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
            )
        }

        switch envelope.message {
        case .clientHello, .authenticate:
            return .handled(rejectAuthenticatedProtocolMessage(clientId, envelope: envelope, respond: respond))
        default:
            return .admitted(AdmittedClientMessage(clientId: clientId, envelope: envelope))
        }
    }

    mutating func handleUnauthenticatedMessage(
        _ clientId: Int,
        data: Data,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard let envelope = decodeRequest(data) else {
            return .handled(rejectUndecodableUnauthenticatedMessage(clientId, respond: respond))
        }
        return handleUnauthenticatedMessage(
            clientId,
            envelope: envelope,
            respond: respond,
            uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
        )
    }

    mutating func completeAuthentication(_ authentication: MuscleAuthentication) -> MuscleAdmissionEffect {
        clientRegistry.authenticate(
            authentication.clientId,
            address: authentication.address,
            driverIdentity: authentication.driverIdentity
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
        guard let phase = clientRegistry.phase(for: clientId),
              !phase.isAuthenticated else {
            return .none
        }

        let error: ServerError
        switch phase {
        case .pendingApproval:
            muscleAuthenticationLogger.warning(
                "Client \(clientId): approval timed out - user did not respond to the approval prompt on the device"
            )
            error = ServerError(
                kind: .authApprovalPending,
                message: "Approval timed out — user did not respond to the approval prompt on the device."
            )
        case .connected, .helloValidated:
            muscleAuthenticationLogger.warning("Client \(clientId) did not authenticate within \(deadlineSeconds)s deadline")
            error = ServerError(
                kind: .authFailure,
                message: "Authentication timed out after \(deadlineSeconds) seconds."
            )
        case .authenticated:
            return .none
        }

        return .client(.error(error), clientId: clientId, disconnect: true)
    }

    private mutating func handleUnauthenticatedMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard envelope.buttonHeistVersion == buttonHeistVersion else {
            muscleAuthenticationLogger.warning(
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
        respond: @escaping TheMuscleAdmission.ResponseHandler
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
        respond: @escaping TheMuscleAdmission.ResponseHandler,
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
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        uiApprovalUnavailableDiagnostic: SessionLease.SessionLockDiagnostic?
    ) -> MuscleAdmissionDecision {
        guard let phase = clientRegistry.phase(for: clientId) else {
            muscleAuthenticationLogger.warning("Client \(clientId) has no registered address, rejecting auth")
            return .handled(.response(
                .error(ServerError(kind: .authFailure, message: "Connection rejected.")),
                respond: respond,
                disconnect: clientId
            ))
        }

        if payload.token.isEmpty {
            return MuscleUIApprovalPhase.request(
                clientId,
                address: phase.address,
                driverId: payload.driverId,
                clientRegistry: &clientRegistry,
                tokenAdmission: tokenAdmission,
                respond: respond,
                uiApprovalUnavailableDiagnostic: uiApprovalUnavailableDiagnostic
            )
        }

        return MuscleTokenAuthenticationPhase.authenticate(
            clientId,
            address: phase.address,
            payload: payload,
            tokenAdmission: &tokenAdmission,
            respond: respond
        )
    }

    private func rejectUndecodableUnauthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Client \(clientId) sent unparsable message before authenticating")
        return .response(
            .error(ServerError(
                kind: .validationError,
                message: """
                    Could not decode client message before authentication. \
                    Check that the client and app are built from the same Button Heist version.
                    """
            )),
            respond: respond,
            disconnect: clientId
        )
    }

    private func rejectUndecodableAuthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Authenticated client \(clientId) sent unparsable message")
        return .response(
            .error(ServerError(kind: .general, message: "Malformed message — could not decode")),
            respond: respond
        )
    }

    private func rejectAuthenticatedProtocolMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        let name = envelope.message.canonicalName
        muscleAuthenticationLogger.warning(
            "Authenticated client \(clientId) sent protocol message \(name, privacy: .public) after admission"
        )
        return .response(
            .error(ServerError(
                kind: .validationError,
                message: "Protocol message \(name) is not an app command after authentication."
            )),
            requestId: envelope.requestId,
            respond: respond
        )
    }

    private func rejectUnauthenticatedMessage(
        _ clientId: Int,
        message: String,
        requestId: String?,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Client \(clientId) rejected before auth: \(message, privacy: .public)")
        return .response(
            .error(ServerError(kind: .authFailure, message: message)),
            requestId: requestId,
            respond: respond,
            disconnect: clientId
        )
    }

    private func decodeRequest(_ data: Data) -> RequestEnvelope? {
        do {
            return try RequestEnvelope.decoded(from: data)
        } catch {
            muscleAuthenticationLogger.error("Failed to decode client message: \(error)")
            return nil
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

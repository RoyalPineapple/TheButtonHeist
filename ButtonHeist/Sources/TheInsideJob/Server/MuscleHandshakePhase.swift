#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleHandshakePhase {
    static func handle(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        clientRegistry: inout TheMuscleClientRegistry,
        tokenAdmission: inout TokenAdmission
    ) -> MuscleAdmissionDecision {
        guard envelope.buttonHeistVersion == buttonHeistVersion else {
            return .handled([
                .log(.versionMismatch(
                    clientId: clientId,
                    serverVersion: buttonHeistVersion,
                    clientVersion: envelope.buttonHeistVersion
                )),
                .sendResponse(.protocolMismatch(ProtocolMismatchPayload(
                    serverButtonHeistVersion: buttonHeistVersion,
                    clientButtonHeistVersion: envelope.buttonHeistVersion
                )), requestId: nil, respond: respond),
                .delayedDisconnect(clientId: clientId),
            ])
        }

        switch envelope.message {
        case .clientHello:
            return handleClientHello(
                clientId,
                envelope: envelope,
                respond: respond,
                clientRegistry: &clientRegistry
            )
        case .authenticate(let payload):
            return handleAuthenticate(
                clientId,
                envelope: envelope,
                payload: payload,
                respond: respond,
                clientRegistry: &clientRegistry,
                tokenAdmission: &tokenAdmission
            )
        default:
            return .handled(MuscleAuthenticationRejection.unauthenticatedMessage(
                clientId,
                message: "Authentication required before \(envelope.message.wireType.rawValue).",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
    }

    private static func handleClientHello(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        clientRegistry: inout TheMuscleClientRegistry
    ) -> MuscleAdmissionDecision {
        switch clientRegistry.validateHello(clientId) {
        case .advanced:
            return .handled([
                .sendResponse(.authRequired, requestId: nil, respond: respond),
            ])
        case .missingClient:
            return .handled(MuscleAuthenticationRejection.unauthenticatedMessage(
                clientId,
                message: "Connection is not registered; reconnect before starting the auth handshake.",
                requestId: envelope.requestId,
                respond: respond
            ))
        case .rejected:
            return .handled(MuscleAuthenticationRejection.unauthenticatedMessage(
                clientId,
                message: "clientHello is only valid immediately after connection.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
    }

    private static func handleAuthenticate(
        _ clientId: Int,
        envelope: RequestEnvelope,
        payload: AuthenticatePayload,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        clientRegistry: inout TheMuscleClientRegistry,
        tokenAdmission: inout TokenAdmission
    ) -> MuscleAdmissionDecision {
        guard clientRegistry.phase(for: clientId)?.hasCompletedHello == true else {
            return .handled(MuscleAuthenticationRejection.unauthenticatedMessage(
                clientId,
                message: "Authentication requires clientHello first.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }

        guard let phase = clientRegistry.phase(for: clientId) else {
            return .handled([
                .log(.missingRegisteredAddress(clientId: clientId)),
                .sendResponse(
                    .error(ServerError(kind: .authFailure, message: "Connection rejected.")),
                    requestId: nil,
                    respond: respond
                ),
                .delayedDisconnect(clientId: clientId),
            ])
        }

        if payload.token.isEmpty {
            return .handled([
                .sendResponse(
                    .error(tokenAdmission.emptyTokenError()),
                    requestId: nil,
                    respond: respond
                ),
                .delayedDisconnect(clientId: clientId),
            ])
        }

        return MuscleTokenAuthenticationPhase.authenticate(
            clientId,
            address: phase.address,
            payload: payload,
            tokenAdmission: &tokenAdmission,
            respond: respond
        )
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

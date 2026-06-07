#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleHandshakePhase {
    static func handle(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        clientRegistry: inout TheMuscleClientRegistry,
        tokenAdmission: inout SessionAdmission
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
        guard clientRegistry.markHelloValidated(clientId) != nil else {
            return .handled(MuscleAuthenticationRejection.unauthenticatedMessage(
                clientId,
                message: "Connection is not registered; reconnect before starting the auth handshake.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
        return .handled(.response(.authRequired, respond: respond))
    }

    private static func handleAuthenticate(
        _ clientId: Int,
        envelope: RequestEnvelope,
        payload: AuthenticatePayload,
        respond: @escaping TheMuscleAdmission.ResponseHandler,
        clientRegistry: inout TheMuscleClientRegistry,
        tokenAdmission: inout SessionAdmission
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
            muscleAuthenticationLogger.warning("Client \(clientId) has no registered address, rejecting auth")
            return .handled(.response(
                .error(ServerError(kind: .authFailure, message: "Connection rejected.")),
                respond: respond,
                disconnect: clientId
            ))
        }

        if payload.token.isEmpty {
            return .handled(.response(.error(tokenAdmission.emptyTokenError()), respond: respond, disconnect: clientId))
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

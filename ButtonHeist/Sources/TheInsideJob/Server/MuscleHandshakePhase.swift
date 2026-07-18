#if canImport(UIKit)
#if DEBUG
import TheScore

extension ClientAdmission {
enum Handshake {
    static func admit(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler,
        clientRegistry: inout Registry,
        tokenAuthentication: inout TokenAuthentication
    ) -> Decision {
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
            return admitHello(
                clientId,
                envelope: envelope,
                respond: respond,
                clientRegistry: &clientRegistry
            )
        case .authenticate(let payload):
            return admitAuthentication(
                clientId,
                envelope: envelope,
                payload: payload,
                respond: respond,
                clientRegistry: &clientRegistry,
                tokenAuthentication: &tokenAuthentication
            )
        default:
            return .handled(Rejection.unauthenticatedMessage(
                clientId,
                message: "Authentication required before \(envelope.message.wireType.rawValue).",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
    }

    private static func admitHello(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler,
        clientRegistry: inout Registry
    ) -> Decision {
        switch clientRegistry.validateHello(clientId) {
        case .advanced:
            return .handled([
                .sendResponse(.authRequired, requestId: nil, respond: respond),
            ])
        case .missingClient:
            return .handled(Rejection.unauthenticatedMessage(
                clientId,
                message: "Connection is not registered; reconnect before starting the auth handshake.",
                requestId: envelope.requestId,
                respond: respond
            ))
        case .rejected:
            return .handled(Rejection.unauthenticatedMessage(
                clientId,
                message: "clientHello is only valid immediately after connection.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }
    }

    private static func admitAuthentication(
        _ clientId: Int,
        envelope: RequestEnvelope,
        payload: AuthenticatePayload,
        respond: @escaping ResponseHandler,
        clientRegistry: inout Registry,
        tokenAuthentication: inout TokenAuthentication
    ) -> Decision {
        guard clientRegistry.state(for: clientId)?.hasCompletedHello == true else {
            return .handled(Rejection.unauthenticatedMessage(
                clientId,
                message: "Authentication requires clientHello first.",
                requestId: envelope.requestId,
                respond: respond
            ))
        }

        guard let state = clientRegistry.state(for: clientId) else {
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

        return tokenAuthentication.admit(
            clientId,
            address: state.address,
            payload: payload,
            respond: respond
        )
    }
}
}
#endif // DEBUG
#endif // canImport(UIKit)

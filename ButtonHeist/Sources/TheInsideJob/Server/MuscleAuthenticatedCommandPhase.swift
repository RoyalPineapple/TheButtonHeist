#if canImport(UIKit)
#if DEBUG
import TheScore

extension ClientAdmission {
enum AuthenticatedCommand {
    static func admit(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler
    ) -> Decision {
        switch envelope.message {
        case .clientHello, .authenticate:
            return .handled(Rejection.authenticatedProtocolMessage(
                clientId,
                envelope: envelope,
                respond: respond
            ))
        default:
            return .admitted(AdmittedClientMessage(clientId: clientId, envelope: envelope))
        }
    }
}
}
#endif // DEBUG
#endif // canImport(UIKit)

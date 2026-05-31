#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleAuthenticatedCommandPhase {
    static func admit(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionDecision {
        switch envelope.message {
        case .clientHello, .authenticate:
            return .handled(MuscleAuthenticationRejection.authenticatedProtocolMessage(
                clientId,
                envelope: envelope,
                respond: respond
            ))
        default:
            return .admitted(AdmittedClientMessage(clientId: clientId, envelope: envelope))
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

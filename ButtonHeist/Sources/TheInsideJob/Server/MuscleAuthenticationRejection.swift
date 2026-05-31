#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleAuthenticationRejection {
    static func undecodableUnauthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Client \(clientId) sent unparsable message before authenticating")
        let error = ServerError(
            kind: .validationError,
            message: """
                Could not decode client message before authentication. \
                Check that the client and app are built from the same Button Heist version.
                """
        )
        return .response(.error(error), respond: respond, disconnect: clientId)
    }

    static func undecodableAuthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Authenticated client \(clientId) sent unparsable message")
        let error = ServerError(kind: .general, message: "Malformed message — could not decode")
        return .response(.error(error), respond: respond)
    }

    static func authenticatedProtocolMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        let name = envelope.message.wireType.rawValue
        muscleAuthenticationLogger.warning(
            "Authenticated client \(clientId) sent protocol message \(name, privacy: .public) after admission"
        )
        let error = ServerError(
            kind: .validationError,
            message: "Protocol message \(name) is not an app command after authentication."
        )
        return .response(.error(error), requestId: envelope.requestId, respond: respond)
    }

    static func unauthenticatedMessage(
        _ clientId: Int,
        message: String,
        requestId: String?,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> MuscleAdmissionEffect {
        muscleAuthenticationLogger.warning("Client \(clientId) rejected before auth: \(message, privacy: .public)")
        let error = ServerError(kind: .authFailure, message: message)
        return .response(.error(error), requestId: requestId, respond: respond, disconnect: clientId)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleAuthenticationRejection {
    static func undecodableUnauthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let error = ServerError(
            kind: .validationError,
            message: """
                Could not decode client message before authentication. \
                Check that the client and app are built from the same Button Heist version.
                """
        )
        return [
            .log(.undecodableUnauthenticatedMessage(clientId: clientId)),
            .sendResponse(.error(error), requestId: nil, respond: respond),
            .delayedDisconnect(clientId: clientId),
        ]
    }

    static func undecodableAuthenticatedMessage(
        _ clientId: Int,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let error = ServerError(kind: .general, message: "Malformed message — could not decode")
        return [
            .log(.undecodableAuthenticatedMessage(clientId: clientId)),
            .sendResponse(.error(error), requestId: nil, respond: respond),
        ]
    }

    static func authenticatedProtocolMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let error = ServerError(
            kind: .validationError,
            message: "Protocol message \(envelope.message.wireType.rawValue) is not an app command after authentication."
        )
        return [
            .log(.authenticatedProtocolMessage(clientId: clientId, wireType: envelope.message.wireType)),
            .sendResponse(.error(error), requestId: envelope.requestId, respond: respond),
        ]
    }

    static func unauthenticatedMessage(
        _ clientId: Int,
        message: String,
        requestId: String?,
        respond: @escaping TheMuscleAdmission.ResponseHandler
    ) -> [MuscleAdmissionEffect] {
        let error = ServerError(kind: .authFailure, message: message)
        return [
            .log(.unauthenticatedMessage(clientId: clientId, message: message)),
            .sendResponse(.error(error), requestId: requestId, respond: respond),
            .delayedDisconnect(clientId: clientId),
        ]
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

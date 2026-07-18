#if canImport(UIKit)
#if DEBUG
import TheScore

extension ClientAdmission {
enum Rejection {
    static func undecodableUnauthenticatedMessage(
        _ clientId: Int,
        respond: @escaping ResponseHandler
    ) -> [Effect] {
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
        respond: @escaping ResponseHandler
    ) -> [Effect] {
        let error = ServerError(kind: .general, message: "Malformed message — could not decode")
        return [
            .log(.undecodableAuthenticatedMessage(clientId: clientId)),
            .sendResponse(.error(error), requestId: nil, respond: respond),
        ]
    }

    static func authenticatedProtocolMessage(
        _ clientId: Int,
        envelope: RequestEnvelope,
        respond: @escaping ResponseHandler
    ) -> [Effect] {
        let message: ServerErrorMessage
        do {
            message = try ServerErrorMessage(
                validating: "Protocol message \(envelope.message.wireType.rawValue) is not an app command after authentication."
            )
        } catch {
            return [.log(.authenticatedProtocolMessage(
                clientId: clientId,
                wireType: envelope.message.wireType
            ))]
        }
        let error = ServerError(kind: .validationError, message: message)
        return [
            .log(.authenticatedProtocolMessage(clientId: clientId, wireType: envelope.message.wireType)),
            .sendResponse(.error(error), requestId: envelope.requestId, respond: respond),
        ]
    }

    static func unauthenticatedMessage(
        _ clientId: Int,
        message: String,
        requestId: RequestID?,
        respond: @escaping ResponseHandler
    ) -> [Effect] {
        let serverMessage: ServerErrorMessage
        do {
            serverMessage = try ServerErrorMessage(validating: message)
        } catch {
            return [
                .log(.unauthenticatedMessage(clientId: clientId, message: message)),
                .delayedDisconnect(clientId: clientId),
            ]
        }
        let error = ServerError(kind: .authFailure, message: serverMessage)
        return [
            .log(.unauthenticatedMessage(clientId: clientId, message: message)),
            .sendResponse(.error(error), requestId: requestId, respond: respond),
            .delayedDisconnect(clientId: clientId),
        ]
    }
}
}
#endif // DEBUG
#endif // canImport(UIKit)

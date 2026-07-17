#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleAuthenticationDeadlinePhase {
    static func effect(
        clientId: Int,
        phase: ClientAuthenticationState?,
        deadlineSeconds: UInt64
    ) -> [MuscleAdmissionEffect] {
        guard let phase, !phase.isAuthenticated else { return [] }

        let message: ServerErrorMessage
        do {
            message = try ServerErrorMessage(
                validating: "Authentication timed out after \(deadlineSeconds) seconds."
            )
        } catch {
            return [
                .log(.authenticationDeadline(clientId: clientId, deadlineSeconds: deadlineSeconds)),
                .delayedDisconnect(clientId: clientId),
            ]
        }
        let error = ServerError(kind: .authFailure, message: message)

        return [
            .log(.authenticationDeadline(clientId: clientId, deadlineSeconds: deadlineSeconds)),
            .sendClient(.error(error), requestId: nil, clientId: clientId),
            .delayedDisconnect(clientId: clientId),
        ]
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

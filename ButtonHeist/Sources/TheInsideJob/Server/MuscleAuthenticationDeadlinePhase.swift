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

        let error = ServerError(
            kind: .authFailure,
            message: "Authentication timed out after \(deadlineSeconds) seconds."
        )

        return [
            .log(.authenticationDeadline(clientId: clientId, deadlineSeconds: deadlineSeconds)),
            .sendClient(.error(error), requestId: nil, clientId: clientId),
            .delayedDisconnect(clientId: clientId),
        ]
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

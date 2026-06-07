#if canImport(UIKit)
#if DEBUG
import TheScore

struct MuscleAuthenticationDeadlinePhase {
    static func effect(
        clientId: Int,
        phase: ClientAuthenticationState?,
        deadlineSeconds: UInt64
    ) -> MuscleAdmissionEffect {
        guard let phase, !phase.isAuthenticated else { return .none }

        muscleAuthenticationLogger.warning("Client \(clientId) did not authenticate within \(deadlineSeconds)s deadline")
        let error = ServerError(
            kind: .authFailure,
            message: "Authentication timed out after \(deadlineSeconds) seconds."
        )

        return .client(.error(error), clientId: clientId, disconnect: true)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

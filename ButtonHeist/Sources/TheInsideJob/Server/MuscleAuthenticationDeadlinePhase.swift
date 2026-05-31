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

        let error: ServerError
        switch phase {
        case .pendingApproval:
            muscleAuthenticationLogger.warning(
                "Client \(clientId): approval timed out - user did not respond to the approval prompt on the device"
            )
            error = ServerError(
                kind: .authApprovalPending,
                message: "Approval timed out — user did not respond to the approval prompt on the device."
            )
        case .connected, .helloValidated:
            muscleAuthenticationLogger.warning("Client \(clientId) did not authenticate within \(deadlineSeconds)s deadline")
            error = ServerError(
                kind: .authFailure,
                message: "Authentication timed out after \(deadlineSeconds) seconds."
            )
        case .authenticated: return .none
        }

        return .client(.error(error), clientId: clientId, disconnect: true)
    }
}
#endif // DEBUG
#endif // canImport(UIKit)

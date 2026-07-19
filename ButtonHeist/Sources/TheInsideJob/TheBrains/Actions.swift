#if canImport(UIKit)
#if DEBUG

@MainActor
final class Actions {

    let vault: TheVault
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let accessibilityActions = AccessibilityActionDispatcher()

    init(
        vault: TheVault,
        safecracker: TheSafecracker,
        tripwire: TheTripwire,
        navigation: Navigation
    ) {
        self.vault = vault
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    func staleLiveTargetFailure(
        _ staleness: TheVault.LiveTargetStaleness<HeistId>,
        payload: ActionResult.Payload
    ) -> TheSafecracker.ActionDispatchResult {
        .failure(
            payload,
            message: staleness.message,
            failureKind: .targetUnavailable
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG

@MainActor
final class Actions {

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let accessibilityActions = AccessibilityActionDispatcher()

    init(
        stash: TheStash,
        safecracker: TheSafecracker,
        tripwire: TheTripwire,
        navigation: Navigation
    ) {
        self.stash = stash
        self.safecracker = safecracker
        self.tripwire = tripwire
        self.navigation = navigation
    }

    func staleLiveTargetFailure(
        _ staleness: TheStash.LiveTargetStaleness<HeistId>,
        method: ActionMethod
    ) -> TheSafecracker.ActionDispatchOutcome {
        .failure(
            method,
            message: staleness.message,
            failureKind: .targetUnavailable
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

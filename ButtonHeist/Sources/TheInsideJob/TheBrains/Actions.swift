#if canImport(UIKit)
#if DEBUG

/// Actions — shared runtime dependencies for action execution families.
///
/// Internal component of TheBrains. The execution methods live in focused
/// extensions by action family.
@MainActor
final class Actions {

    // MARK: - Properties

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let accessibilityActions = AccessibilityActionDispatcher()

    // MARK: - Init

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
}

#endif // DEBUG
#endif // canImport(UIKit)

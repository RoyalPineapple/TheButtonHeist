#if canImport(UIKit)
#if DEBUG
import TheScore

/// The brains of the operation — plans the play, sequences the crew.
///
/// TheBrains takes a command and works it through to a result by coordinating
/// TheStash (the screen value), TheSafecracker (gestures), and TheTripwire
/// (timing). Command dispatch, scroll/explore, action handlers, and
/// post-action observation are internal components with separate owners.
@MainActor
final class TheBrains {

    // Keep this literal in sync with `FenceResponse.accessibilityTreeUnavailableMessage`;
    // TheFence uses it to enrich wire-shaped `actionFailed` results locally.
    static let treeUnavailableMessage = "Could not access accessibility tree: no traversable app windows"

    let stash: TheStash
    let safecracker: TheSafecracker
    let tripwire: TheTripwire
    let navigation: Navigation
    let actions: Actions
    let postActionObservation: PostActionObservation
    let waitForChangeState = WaitForChangeState()

    enum InterfaceObservation {
        case success(Interface)
        case failure(InterfaceObservationError)
    }

    enum InterfaceObservationError: Error, Equatable {
        case rootViewUnavailable
        case selection(InterfaceSelectionError)

        var message: String {
            switch self {
            case .rootViewUnavailable:
                return "Could not access root view"
            case .selection(let error):
                return error.message
            }
        }
    }

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        let stash = TheStash(tripwire: tripwire)
        let safecracker = TheSafecracker()
        self.stash = stash
        self.safecracker = safecracker
        let navigation = Navigation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire
        )
        self.navigation = navigation
        self.actions = Actions(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            navigation: navigation
        )
        self.postActionObservation = PostActionObservation(
            stash: stash,
            safecracker: safecracker,
            tripwire: tripwire,
            navigation: navigation
        )
    }

    // MARK: - Refresh Convenience

    /// Refresh the accessibility tree into the stash. Returns the new Screen
    /// or nil if the parser couldn't produce one. Callers in an exploration
    /// cycle should use `stash.parse()` directly and accumulate into a local
    /// union — TheStash has no mode flag.
    @discardableResult
    func refresh() -> Screen? {
        stash.refresh()
    }

    func treeUnavailableResult(method: ActionMethod) -> ActionResult {
        var builder = ActionResultBuilder(method: method)
        builder.message = TheBrains.treeUnavailableMessage
        return builder.failure(errorKind: .actionFailed)
    }

    // MARK: - Clear

    func clearCache() {
        stash.clearCache()
        navigation.clearCache()
        waitForChangeState.resetDeliveredBaseline()
    }

    // MARK: - Response State Tracking

    /// Snapshot current state as "last sent" — call after every response to the driver.
    func recordSentState() {
        waitForChangeState.recordDeliveredBaseline(postActionObservation.captureSemanticState())
    }

    func observeInterface(_ query: InterfaceQuery) async -> InterfaceObservation {
        _ = await tripwire.waitForAllClear(timeout: 0.5)

        guard refresh() != nil else {
            return .failure(.rootViewUnavailable)
        }

        _ = await navigation.exploreAndPrune()
        do {
            let interface = try InterfaceSelector(interface: stash.interface()).select(query)
            return .success(interface)
        } catch {
            return .failure(.selection(error))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

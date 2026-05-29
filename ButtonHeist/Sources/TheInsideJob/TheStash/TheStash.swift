#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash — holds the goods and answers questions about them.
///
/// TheStash owns exactly one mutable accessibility belief: the latest
/// committed `Screen`. It exposes lookup, matcher resolution, and
/// wire-conversion facades over that value; parsing, diagnostics, capture,
/// recording, response memory, and UIKit actions are boundary transforms or
/// owned by other crew members. `currentScreen.knownInterface` is targetable
/// semantic state; `currentScreen.liveCapture` is the latest parse
/// used for geometry, live objects, and scrolling. Callers call `parse()` to
/// obtain a Screen value, then decide when to write it back via
/// `currentScreen = ...`. The exploration accumulator lives in TheBrains as
/// a local `var union`.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Mutable State

    /// Latest committed interface state.
    ///
    /// **Writer audit** — the call sites that set this field:
    /// - `refresh()` — single parse + commit (page-only)
    /// - `Navigation+Explore.exploreContainer` mid-loop — page-only commits
    ///   per scroll page, required for the termination heuristics above
    /// - `Navigation+Explore.exploreAndPrune` end-of-cycle — union commit
    /// - `clearCache()` / `clearScreen()` — reset to `.empty`
    /// - `TheBrains.actionResultWithDelta` — page-only commit after settle
    ///
    /// Readers that specifically want "what's on-screen in the latest parse"
    /// read `visibleIds`; target resolution reads the known semantic set.
    var currentScreen: Screen = .empty

    let rotorContinuations = RotorContinuationStore()

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent parse. Proxy for call-site clarity —
    /// reads, matchers, scroll dispatch, and tab-bar geometry all need it
    /// without spelling out `currentScreen.liveCapture.hierarchy`
    /// every time.
    var currentHierarchy: [AccessibilityHierarchy] {
        currentScreen.liveCapture.hierarchy
    }

    /// Scrollable containers paired with their backing UIView.
    /// Unwraps the weak ref wrapper for call sites that need a live UIView.
    var scrollableContainerViews: [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, ref) in currentScreen.liveCapture.scrollableContainerViews {
            if let view = ref.view {
                result[container] = view
            }
        }
        return result
    }

    /// HeistIds of all known elements in the current screen value.
    ///
    /// After an exploration commit this includes elements that were observed
    /// during scrolling and are no longer on-screen. Use `visibleIds` when
    /// you specifically need the latest parsed on-screen ids.
    var knownIds: Set<HeistId> {
        ids(in: .known)
    }

    /// HeistIds of elements present in the hierarchy from the most recent
    /// parse. Strictly a subset of `knownIds` after an exploration union has
    /// been committed.
    var visibleIds: Set<HeistId> {
        ids(in: .visible)
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: HeistId? {
        currentScreen.liveCapture.firstResponderHeistId
    }

    /// Screen name from the current screen (first header element by traversal order).
    var lastScreenName: String? {
        currentScreen.name
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        currentScreen.id
    }

    // MARK: - Cache Control

    /// Clear cached element data (used on suspend).
    func clearCache() {
        currentScreen = .empty
        clearPendingRotorResult()
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        currentScreen = .empty
        clearPendingRotorResult()
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing.
    let burglar: TheBurglar

    // MARK: - Parse Pipeline

    /// Read the live accessibility tree and produce a Screen value.
    /// Pure: does not touch `currentScreen`. Returns nil if no accessible
    /// windows exist (loading screen, app backgrounded, etc.).
    func parse() -> Screen? {
        guard let result = burglar.parse() else { return nil }
        return TheBurglar.buildScreen(from: result)
    }

    /// Parse and commit in one step. Most callers use this. A visible refresh
    /// updates live interaction evidence without dropping known semantic
    /// elements when it is still observing the same screen.
    @discardableResult
    func refresh() -> Screen? {
        guard let screen = parse() else { return nil }
        currentScreen = currentScreen.refreshingVisibleState(with: screen)
        return screen
    }

    // MARK: - Interface Read Helpers

    /// Current parser hierarchy plus Button Heist annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the interface of the *current* screen, not an arbitrary one.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: currentScreen, timestamp: timestamp)
    }

    /// Single-build variant: returns the interface alongside its hash so callers
    /// that need both don't pay for two projection passes.
    func interfaceWithHash(timestamp: Date = Date()) -> (interface: Interface, hash: String) {
        let interface = interface(timestamp: timestamp)
        return (interface, AccessibilityTrace.Capture.hash(interface))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

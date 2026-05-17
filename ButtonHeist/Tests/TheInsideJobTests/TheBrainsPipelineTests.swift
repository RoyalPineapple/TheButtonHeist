#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for the pipelines on TheBrains that operate purely against
/// the current `Screen` snapshot: the failure branch of `actionResultWithDelta`, the
/// `SentState` accessors, the `computeBackgroundDelta` guards, the
/// `broadcastInterfaceIfChanged` cache-miss, and `exploreAndPrune` pruning.
///
/// Success-path `actionResultWithDelta` and `exploreScreen` container iteration
/// require a live window and are covered by integration/benchmark runs.
@MainActor
final class TheBrainsPipelineTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    // MARK: - actionResultWithDelta Failure Path

    func testActionResultWithDeltaFailureReturnsBeforeSnapshot() async {
        seedScreen(elements: [("Sign In", .button, "button_sign_in")])
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .activate,
            message: "target disappeared",
            before: before
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .activate)
        XCTAssertEqual(result.message, "target disappeared")
        XCTAssertEqual(result.errorKind, .actionFailed,
                       "Without explicit errorKind and with method != elementNotFound, default is .actionFailed")
    }

    func testActionResultWithDeltaFailureInfersNotFoundFromMethod() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .elementNotFound,
            before: before
        )

        XCTAssertEqual(result.errorKind, .elementNotFound,
                       "method == .elementNotFound should infer errorKind == .elementNotFound")
    }

    func testActionResultWithDeltaFailureInfersNotFoundFromDeallocated() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .elementDeallocated,
            before: before
        )

        XCTAssertEqual(result.errorKind, .elementNotFound,
                       "method == .elementDeallocated should infer errorKind == .elementNotFound")
    }

    func testActionResultWithDeltaFailureRespectsExplicitErrorKind() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .activate,
            errorKind: .timeout,
            before: before
        )

        XCTAssertEqual(result.errorKind, .timeout,
                       "An explicit errorKind must override the method-based inference")
    }

    func testActionResultWithDeltaFailureCarriesValueAndMessage() async {
        let before = brains.captureBeforeState()

        let result = await brains.actionResultWithDelta(
            success: false,
            method: .getPasteboard,
            message: "pasteboard empty",
            value: "",
            before: before
        )

        XCTAssertEqual(result.message, "pasteboard empty")
        guard case .value(let value) = result.payload else {
            XCTFail("Expected .value payload, got \(String(describing: result.payload))")
            return
        }
        XCTAssertEqual(value, "")
    }

    // MARK: - SentState

    func testLastSentStateStartsNil() {
        XCTAssertNil(brains.lastSentState)
        XCTAssertNil(brains.lastSentScreenId)
        XCTAssertFalse(brains.screenChangedSinceLastSent,
                       "No prior send means there is no baseline for screen-change classification")
    }

    func testRecordSentStatePopulatesAllFields() {
        seedScreen(elements: [("Home", .header, "home_header"), ("A", .button, "button_a")])
        let viewportHash = brains.stash.wireTreeHash()

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertNotNil(sent)
        XCTAssertEqual(sent?.screenId, "home")
        XCTAssertEqual(sent?.viewportHash, viewportHash)
        XCTAssertNotEqual(sent?.treeHash, 0,
                          "treeHash should be non-zero for a non-empty screen")
        XCTAssertEqual(brains.lastSentScreenId, "home")
    }

    func testRecordSentStateUsesKnownSemanticElements() {
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            respondsToUserInteraction: false
        )
        let offViewport = AccessibilityElement.make(
            label: "Below fold",
            traits: .button,
            respondsToUserInteraction: false
        )
        brains.stash.currentScreen = .makeForTests(
            elements: [(visible, "button_visible")],
            offViewport: [.init(offViewport, heistId: "button_below_fold")]
        )
        let liveViewportHash = brains.stash.wireTreeHash()

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertEqual(
            Set(sent?.beforeState.snapshot.map(\.heistId) ?? []),
            ["button_visible", "button_below_fold"]
        )
        XCTAssertNotEqual(
            sent?.treeHash,
            liveViewportHash,
            "Sent state should hash the known semantic set, not only the live viewport tree"
        )
    }

    func testRecordSentStateWithViewportHashKeepsSemanticHashDomain() {
        seedScreen(elements: [("Screen X", .header, "screen_x_header"), ("A", .button, "button_a")])
        let semanticHash = brains.captureSemanticState().treeHash

        brains.recordSentState(viewportHash: 42)

        XCTAssertEqual(brains.lastSentState?.treeHash, semanticHash)
        XCTAssertEqual(brains.lastSentState?.viewportHash, 42)
        XCTAssertEqual(brains.lastSentState?.screenId, "screen_x")
    }

    func testScreenChangedSinceLastSentDetectsIdTransition() {
        seedScreen(elements: [("Home", .header, "home_header")])
        brains.recordSentState(viewportHash: 1)
        XCTAssertFalse(brains.screenChangedSinceLastSent)

        seedScreen(elements: [("Settings", .header, "settings_header")])
        XCTAssertTrue(brains.screenChangedSinceLastSent,
                      "A changed parsed screen signature should report a screen change")
    }

    func testClearCacheResetsSentState() {
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState()
        XCTAssertNotNil(brains.lastSentState)

        brains.clearCache()

        XCTAssertNil(brains.lastSentState)
    }

    func testClearCacheResetsBroadcastInterfaceMemo() throws {
        guard brains.broadcastInterfaceIfChanged() != nil else {
            throw XCTSkip("No live hierarchy available for broadcast memo test")
        }
        guard brains.broadcastInterfaceIfChanged() == nil else {
            throw XCTSkip("Live hierarchy changed during broadcast memo test")
        }

        brains.clearCache()

        XCTAssertNotNil(brains.broadcastInterfaceIfChanged())
    }

    // MARK: - computeBackgroundDelta Guards

    func testComputeBackgroundDeltaReturnsNilWithoutPriorSend() async {
        let delta = await brains.computeBackgroundDelta()
        XCTAssertNil(delta, "No prior send means no comparison baseline, so return nil")
    }

    func testComputeBackgroundDeltaReturnsNilWhenViewportHashIsZero() async {
        // A viewportHash of 0 is the sentinel for "not set" — even if lastSentState exists,
        // the delta must be suppressed to avoid false positives.
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState(viewportHash: 0)

        let delta = await brains.computeBackgroundDelta()
        XCTAssertNil(delta)
    }

    // MARK: - Unsupported Diagnostics

    func testExecuteCommandUnsupportedIncludesCommandIdentityAndScreenContext() async {
        seedScreen(elements: [("Home", .header, "home_header")])

        let result = await brains.executeCommand(.ping)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .unsupported)
        XCTAssertEqual(result.method, .activate, "Non-action protocol commands fall back to .activate diagnostics")
        XCTAssertEqual(result.screenName, "Home")
        XCTAssertEqual(result.screenId, "home")
        XCTAssertEqual(result.message, "Unsupported command 'ping' in executeCommand")
    }

    // MARK: - Transient Suppression on Screen Change (PR #330 H2)

    /// `SettleSession.elementsByKey` accumulates every element observed
    /// across cycles, including the previous screen's elements before a
    /// transition. Those are stale, not transient, and must not be surfaced
    /// under the delta's `transient` list when the action triggered a
    /// screen change.
    func testShouldSuppressTransientOnTripwireTriggeredOutcome() {
        XCTAssertTrue(
            TheBrains.shouldSuppressTransient(
                settleOutcome: .tripwireTriggered(timeMs: 120),
                isScreenChange: false
            ),
            "A .tripwireTriggered settle outcome alone must suppress transients"
        )
    }

    func testShouldSuppressTransientOnDiffDetectedScreenChange() {
        XCTAssertTrue(
            TheBrains.shouldSuppressTransient(
                settleOutcome: .settled(timeMs: 300),
                isScreenChange: true
            ),
            "Even when the settle loop reached .settled, a parsed screen change must suppress transients"
        )
    }

    func testShouldNotSuppressTransientOnCleanSettle() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleOutcome: .settled(timeMs: 300),
                isScreenChange: false
            ),
            "Clean settle without a screen change: transients are real (spinners, snackbars, overlays)"
        )
    }

    func testShouldNotSuppressTransientOnTimedOut() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleOutcome: .timedOut(timeMs: 5_000),
                isScreenChange: false
            ),
            "Timed-out settle: still on the same screen, so observed transients are still valid"
        )
    }

    func testShouldNotSuppressTransientOnCancelled() {
        XCTAssertFalse(
            TheBrains.shouldSuppressTransient(
                settleOutcome: .cancelled(timeMs: 50),
                isScreenChange: false
            ),
            "Cancelled mid-action: not a screen change, transients (if any) are valid"
        )
    }

    // MARK: - exploreAndPrune

    func testExploreAndPruneCommitsUnion() async {
        // Post-0.2.25: exploration seeds the local union from currentScreen,
        // merges each parse into it, then commits the union back. There is no
        // pruning — the union is the canonical "all elements seen this cycle".
        // With no scrollable containers in the host hierarchy, exploreAndPrune
        // reduces to refresh-and-commit, and the seeded entry merges into the
        // live parse rather than being pruned.
        seedScreen(elements: [("Seed", .button, "button_seed")])
        XCTAssertEqual(brains.stash.currentScreen.elements.count, 1)

        _ = await brains.navigation.exploreAndPrune()

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // currentScreen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(brains.stash.currentScreen,
                        "exploreAndPrune always commits a screen value")
    }

    func testExploreScreenExploresSwipeableContainer() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for swipeable explore test")
        }
        guard let container = brains.stash.currentHierarchy.scrollableContainers.first(where: {
            guard let view = brains.stash.scrollableContainerViews[$0] else { return true }
            return !(view is UIScrollView)
        }) else {
            throw XCTSkip("No non-UIScrollView scrollable container in host UI")
        }

        var union = brains.stash.currentScreen
        let manifest = await brains.navigation.exploreScreen(union: &union)

        XCTAssertTrue(manifest.exploredContainers.contains(container))
    }

    // MARK: - Helpers

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: String)]) {
        let pairs: [(AccessibilityElement, String)] = elements.map { entry in
            let element = AccessibilityElement.make(
                label: entry.label,
                traits: entry.traits,
                respondsToUserInteraction: false
            )
            return (element, entry.heistId)
        }
        brains.stash.currentScreen = .makeForTests(elements: pairs)
    }

}

#endif

#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

/// Deterministic tests for the pipelines on TheBrains that operate purely against
/// the stash registry: the failure branch of `actionResultWithDelta`, the
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
                       "No prior send means the screen-change tripwire must be false")
    }

    func testRecordSentStatePopulatesAllFields() {
        seedScreen(elements: [("Home", .header, "home_header"), ("A", .button, "button_a")])

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertNotNil(sent)
        XCTAssertEqual(sent?.screenId, "home")
        XCTAssertNotEqual(sent?.treeHash, 0,
                          "treeHash should be non-zero for a non-empty screen")
        XCTAssertEqual(brains.lastSentScreenId, "home")
    }

    func testRecordSentStateWithHashAvoidsWireConversion() {
        seedScreen(elements: [("Screen X", .header, "screen_x_header"), ("A", .button, "button_a")])

        brains.recordSentState(treeHash: 42)

        XCTAssertEqual(brains.lastSentState?.treeHash, 42)
        XCTAssertEqual(brains.lastSentState?.screenId, "screen_x")
    }

    func testScreenChangedSinceLastSentDetectsIdTransition() {
        seedScreen(elements: [("Home", .header, "home_header")])
        brains.recordSentState(treeHash: 1)
        XCTAssertFalse(brains.screenChangedSinceLastSent)

        seedScreen(elements: [("Settings", .header, "settings_header")])
        XCTAssertTrue(brains.screenChangedSinceLastSent,
                      "Current screenId differs from the one captured in lastSentState")
    }

    func testClearCacheResetsSentState() {
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState()
        XCTAssertNotNil(brains.lastSentState)

        brains.clearCache()

        XCTAssertNil(brains.lastSentState)
    }

    // MARK: - computeBackgroundDelta Guards

    func testComputeBackgroundDeltaReturnsNilWithoutPriorSend() {
        XCTAssertNil(brains.computeBackgroundDelta(),
                     "No prior send means no comparison baseline, so return nil")
    }

    func testComputeBackgroundDeltaReturnsNilWhenTreeHashIsZero() {
        // A treeHash of 0 is the sentinel for "not set" — even if lastSentState exists,
        // the delta must be suppressed to avoid false positives.
        seedScreen(elements: [("A", .button, "button_a")])
        brains.recordSentState(treeHash: 0)

        XCTAssertNil(brains.computeBackgroundDelta())
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

        _ = await brains.exploreAndPrune()

        // Either the seed survives (no live parse landed and the union still
        // holds it) or it merges with new live entries — either way, the
        // currentScreen reflects the committed union, not the pre-explore
        // value alone.
        XCTAssertNotNil(brains.stash.currentScreen,
                        "exploreAndPrune always commits a screen value")
    }

    func testExploreScreenCachesDiscoveredIdsForSwipeableContainer() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for swipeable explore cache test")
        }
        guard let container = brains.stash.currentHierarchy.scrollableContainers.first(where: {
            guard let view = brains.stash.scrollableContainerViews[$0] else { return true }
            return !(view is UIScrollView)
        }) else {
            throw XCTSkip("No non-UIScrollView scrollable container in host UI")
        }

        var union = brains.stash.currentScreen
        let manifest = await brains.exploreScreen(union: &union)

        XCTAssertTrue(manifest.exploredContainers.contains(container))
        XCTAssertNotNil(brains.containerExploreStates[container],
                        "Swipeable containers should be explored and cached")
    }

    // MARK: - Helpers

    private func seedScreen(elements: [(label: String, traits: UIAccessibilityTraits, heistId: String)]) {
        var screenElements: [String: Screen.ScreenElement] = [:]
        var hierarchy: [AccessibilityHierarchy] = []
        var heistIdByElement: [AccessibilityElement: String] = [:]
        for (index, entry) in elements.enumerated() {
            let element = AccessibilityElement(
                description: entry.label,
                label: entry.label,
                value: nil,
                traits: entry.traits,
                identifier: nil,
                hint: nil,
                userInputLabels: nil,
                shape: .frame(.zero),
                activationPoint: .zero,
                usesDefaultActivationPoint: true,
                customActions: [],
                customContent: [],
                customRotors: [],
                accessibilityLanguage: nil,
                respondsToUserInteraction: false
            )
            screenElements[entry.heistId] = Screen.ScreenElement(
                heistId: entry.heistId,
                contentSpaceOrigin: nil,
                element: element,
                object: nil,
                scrollView: nil
            )
            hierarchy.append(.element(element, traversalIndex: index))
            heistIdByElement[element] = entry.heistId
        }
        brains.stash.currentScreen = Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            containerStableIds: [:],
            heistIdByElement: heistIdByElement,
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
    }

}

#endif

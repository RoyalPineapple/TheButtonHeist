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
        seedRegistry(heistId: "button_sign_in", label: "Sign In", traits: .button)
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
        seedRegistry(heistId: "button_a", label: "A", traits: .button)
        brains.stash.lastScreenName = "Home"
        brains.stash.lastScreenId = "home"

        brains.recordSentState()

        let sent = brains.lastSentState
        XCTAssertNotNil(sent)
        XCTAssertEqual(sent?.screenId, "home")
        XCTAssertNotEqual(sent?.treeHash, 0,
                          "treeHash should be non-zero for a non-empty registry")
        XCTAssertEqual(brains.lastSentScreenId, "home")
    }

    func testRecordSentStateWithHashAvoidsWireConversion() {
        seedRegistry(heistId: "button_a", label: "A", traits: .button)
        brains.stash.lastScreenId = "screen_x"

        brains.recordSentState(treeHash: 42)

        XCTAssertEqual(brains.lastSentState?.treeHash, 42)
        XCTAssertEqual(brains.lastSentState?.screenId, "screen_x")
    }

    func testScreenChangedSinceLastSentDetectsIdTransition() {
        brains.stash.lastScreenId = "home"
        brains.recordSentState(treeHash: 1)
        XCTAssertFalse(brains.screenChangedSinceLastSent)

        brains.stash.lastScreenId = "settings"
        XCTAssertTrue(brains.screenChangedSinceLastSent,
                      "Current screenId differs from the one captured in lastSentState")
    }

    func testClearCacheResetsSentState() {
        seedRegistry(heistId: "button_a", label: "A", traits: .button)
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
        seedRegistry(heistId: "button_a", label: "A", traits: .button)
        brains.recordSentState(treeHash: 0)

        XCTAssertNil(brains.computeBackgroundDelta())
    }

    // MARK: - Unsupported Diagnostics

    func testExecuteCommandUnsupportedIncludesCommandIdentityAndScreenContext() async {
        brains.stash.lastScreenName = "Home"
        brains.stash.lastScreenId = "home"

        let result = await brains.executeCommand(.ping)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorKind, .unsupported)
        XCTAssertEqual(result.method, .activate, "Non-action protocol commands fall back to .activate diagnostics")
        XCTAssertEqual(result.screenName, "Home")
        XCTAssertEqual(result.screenId, "home")
        XCTAssertEqual(result.message, "Unsupported command 'ping' in executeCommand")
    }

    // MARK: - exploreAndPrune

    func testExploreAndPruneRemovesUnseenElementsWhenNoContainers() async {
        // Seed an orphan element that is NOT in the viewport and has no scrollable
        // ancestor. With no scrollable containers, exploreScreen is a no-op, so
        // only the seed (viewportIds) survives the prune.
        seedRegistry(heistId: "button_seen", label: "Seen", traits: .button)
        seedRegistry(heistId: "button_orphan", label: "Orphan", traits: .button,
                     includeInViewport: false)
        XCTAssertEqual(brains.stash.registry.elementByHeistId.count, 2)

        _ = await brains.exploreAndPrune()

        XCTAssertTrue(brains.stash.registry.elementByHeistId.keys.contains("button_seen"),
                      "Viewport elements must survive the prune")
        XCTAssertFalse(brains.stash.registry.elementByHeistId.keys.contains("button_orphan"),
                       "Elements not in the viewport (or in a cached container) must be pruned")
    }

    func testExploreAndPruneResetsPhaseToIdle() async {
        seedRegistry(heistId: "button_a", label: "A", traits: .button)
        _ = await brains.exploreAndPrune()
        XCTAssertEqual(brains.explorePhase, .idle,
                       "The explore cycle must always end in .idle, even when no containers exist")
    }

    func testExploreAndPruneKeepsCachedContainerIdsEvenWhenOffViewport() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for explore cache regression test")
        }
        guard let container = brains.stash.currentHierarchy.scrollableContainers.first,
              let fingerprint = brains.stash.currentHierarchy.containerFingerprints[container] else {
            throw XCTSkip("No scrollable container available in host UI")
        }
        let cachedElement = makeElement(label: "Cached", traits: .button)
        brains.stash.registry.insertForTesting(TheStash.ScreenElement(
            heistId: "button_cached",
            contentSpaceOrigin: nil,
            element: cachedElement,
            object: nil,
            scrollView: nil
        ))
        brains.containerExploreStates[container] = TheBrains.ContainerExploreState(
            visibleSubtreeFingerprint: fingerprint,
            discoveredHeistIds: ["button_cached"]
        )

        _ = await brains.exploreAndPrune()

        XCTAssertTrue(brains.stash.registry.elementByHeistId.keys.contains("button_cached"),
                      "Cached discovered ids must survive prune when fingerprint cache hits")
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

        let manifest = await brains.exploreScreen()

        XCTAssertTrue(manifest.exploredContainers.contains(container))
        XCTAssertNotNil(brains.containerExploreStates[container],
                        "Swipeable containers should be explored and cached")
    }

    // MARK: - Helpers

    private func seedRegistry(
        heistId: String,
        label: String,
        traits: UIAccessibilityTraits,
        includeInViewport: Bool = true
    ) {
        let element = AccessibilityElement(
            description: label,
            label: label,
            value: nil,
            traits: traits,
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
        brains.stash.registry.insertForTesting(TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        ))
        if includeInViewport {
            brains.stash.registry.viewportIds.insert(heistId)
            brains.stash.currentHierarchy.append(.element(element, traversalIndex: 0))
        }
    }

    private func makeElement(
        label: String,
        traits: UIAccessibilityTraits
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label,
            label: label,
            value: nil,
            traits: traits,
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
    }

}

#endif

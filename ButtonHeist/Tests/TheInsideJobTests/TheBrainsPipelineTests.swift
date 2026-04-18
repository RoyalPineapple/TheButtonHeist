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
        XCTAssertEqual(result.value, "")
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
        XCTAssertEqual(brains.stash.registry.elements.count, 2)

        _ = await brains.exploreAndPrune()

        XCTAssertTrue(brains.stash.registry.elements.keys.contains("button_seen"),
                      "Viewport elements must survive the prune")
        XCTAssertFalse(brains.stash.registry.elements.keys.contains("button_orphan"),
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
        brains.stash.registry.elements["button_cached"] = TheStash.ScreenElement(
            heistId: "button_cached",
            contentSpaceOrigin: nil,
            element: cachedElement,
            object: nil,
            scrollView: nil
        )
        brains.containerExploreStates[container] = TheBrains.ContainerExploreState(
            visibleSubtreeFingerprint: fingerprint,
            discoveredHeistIds: ["button_cached"]
        )

        _ = await brains.exploreAndPrune()

        XCTAssertTrue(brains.stash.registry.elements.keys.contains("button_cached"),
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

    // MARK: - Temporary Swipe Diagnostics (Watch Mode)

    func testTempWatchSwipeParseDuringAnimation() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for swipe timing diagnostics")
        }
        guard let scenario = swipeScenario() else {
            throw XCTSkip("No overflowing scrollable container available")
        }

        // Keep this short enough to run quickly, but slow enough to watch in Simulator.
        let durations: [TimeInterval] = [0.12, 0.08, 0.06]
        let iterations = 4

        for duration in durations {
            var detectedDuringCount = 0
            var detectedAfterCount = 0
            var parseMs: [Double] = []

            print(String(format: "[Diagnostics][Temp][Watch] starting duration=%.2fs", duration))

            for i in 0..<iterations {
                let direction = i.isMultiple(of: 2) ? scenario.primaryDirection : scenario.reverseDirection
                guard brains.refresh() != nil else { continue }
                let before = brains.stash.registry.viewportIds
                let t0 = CACurrentMediaTime()

                let swipeTask = Task {
                    await self.brains.safecracker.scrollBySwipe(
                        frame: scenario.frame,
                        direction: direction,
                        duration: duration
                    )
                }

                var sawDuring = false
                while CACurrentMediaTime() - t0 < duration {
                    let parseStart = CACurrentMediaTime()
                    brains.refresh()
                    let parseEnd = CACurrentMediaTime()
                    parseMs.append((parseEnd - parseStart) * 1000)

                    if brains.stash.registry.viewportIds != before {
                        detectedDuringCount += 1
                        sawDuring = true
                        break
                    }
                    await brains.tripwire.yieldFrames(1)
                }

                _ = await swipeTask.value
                brains.refresh()
                if !sawDuring, brains.stash.registry.viewportIds != before {
                    detectedAfterCount += 1
                }

                // Give humans time to visually follow each swipe in Simulator.
                try? await Task.sleep(for: .milliseconds(450))
            }

            let meanParse = parseMs.reduce(0, +) / Double(max(parseMs.count, 1))
            print(String(
                format: "[Diagnostics][Temp][Watch] duration=%.2fs detected_during=%d/%d detected_only_after=%d/%d parse_mean=%.2fms",
                duration, detectedDuringCount, iterations, detectedAfterCount, iterations, meanParse
            ))
        }
    }

    // MARK: - Helpers

    private struct SwipeScenario {
        let frame: CGRect
        let primaryDirection: UIAccessibilityScrollDirection
        let reverseDirection: UIAccessibilityScrollDirection
    }

    private func swipeScenario() -> SwipeScenario? {
        guard let container = brains.stash.currentHierarchy.scrollableContainers.first(where: {
            guard case .scrollable(let contentSize) = $0.type else { return false }
            let hasHOverflow = contentSize.width > $0.frame.width + 1
            let hasVOverflow = contentSize.height > $0.frame.height + 1
            return hasHOverflow || hasVOverflow
        }),
        case .scrollable(let contentSize) = container.type else {
            return nil
        }

        let hasHOverflow = contentSize.width > container.frame.width + 1
        let hasVOverflow = contentSize.height > container.frame.height + 1

        let primaryDirection: UIAccessibilityScrollDirection
        let reverseDirection: UIAccessibilityScrollDirection
        if hasVOverflow {
            primaryDirection = .down
            reverseDirection = .up
        } else if hasHOverflow {
            primaryDirection = .right
            reverseDirection = .left
        } else {
            return nil
        }

        let frame: CGRect
        if let view = brains.stash.scrollableContainerViews[container], view.window != nil {
            frame = view.convert(view.bounds, to: nil)
        } else {
            frame = container.frame
        }

        guard !frame.isEmpty else { return nil }
        return SwipeScenario(frame: frame, primaryDirection: primaryDirection, reverseDirection: reverseDirection)
    }

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
        brains.stash.registry.elements[heistId] = TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        )
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

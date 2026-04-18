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
        try await navigateToLongListView()
        guard let scenario = swipeScenario() else {
            throw XCTSkip("No overflowing scrollable container available")
        }

        let iterations = 70
        var swipeMs: [Double] = []
        var movedCount = 0
        var blockedCount = 0
        var downMoves = 0
        var upMoves = 0
        var bottomHits = 0
        var topHits = 0
        var reverseChecks = 0
        var reverseRecovered = 0
        var pendingReverseCheck = false
        var direction = await calibratedStartDirection(for: scenario)

        print(String(
            format: "[Diagnostics][Temp][Watch] starting iterations=%d start_direction=%@",
            iterations,
            directionName(direction)
        ))

        for _ in 0..<iterations {
            guard brains.refresh() != nil else { continue }
            let swipeDirection = direction
            let beforeOffset = scenario.observedScrollView?.contentOffset
            let start = CACurrentMediaTime()
            let (moved, before) = await brains.scrollOnePageAndSettle(
                scenario.target,
                direction: swipeDirection,
                animated: false
            )
            let end = CACurrentMediaTime()
            swipeMs.append((end - start) * 1000)

            let movedThisSwipe: Bool
            if let scrollView = scenario.observedScrollView, let beforeOffset {
                let afterOffset = scrollView.contentOffset
                movedThisSwipe = abs(afterOffset.x - beforeOffset.x) > 0.5
                    || abs(afterOffset.y - beforeOffset.y) > 0.5
            } else {
                movedThisSwipe = moved && (brains.stash.registry.viewportIds != before || moved)
            }
            if movedThisSwipe {
                movedCount += 1
                if swipeDirection == .down {
                    downMoves += 1
                } else if swipeDirection == .up {
                    upMoves += 1
                }
            } else {
                blockedCount += 1
            }

            if let scrollView = scenario.observedScrollView {
                let insets = scrollView.adjustedContentInset
                let minY = -insets.top
                let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
                let y = scrollView.contentOffset.y
                if swipeDirection == .down, y >= maxY - 1 {
                    direction = .up
                    bottomHits += 1
                } else if swipeDirection == .up, y <= minY + 1 {
                    direction = .down
                    topHits += 1
                }
            } else {
                if pendingReverseCheck {
                    reverseChecks += 1
                    if movedThisSwipe { reverseRecovered += 1 }
                    pendingReverseCheck = false
                }
                if !movedThisSwipe {
                    pendingReverseCheck = true
                    direction = oppositeDirection(of: direction)
                }
            }

            await brains.tripwire.yieldFrames(movedThisSwipe ? 1 : 3)
        }

        let meanSwipeMs = swipeMs.reduce(0, +) / Double(max(swipeMs.count, 1))
        let diagnosticsFormat =
            "[Diagnostics][Temp][Watch] moved=%d blocked=%d down_moves=%d up_moves=%d "
            + "bottom_hits=%d top_hits=%d reverse_recovered=%d/%d swipe_call_mean=%.2fms"
        print(String(
            format: diagnosticsFormat,
            movedCount,
            blockedCount,
            downMoves,
            upMoves,
            bottomHits,
            topHits,
            reverseRecovered,
            reverseChecks,
            meanSwipeMs
        ))
    }

    // MARK: - Helpers

    private func navigateToLongListView() async throws {
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for swipe timing diagnostics")
        }

        let longListHeader = ElementTarget.matcher(ElementMatcher(label: "Long List", traits: [.header]))
        if brains.stash.resolveFirstMatch(longListHeader) != nil {
            return
        }

        let longListLink = ElementTarget.matcher(ElementMatcher(label: "Long List", traits: [.button]))
        if brains.stash.resolveFirstMatch(longListLink) == nil {
            for _ in 0..<16 {
                guard let container = brains.stash.currentHierarchy.scrollableContainers.first,
                      case .scrollable(let contentSize) = container.type else { break }
                let target = brains.scrollableTarget(for: container, contentSize: contentSize)
                _ = await brains.scrollOnePageAndSettle(target, direction: .down, animated: false)
                if brains.stash.resolveFirstMatch(longListLink) != nil {
                    break
                }
            }
        }

        let activateResult = await brains.executeActivate(longListLink)
        if !activateResult.success {
            let tapResult = await brains.executeTap(TouchTapTarget(elementTarget: longListLink))
            guard tapResult.success else {
                let reason = tapResult.message ?? activateResult.message ?? "activate/tap failed"
                throw XCTSkip("Could not open Long List demo (\(reason))")
            }
        }

        _ = await brains.tripwire.waitForAllClear(timeout: 1.2)
        guard brains.refresh() != nil else {
            throw XCTSkip("Hierarchy unavailable after opening Long List")
        }
        guard brains.stash.resolveFirstMatch(longListHeader) != nil else {
            throw XCTSkip("Long List view did not become visible")
        }
    }

    private struct SwipeScenario {
        let target: TheBrains.ScrollableTarget
        let observedScrollView: UIScrollView?
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

        let baseFrame: CGRect
        if let view = brains.stash.scrollableContainerViews[container], view.window != nil {
            baseFrame = view.convert(view.bounds, to: nil)
        } else {
            baseFrame = container.frame
        }
        let frame = swipeOnlyFrame(from: baseFrame)
        guard !frame.isEmpty else { return nil }
        let target = TheBrains.ScrollableTarget.swipeable(frame: frame, contentSize: contentSize)
        let observedScrollView = brains.stash.scrollableContainerViews[container] as? UIScrollView
        return SwipeScenario(
            target: target,
            observedScrollView: observedScrollView,
            primaryDirection: primaryDirection,
            reverseDirection: reverseDirection
        )
    }

    private func calibratedStartDirection(
        for scenario: SwipeScenario
    ) async -> UIAccessibilityScrollDirection {
        if await swipeChangesViewport(target: scenario.target, direction: scenario.primaryDirection) {
            return scenario.primaryDirection
        }
        if await swipeChangesViewport(target: scenario.target, direction: scenario.reverseDirection) {
            return scenario.reverseDirection
        }
        return scenario.primaryDirection
    }

    private func swipeChangesViewport(
        target: TheBrains.ScrollableTarget,
        direction: UIAccessibilityScrollDirection
    ) async -> Bool {
        guard brains.refresh() != nil else { return false }
        let before = brains.stash.registry.viewportIds
        let (moved, _) = await brains.scrollOnePageAndSettle(target, direction: direction, animated: false)
        return moved && brains.stash.registry.viewportIds != before
    }

    private func oppositeDirection(of direction: UIAccessibilityScrollDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .up
        case .up: return .down
        case .left: return .right
        case .right: return .left
        case .next: return .previous
        case .previous: return .next
        @unknown default: return direction
        }
    }

    private func directionName(_ direction: UIAccessibilityScrollDirection) -> String {
        switch direction {
        case .down: return "down"
        case .up: return "up"
        case .left: return "left"
        case .right: return "right"
        case .next: return "next"
        case .previous: return "previous"
        @unknown default: return "unknown"
        }
    }

    private func swipeOnlyFrame(from frame: CGRect) -> CGRect {
        let safeArea = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        let clamped = frame.inset(by: UIEdgeInsets(
            top: safeArea.top + 56,
            left: 16,
            bottom: safeArea.bottom + 20,
            right: 16
        ))
        if !clamped.isEmpty { return clamped }
        return frame.insetBy(dx: min(20, frame.width * 0.1), dy: min(60, frame.height * 0.2))
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

#if canImport(UIKit)
import XCTest
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBrainsScrollTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    // MARK: - Programmatic Scroll Safety

    func testExploreScreenSkipsUIPageViewControllerQueuingScrollView() async throws {
        let windowScene = try requireForegroundWindowScene()
        let pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        let pages = [
            PageContentViewController(label: "Page One Visible Label"),
            PageContentViewController(label: "Page Two Hidden Label"),
            PageContentViewController(label: "Page Three Hidden Label"),
        ]
        let dataSource = PageDataSource(pages: pages)
        pageViewController.dataSource = dataSource
        pageViewController.setViewControllers([pages[0]], direction: .forward, animated: false)
        pageViewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 20
        window.rootViewController = pageViewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false

        defer {
            window.isHidden = true
            pageViewController.view.accessibilityViewIsModal = false
        }

        window.layoutIfNeeded()
        await brains.tripwire.yieldFrames(3)

        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for UIPageViewController regression test")
        }

        let unsafeContainers = brains.stash.scrollableContainerViews.compactMap { entry -> AccessibilityContainer? in
            let (container, view) = entry
            guard let scrollView = view as? UIScrollView,
                  scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return nil
            }
            return container
        }
        guard !unsafeContainers.isEmpty else {
            throw XCTSkip("UIPageViewController did not expose _UIQueuingScrollView on this OS")
        }

        var union = brains.stash.currentScreen
        let manifest = await brains.navigation.exploreScreen(union: &union)

        for container in unsafeContainers {
            XCTAssertTrue(
                manifest.exploredContainers.contains(container),
                "Unsafe page-view scroll containers should be marked explored without programmatic scrolling"
            )
        }
        XCTAssertTrue(
            union.elements.values.contains {
                $0.element.label == "Page One Visible Label"
            },
            "Visible page content should remain discoverable without scrolling the queuing scroll view"
        )
    }

    // MARK: - scrollTargetOffset (Pure Math)

    func testScrollTargetOffsetCentersOnOrigin() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = .zero

        let origin = CGPoint(x: 100, y: 2500)
        let offset = TheStash.scrollTargetOffset(for: origin, in: scrollView)

        XCTAssertEqual(offset.x, max(origin.x - 375.0 / 2, 0), accuracy: 0.01,
                       "X offset should center on origin horizontally")
        XCTAssertEqual(offset.y, origin.y - 667.0 / 2, accuracy: 0.01,
                       "Y offset should center on origin vertically")
    }

    func testScrollTargetOffsetClampsToTop() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let origin = CGPoint(x: 100, y: 100)
        let offset = TheStash.scrollTargetOffset(for: origin, in: scrollView)

        XCTAssertGreaterThanOrEqual(offset.y, 0,
                                    "Offset should not go above content start")
    }

    func testScrollTargetOffsetClampsToBottom() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)

        let origin = CGPoint(x: 100, y: 4900)
        let offset = TheStash.scrollTargetOffset(for: origin, in: scrollView)

        let maxY = scrollView.contentSize.height - scrollView.bounds.height
        XCTAssertLessThanOrEqual(offset.y, maxY + 0.01,
                                 "Offset should not exceed maximum scrollable Y")
    }

    func testScrollTargetOffsetRespectsContentInsets() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        scrollView.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)

        let origin = CGPoint(x: 100, y: 10)
        let offset = TheStash.scrollTargetOffset(for: origin, in: scrollView)

        let minY = -scrollView.adjustedContentInset.top
        XCTAssertGreaterThanOrEqual(offset.y, minY,
                                    "Offset should respect top content inset")
    }

    func testScrollTargetOffsetHorizontalClamping() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 2000, height: 667)

        let originNearStart = CGPoint(x: 50, y: 300)
        let offsetStart = TheStash.scrollTargetOffset(for: originNearStart, in: scrollView)
        XCTAssertGreaterThanOrEqual(offsetStart.x, 0, "Should clamp to left edge")

        let originNearEnd = CGPoint(x: 1950, y: 300)
        let offsetEnd = TheStash.scrollTargetOffset(for: originNearEnd, in: scrollView)
        let maxX = scrollView.contentSize.width - scrollView.bounds.width
        XCTAssertLessThanOrEqual(offsetEnd.x, maxX + 0.01, "Should clamp to right edge")
    }

    // MARK: - requiredAxis Mapping

    func testRequiredAxisForScrollDirection() {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.up), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.down), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.right), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.next), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollDirection.previous), .vertical)
    }

    func testRequiredAxisForScrollEdge() {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.top), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.bottom), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollEdge.right), .horizontal)
    }

    func testRequiredAxisForScrollSearchDirection() {
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollSearchDirection.up), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollSearchDirection.down), .vertical)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollSearchDirection.left), .horizontal)
        XCTAssertEqual(Navigation.requiredAxis(for: ScrollSearchDirection.right), .horizontal)
    }

    // MARK: - uiScrollDirection Mapping

    func testUIScrollDirectionFromScrollSearchDirection() {
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollSearchDirection.down), .down)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollSearchDirection.up), .up)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollSearchDirection.left), .left)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollSearchDirection.right), .right)
    }

    func testUIScrollDirectionFromScrollDirection() {
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.up), .up)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.down), .down)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.left), .left)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.right), .right)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.next), .next)
        XCTAssertEqual(Navigation.uiScrollDirection(for: ScrollDirection.previous), .previous)
    }

    // MARK: - adaptDirection Cross-Axis Fallback

    func testAdaptDirectionForwardVerticalToHorizontal() {
        let horizontalOnly = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(Navigation.adaptDirection(.down, for: horizontalOnly), .right,
                       "Forward vertical request on horizontal-only → .right")
    }

    func testAdaptDirectionBackwardVerticalToHorizontal() {
        let horizontalOnly = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(Navigation.adaptDirection(.up, for: horizontalOnly), .left,
                       "Backward vertical request on horizontal-only → .left")
    }

    func testAdaptDirectionForwardHorizontalToVertical() {
        let verticalOnly = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.right, for: verticalOnly), .down,
                       "Forward horizontal request on vertical-only → .down")
    }

    func testAdaptDirectionBackwardHorizontalToVertical() {
        let verticalOnly = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.left, for: verticalOnly), .up,
                       "Backward horizontal request on vertical-only → .up")
    }

    func testAdaptDirectionMatchingAxisPassesThrough() {
        let verticalOnly = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.down, for: verticalOnly), .down)
        XCTAssertEqual(Navigation.adaptDirection(.up, for: verticalOnly), .up)
    }

    func testAdaptDirectionBothAxesPassesThrough() {
        let biaxial = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.down, for: biaxial), .down)
        XCTAssertEqual(Navigation.adaptDirection(.right, for: biaxial), .right)
        XCTAssertEqual(Navigation.adaptDirection(.up, for: biaxial), .up)
        XCTAssertEqual(Navigation.adaptDirection(.left, for: biaxial), .left)
    }

    // MARK: - Scroll Search Target Selection

    func testFindScrollTargetPrefersRequestedAxisBeforeCrossAxisFallback() {
        let vertical = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1200, height: 200),
            frame: CGRect(x: 0, y: 420, width: 320, height: 200)
        )
        installScrollableContainers([vertical, horizontal])

        let result = brains.navigation.findScrollTarget(preferredAxis: .horizontal)

        XCTAssertEqual(result?.container, horizontal)
    }

    func testFindScrollTargetFallsBackWhenRequestedAxisIsUnavailable() {
        let vertical = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        installScrollableContainers([vertical])

        let result = brains.navigation.findScrollTarget(preferredAxis: .horizontal)

        XCTAssertEqual(result?.container, vertical)
    }

    func testScrollSearchCandidatesKeepCrossAxisFallbacksAfterPreferredAxis() {
        let vertical = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1200, height: 200),
            frame: CGRect(x: 0, y: 420, width: 320, height: 200)
        )
        installScrollableContainers([vertical, horizontal])

        let candidates = brains.navigation.scrollSearchCandidates(preferredAxis: .horizontal)

        XCTAssertEqual(candidates.map(\.container), [horizontal, vertical])
    }

    func testScrollSearchCandidatesPreserveTreeOrderWithinPreferredAndFallbackGroups() {
        let horizontal = makeScrollableContainer(
            contentSize: CGSize(width: 1200, height: 200),
            frame: CGRect(x: 0, y: 0, width: 320, height: 200)
        )
        let verticalOne = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1600),
            frame: CGRect(x: 0, y: 220, width: 320, height: 400)
        )
        let verticalTwo = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1800),
            frame: CGRect(x: 0, y: 640, width: 320, height: 400)
        )
        installScrollableContainers([horizontal, verticalOne, verticalTwo])

        let candidates = brains.navigation.scrollSearchCandidates(preferredAxis: .vertical)

        XCTAssertEqual(candidates.map(\.container), [verticalOne, verticalTwo, horizontal])
    }

    func testFindScrollTargetUsesKnownSiblingAfterFirstContainerExhausted() {
        let first = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let sibling = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1600),
            frame: CGRect(x: 0, y: 420, width: 320, height: 400)
        )
        installScrollableContainers([first, sibling])

        let result = brains.navigation.findScrollTarget(
            preferredAxis: .vertical,
            excluding: [first]
        )

        XCTAssertEqual(result?.container, sibling)
    }

    // MARK: - Scroll Search Progress

    func testScrollSearchProgressReportsCapAsNonExhaustive() {
        let container = makeScrollableContainer()
        var progress = Navigation.ScrollSearchProgress(
            initialVisibleHeistIds: ["initial"],
            maxScrolls: 2
        )

        progress.markScrolledPage(in: container, visibleHeistIds: ["page_1"])
        progress.markScrolledPage(in: container, visibleHeistIds: ["initial", "page_2"])

        XCTAssertEqual(progress.scrollCount, 2)
        XCTAssertEqual(progress.pagesSearched, 3)
        XCTAssertEqual(progress.containersSearched, 1)
        XCTAssertEqual(progress.uniqueElementsSeen, 3)
        XCTAssertTrue(progress.didHitScrollCap)
        XCTAssertFalse(progress.exhaustive)
    }

    func testScrollSearchProgressReportsExhaustiveWhenEdgesReachedBeforeCap() {
        let container = makeScrollableContainer()
        var progress = Navigation.ScrollSearchProgress(
            initialVisibleHeistIds: ["initial"],
            maxScrolls: 2
        )

        progress.markContainerExhausted(container)

        XCTAssertEqual(progress.scrollCount, 0)
        XCTAssertEqual(progress.pagesSearched, 1)
        XCTAssertEqual(progress.containersSearched, 1)
        XCTAssertEqual(progress.exhaustedContainers, Set([container]))
        XCTAssertFalse(progress.didHitScrollCap)
        XCTAssertTrue(progress.exhaustive)
    }

    func testScrollSearchProgressIsNotExhaustiveWhileKnownContainerRemains() {
        let first = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let sibling = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 1600),
            frame: CGRect(x: 0, y: 420, width: 320, height: 400)
        )
        var progress = Navigation.ScrollSearchProgress(
            initialVisibleHeistIds: ["initial"],
            knownContainers: [first, sibling],
            maxScrolls: 5
        )

        progress.markContainerExhausted(first)

        XCTAssertEqual(progress.containersSearched, 1)
        XCTAssertEqual(progress.exhaustedContainers, Set([first]))
        XCTAssertEqual(progress.knownContainers, Set([first, sibling]))
        XCTAssertFalse(progress.didHitScrollCap)
        XCTAssertFalse(progress.exhaustive)
    }

    func testScrollSearchProgressWithoutSearchedContainersIsNotExhaustive() {
        let progress = Navigation.ScrollSearchProgress(
            initialVisibleHeistIds: ["initial"],
            maxScrolls: 2
        )

        XCTAssertEqual(progress.containersSearched, 0)
        XCTAssertFalse(progress.didHitScrollCap)
        XCTAssertFalse(progress.exhaustive)
    }

    // MARK: - ScrollableTarget Properties

    func testScrollableTargetFrameForUIScrollView() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let scrollView = UIScrollView(frame: frame)
        let target = Navigation.ScrollableTarget.uiScrollView(scrollView)

        XCTAssertEqual(target.frame, frame)
    }

    func testScrollableTargetFrameForSwipeable() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let contentSize = CGSize(width: 600, height: 800)
        let target = Navigation.ScrollableTarget.swipeable(frame: frame, contentSize: contentSize)

        XCTAssertEqual(target.frame, frame)
        XCTAssertEqual(target.contentSize, contentSize)
    }

    func testScrollableTargetContentSizeForUIScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        let target = Navigation.ScrollableTarget.uiScrollView(scrollView)

        XCTAssertEqual(target.contentSize, CGSize(width: 375, height: 5000))
    }

    // MARK: - Scroll Axis Detection (Swipeable variant)

    func testScrollableAxisSwipeableHorizontalOnly() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        let axis = Navigation.scrollableAxis(of: target)
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertFalse(axis.contains(.vertical))
    }

    func testScrollableAxisSwipeableVerticalOnly() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        let axis = Navigation.scrollableAxis(of: target)
        XCTAssertFalse(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisSwipeableNoOverflow() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 200)
        )
        let axis = Navigation.scrollableAxis(of: target)
        XCTAssertTrue(axis.isEmpty)
    }

    // MARK: - Off-Viewport Entry

    /// Install a Screen whose `elements` includes an entry that's not in the
    /// live hierarchy — simulating an element retained from a previous
    /// exploration commit that has since scrolled off.
    private func installScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, String)],
        offViewport: [(AccessibilityElement, String, CGPoint?)]
    ) {
        brains.stash.currentScreen = .makeForTests(
            elements: liveHierarchy.map { ($0.0, $0.1) },
            offViewport: offViewport.map {
                Screen.OffViewportEntry($0.0, heistId: $0.1, contentSpaceOrigin: $0.2)
            }
        )
    }

    func testOffViewportEntryByHeistIdReturnsWhenOffScreen() {
        let other = makeElement(label: "Other")
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(other, "other_element")],
            offViewport: [(element, "button_item", CGPoint(x: 0, y: 2000))]
        )

        let entry = brains.navigation.offViewportRegistryEntry(for: .heistId("button_item"))
        XCTAssertNotNil(entry, "Should return entry when heistId is not in live viewport")
        XCTAssertEqual(entry?.heistId, "button_item")
    }

    func testOffViewportEntryByHeistIdReturnsNilWhenOnScreen() {
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(element, "button_item")],
            offViewport: []
        )

        let entry = brains.navigation.offViewportRegistryEntry(for: .heistId("button_item"))
        XCTAssertNil(entry, "Should return nil when heistId is in live viewport")
    }

    // MARK: - resolveScrollTarget

    func testResolveScrollTargetReturnsNilWhenNoScrollView() {
        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: makeElement(),
            object: UILabel(),
            scrollView: nil
        )

        let target = brains.navigation.resolveScrollTarget(screenElement: screenElement)
        XCTAssertNil(target)
    }

    func testResolveScrollTargetWithAxisMismatchReturnsScrollViewWhenNoFallback() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: makeElement(),
            object: nil,
            scrollView: scrollView
        )

        let target = brains.navigation.resolveScrollTarget(
            screenElement: screenElement, axis: .vertical
        )
        // When axis doesn't match and no fallback container exists in the hierarchy,
        // the code still returns the element's own scroll view.
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === scrollView,
                          "Should return the element's scroll view when no fallback exists")
        } else {
            XCTFail("Expected .uiScrollView, got \(String(describing: target))")
        }
    }

    // MARK: - SettleSwipeLoopState (Pure Decision Logic)

    func testSettleLoopSameDirectionExitsAfterOneStableFrame() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .sameDirection,
            previousViewport: ["a"],
            previousAnchor: 100
        )
        let step1 = state.advance(
            viewportIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step1, .continue, "Viewport change resets stable counter")
        XCTAssertTrue(state.moved, "Anchor differs, motion detected")

        let step2 = state.advance(
            viewportIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step2, .done, "Same-direction profile exits once stable frame count hits 1")
        XCTAssertTrue(state.moved)
    }

    func testSettleLoopDirectionChangeHonorsMinFrames() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousViewport: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<5 {
            let step = state.advance(
                viewportIds: ["a"],
                anchorSignature: 100,
                newHeistIds: []
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) must not exit before minFrames=6")
        }
        let finalStep = state.advance(
            viewportIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertEqual(finalStep, .done, "Direction-change profile exits at frame 6")
        XCTAssertEqual(state.frame, 6)
    }

    func testSettleLoopExitsAtMaxFramesWhenConditionsNeverSettle() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousViewport: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<23 {
            let step = state.advance(
                viewportIds: ["id-\(frameIndex)"],
                anchorSignature: 200 + frameIndex,
                newHeistIds: ["id-\(frameIndex)"]
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) churns, should continue")
        }
        let finalStep = state.advance(
            viewportIds: ["id-final"],
            anchorSignature: 999,
            newHeistIds: ["id-final"]
        )
        XCTAssertEqual(finalStep, .done, "Must exit at maxFrames=24 even if never settles")
        XCTAssertEqual(state.frame, 24)
    }

    func testSettleLoopMovedLatchesAndNeverClears() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousViewport: ["a"],
            previousAnchor: 100
        )
        XCTAssertFalse(state.moved)

        _ = state.advance(
            viewportIds: ["a"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Differing anchor flags motion")

        _ = state.advance(
            viewportIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "moved only latches true, never clears back to false")
    }

    func testSettleLoopFallsBackToViewportDiffWhenAnchorsUnavailable() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousViewport: ["a"],
            previousAnchor: nil
        )
        _ = state.advance(
            viewportIds: ["b"],
            anchorSignature: nil,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Without anchors, viewport set difference signals motion")
    }

    func testSettleLoopEdgeBounceDoesNotReportMotion() {
        // Regression guard for the claim that viewportAnchorSignature
        // filters out edge-bounce false positives. When content-space
        // anchors are unchanged across frames, viewport id shuffles
        // (element reorder, reparse flicker) must NOT count as motion.
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousViewport: ["a", "b"],
            previousAnchor: 500
        )
        _ = state.advance(
            viewportIds: ["a", "c"],
            anchorSignature: 500,
            newHeistIds: ["c"]
        )
        XCTAssertFalse(
            state.moved,
            "Matching anchor must suppress viewport-set differences as motion signal"
        )
    }

    // MARK: - safeSwipeFrame

    func testSafeSwipeFrameFullyInSafeBoundsIsUnchanged() {
        // A frame sitting comfortably inside the safe area passes through
        // intersected with itself, which is the frame.
        let screen = UIScreen.main.bounds
        let inner = screen.insetBy(dx: 80, dy: 120)
        XCTAssertEqual(brains.navigation.safeSwipeFrame(from: inner), inner)
    }

    func testSafeSwipeFrameZeroWidthReturnsOriginal() {
        // Degenerate input has no intersection with anything, so the function
        // returns the original frame.
        let input = CGRect(x: 0, y: 0, width: 0, height: 100)
        XCTAssertEqual(brains.navigation.safeSwipeFrame(from: input), input)
    }

    func testSafeSwipeFrameOversizedFrameClampsWithinScreen() {
        // A frame larger than any iPhone screen must clamp to the safe
        // region and stay within the current screen bounds.
        let huge = CGRect(x: -1000, y: -1000, width: 10000, height: 10000)
        let result = brains.navigation.safeSwipeFrame(from: huge)
        let screenBounds = UIScreen.main.bounds
        XCTAssertTrue(
            screenBounds.contains(result),
            "Result \(result) must fit within the screen \(screenBounds)"
        )
    }

    func testSafeSwipeFrameClampsAboveTabBarContainer() {
        // A .tabBar container in the accessibility hierarchy defines the
        // bottom clear line. A swipe rectangle that overlaps the tab bar
        // must be clipped to end at its top edge.
        let tabBarFrame = CGRect(x: 0, y: 700, width: 400, height: 80)
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: tabBarFrame)
        brains.stash.currentScreen = Screen(
            elements: [:],
            hierarchy: [.container(tabBarContainer, children: [])],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
        let result = brains.navigation.safeSwipeFrame(from: CGRect(x: 100, y: 400, width: 200, height: 500))
        XCTAssertEqual(
            result.maxY, tabBarFrame.minY,
            "Swipe area must end at the tab bar's top edge"
        )
    }

    // MARK: - Clear Cache

    func testClearCacheClearsLastSwipeDirectionCache() {
        brains.navigation.lastSwipeDirectionByTarget["key"] = .down
        XCTAssertFalse(brains.navigation.lastSwipeDirectionByTarget.isEmpty)
        brains.clearCache()
        XCTAssertTrue(
            brains.navigation.lastSwipeDirectionByTarget.isEmpty,
            "clearCache must drop the swipe direction cache so a new session starts fresh"
        )
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none,
        shape: AccessibilityElement.Shape = .frame(.zero)
    ) -> AccessibilityElement {
        .make(label: label, traits: traits, shape: shape, respondsToUserInteraction: false)
    }

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 320, height: 2000),
        frame: CGRect = CGRect(x: 0, y: 0, width: 320, height: 400)
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: contentSize),
            frame: frame
        )
    }

    private func installScrollableContainers(_ containers: [AccessibilityContainer]) {
        brains.stash.currentScreen = Screen(
            elements: [:],
            hierarchy: containers.map { .container($0, children: []) },
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }

    private final class PageDataSource: NSObject, UIPageViewControllerDataSource {
        let pages: [UIViewController]

        init(pages: [UIViewController]) {
            self.pages = pages
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController),
                  index > 0 else {
                return nil
            }
            return pages[index - 1]
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let index = pages.firstIndex(of: viewController),
                  index < pages.count - 1 else {
                return nil
            }
            return pages[index + 1]
        }
    }

    private final class PageContentViewController: UIViewController {
        private let pageLabel: String

        init(label: String) {
            self.pageLabel = label
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .white

            let label = UILabel()
            label.text = pageLabel
            label.accessibilityLabel = pageLabel
            label.isAccessibilityElement = true
            label.frame = CGRect(x: 40, y: 120, width: 280, height: 44)
            view.addSubview(label)
        }
    }
}

#endif

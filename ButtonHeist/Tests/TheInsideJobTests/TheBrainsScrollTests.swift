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

        let unsafeTargets = brains.stash.scrollableContainerViews.compactMap { entry -> (
            AccessibilityContainer,
            UIScrollView
        )? in
            let (container, view) = entry
            guard let scrollView = view as? UIScrollView,
                  scrollView.bhIsUnsafeForProgrammaticScrolling else {
                return nil
            }
            return (container, scrollView)
        }
        guard !unsafeTargets.isEmpty else {
            throw XCTSkip("UIPageViewController did not expose _UIQueuingScrollView on this OS")
        }

        var union = brains.stash.currentScreen
        let manifest = await brains.navigation.exploreScreen(union: &union)

        for (container, _) in unsafeTargets {
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

        let unsafeScreenElement = TheStash.ScreenElement(
            heistId: "unsafe_page_item",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Unsafe Page Item"),
            object: nil,
            scrollView: unsafeTargets[0].1
        )
        guard case .failed(let diagnostic) = brains.navigation.resolveScrollTargetResult(
            screenElement: unsafeScreenElement
        ) else {
            return XCTFail("Expected unsafe programmatic scroll diagnostic")
        }
        XCTAssertEqual(
            diagnostic.message(for: unsafeScreenElement),
            "scroll target failed: observed \"Unsafe Page Item\" (heistId: unsafe_page_item) "
                + "inside a scroll view that is unsafe for programmatic scrolling; try element_search "
                + "to use semantic search"
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

    // MARK: - Known Offscreen Entry

    /// Install a Screen whose `elements` includes an entry that's not in the
    /// live hierarchy — simulating an element retained from a previous
    /// exploration commit that has since scrolled off.
    private func makeScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, String)],
        offViewport: [(AccessibilityElement, String, CGPoint?)]
    ) -> Screen {
        .makeForTests(
            elements: liveHierarchy.map { ($0.0, $0.1) },
            offViewport: offViewport.map {
                Screen.OffViewportEntry($0.0, heistId: $0.1, contentSpaceOrigin: $0.2)
            }
        )
    }

    private func installScreenWithOffViewportEntry(
        liveHierarchy: [(AccessibilityElement, String)],
        offViewport: [(AccessibilityElement, String, CGPoint?)]
    ) {
        brains.stash.currentScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: liveHierarchy,
            offViewport: offViewport
        )
    }

    private func installScreenWithKnownOffscreen(
        visible: (AccessibilityElement, String),
        offscreen: (AccessibilityElement, String, CGPoint, UIScrollView)
    ) {
        let visibleEntry = Screen.ScreenElement(
            heistId: visible.1,
            contentSpaceOrigin: nil,
            element: visible.0,
            object: nil,
            scrollView: nil
        )
        let offscreenEntry = Screen.ScreenElement(
            heistId: offscreen.1,
            contentSpaceOrigin: offscreen.2,
            element: offscreen.0,
            object: nil,
            scrollView: offscreen.3
        )
        brains.stash.currentScreen = Screen(
            elements: [
                visibleEntry.heistId: visibleEntry,
                offscreenEntry.heistId: offscreenEntry,
            ],
            hierarchy: [.element(visible.0, traversalIndex: 0)],
            containerStableIds: [:],
            heistIdByElement: [visible.0: visible.1],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
    }

    func testKnownOffscreenEntryByHeistIdReturnsWhenOffScreen() {
        let other = makeElement(label: "Other")
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(other, "other_element")],
            offViewport: [(element, "button_item", CGPoint(x: 0, y: 2000))]
        )

        let entry = brains.navigation.knownOffscreenEntry(for: .heistId("button_item"))
        XCTAssertNotNil(entry, "Should return entry when heistId is not in live viewport")
        XCTAssertEqual(entry?.heistId, "button_item")
    }

    func testKnownOffscreenEntryByHeistIdUsesRecordedScreenAfterVisibleRefresh() {
        let visible = makeElement(label: "Visible")
        let element = makeElement(label: "Item")
        let recordedScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [(element, "button_item", CGPoint(x: 0, y: 2000))]
        )
        brains.stash.currentScreen = .makeForTests(
            elements: [(visible, "visible_element")]
        )

        let entry = brains.navigation.knownOffscreenEntry(
            for: .heistId("button_item"),
            in: recordedScreen
        )

        XCTAssertEqual(entry?.heistId, "button_item")
    }

    func testKnownOffscreenEntryByHeistIdReturnsNilWhenOnScreen() {
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(element, "button_item")],
            offViewport: []
        )

        let entry = brains.navigation.knownOffscreenEntry(for: .heistId("button_item"))
        XCTAssertNil(entry, "Should return nil when heistId is in live viewport")
    }

    func testKnownOffscreenEntryByMatcherReturnsKnownEntryOutsideLiveHierarchy() {
        let other = makeElement(label: "Other")
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(other, "other_element")],
            offViewport: [(element, "button_item", CGPoint(x: 0, y: 2000))]
        )

        let entry = brains.navigation.knownOffscreenEntry(
            for: .matcher(ElementMatcher(label: "Item"))
        )
        XCTAssertNotNil(entry, "Should return known matcher hit when it is not in the live viewport")
        XCTAssertEqual(entry?.heistId, "button_item")
    }

    func testKnownOffscreenEntryByMatcherUsesRecordedScreenAfterVisibleRefresh() {
        let visible = makeElement(label: "Visible")
        let element = makeElement(label: "Item")
        let recordedScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: [(element, "button_item", CGPoint(x: 0, y: 2000))]
        )
        brains.stash.currentScreen = .makeForTests(
            elements: [(visible, "visible_element")]
        )

        let entry = brains.navigation.knownOffscreenEntry(
            for: .matcher(ElementMatcher(label: "Item")),
            in: recordedScreen
        )

        XCTAssertEqual(entry?.heistId, "button_item")
    }

    func testKnownOffscreenEntryByMatcherReturnsNilWhenMatchIsLive() {
        let element = makeElement(label: "Item")
        installScreenWithOffViewportEntry(
            liveHierarchy: [(element, "button_item")],
            offViewport: []
        )

        let entry = brains.navigation.knownOffscreenEntry(
            for: .matcher(ElementMatcher(label: "Item"))
        )
        XCTAssertNil(entry, "Should return nil when matcher hit is already in the live viewport")
    }

    func testKnownOffscreenEntryKeepsFreshVisibleGeometryAuthoritative() {
        let visibleElement = makeElement(label: "Item")
        let recordedElement = makeElement(label: "Item")
        let recordedScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [],
            offViewport: [(recordedElement, "button_item", CGPoint(x: 0, y: 2000))]
        )
        brains.stash.currentScreen = .makeForTests(
            elements: [(visibleElement, "button_item")]
        )

        let entry = brains.navigation.knownOffscreenEntry(
            for: .matcher(ElementMatcher(label: "Item")),
            in: recordedScreen
        )

        XCTAssertNil(
            entry,
            "Once the target is in the fresh visible parse, scroll_to_visible should use live geometry"
        )
    }

    func testScrollToVisibleUnknownTargetUsesRecordedScreenDiagnostics() {
        let visible = makeElement(label: "Visible")
        let recordedScreen = makeScreenWithOffViewportEntry(
            liveHierarchy: [(visible, "visible_element")],
            offViewport: []
        )
        brains.stash.currentScreen = .makeForTests(
            elements: [(visible, "visible_element")]
        )

        let message = brains.navigation.scrollToVisibleFailureMessage(
            for: .heistId("missing_button"),
            in: recordedScreen
        )

        XCTAssertTrue(message.contains("Element not found"))
        XCTAssertTrue(message.contains("missing_button"))
        XCTAssertTrue(message.contains("1 known element"))
        XCTAssertTrue(message.contains("get_interface"))
    }

    func testScrollReturnsReasonInsteadOfRevealingKnownOffscreenTarget() async {
        // Contract: Scroll either reveals the requested target or returns a reason it cannot.
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "offscreen_button", CGPoint(x: 0, y: 1_200), scrollView)
        )

        let result = await brains.navigation.executeScroll(
            ScrollTarget(elementTarget: .heistId("offscreen_button"), direction: .down)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scroll)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("known but not currently visible") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollToEdgeReturnsReasonInsteadOfRevealingKnownOffscreenTarget() async {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let visible = makeElement(label: "Visible")
        let offscreen = makeElement(label: "Offscreen")
        installScreenWithKnownOffscreen(
            visible: (visible, "visible_element"),
            offscreen: (offscreen, "offscreen_button", CGPoint(x: 0, y: 1_200), scrollView)
        )

        let result = await brains.navigation.executeScrollToEdge(
            ScrollToEdgeTarget(elementTarget: .heistId("offscreen_button"), edge: .bottom)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToEdge)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(
            result.message?.contains("known but not currently visible") == true,
            "Expected offscreen guidance, got \(String(describing: result.message))"
        )
        XCTAssertTrue(result.message?.contains("scroll_to_visible") == true)
    }

    func testScrollToVisibleVisibleAmbiguousMatcherFailsClosed() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Duplicate", frame: CGRect(x: 40, y: 120, width: 260, height: 44)))
        rootView.addSubview(makeButton(label: "Duplicate", frame: CGRect(x: 40, y: 180, width: 260, height: 44)))

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .matcher(ElementMatcher(label: "Duplicate")))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("2 elements match") ?? false,
            "Expected ambiguity diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePreservesVisibleMatcherOrdinalOutOfRange() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Save", frame: CGRect(x: 40, y: 120, width: 260, height: 44)))

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .matcher(ElementMatcher(label: "Save"), ordinal: 3))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("ordinal 3 requested") ?? false,
            "Expected ordinal diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePostJumpAmbiguousLiveTargetFailsClosed() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let firstTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 900, width: 240, height: 44))
        let secondTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 960, width: 240, height: 44))
        scrollView.revealedElements = [firstTarget, secondTarget]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(firstTarget)
        scrollView.addSubview(secondTarget)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        guard brains.refresh() != nil else {
            throw XCTSkip("No live hierarchy available for scroll_to_visible post-jump regression test")
        }
        if !brains.stash.matchScreenElements(ElementMatcher(label: "Jump Target"), limit: 1).isEmpty {
            throw XCTSkip("Parser exposed offscreen scroll content before the jump")
        }

        let recordedElement = makeElement(label: "Jump Target", traits: .button)
        let recordedEntry = TheStash.ScreenElement(
            heistId: "recorded_jump_target",
            contentSpaceOrigin: CGPoint(x: 40, y: 900),
            element: recordedElement,
            object: nil,
            scrollView: scrollView
        )
        let recordedScreen = Screen(
            elements: [recordedEntry.heistId: recordedEntry],
            hierarchy: [],
            containerStableIds: [:],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let result = await brains.navigation.executeScrollToVisible(
            ScrollToVisibleTarget(elementTarget: .matcher(ElementMatcher(label: "Jump Target"))),
            recordedScreen: recordedScreen
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("2 elements match") ?? false,
            "Expected post-jump ambiguity diagnostic, got \(String(describing: result.message))"
        )
    }

    // MARK: - resolveScrollTarget

    func testResolveScrollTargetReturnsNilWhenNoScrollView() {
        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: makeElement(label: "Item"),
            object: UILabel(),
            scrollView: nil
        )

        let target = brains.navigation.resolveScrollTarget(screenElement: screenElement)
        XCTAssertNil(target)

        guard case .failed(let diagnostic) = brains.navigation.resolveScrollTargetResult(
            screenElement: screenElement
        ) else {
            return XCTFail("Expected missing scroll target diagnostic")
        }
        XCTAssertEqual(
            diagnostic.message(for: screenElement),
            "scroll target failed: observed \"Item\" (heistId: item) with no live scrollable ancestor; "
                + "try element_search or target an element inside a scroll container"
        )
    }

    func testResolveScrollTargetReturnsNilWhenNearestScrollViewCannotScrollRequestedAxis() {
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
        XCTAssertNil(target)

        guard case .failed(let diagnostic) = brains.navigation.resolveScrollTargetResult(
            screenElement: screenElement,
            axis: .vertical
        ) else {
            return XCTFail("Expected axis mismatch diagnostic")
        }
        XCTAssertEqual(
            diagnostic.message(for: screenElement),
            "scroll target failed: observed heistId item inside a scroll view that supports no scrolling; "
                + "expected vertical scrolling; try a matching scroll direction or target an element "
                + "inside a matching scroll container"
        )
    }

    func testResolveScrollTargetDoesNotFallbackToUnrelatedAxisContainer() {
        let unrelatedVerticalContainer = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        installScrollableContainers([unrelatedVerticalContainer])

        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 1200, height: 200)

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
        XCTAssertNil(target)
    }

    func testResolveScrollTargetReturnsNearestScrollViewWhenAxisMatches() {
        let unrelatedHorizontalContainer = makeScrollableContainer(
            contentSize: CGSize(width: 2000, height: 320),
            frame: CGRect(x: 0, y: 0, width: 400, height: 320)
        )
        installScrollableContainers([unrelatedHorizontalContainer])

        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 1200)

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
        XCTAssertTrue(
            target === scrollView,
            "Should return the element's stored scroll view"
        )
    }

    // MARK: - SettleSwipeLoopState (Pure Decision Logic)

    func testSettleLoopSameDirectionExitsAfterOneStableFrame() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .sameDirection,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        let step1 = state.advance(
            visibleIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step1, .continue, "Viewport change resets stable counter")
        XCTAssertTrue(state.moved, "Anchor differs, motion detected")

        let step2 = state.advance(
            visibleIds: ["b"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertEqual(step2, .done, "Same-direction profile exits once stable visible count hits 1")
        XCTAssertTrue(state.moved)
    }

    func testSettleLoopDirectionChangeHonorsMinFrames() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<5 {
            let step = state.advance(
                visibleIds: ["a"],
                anchorSignature: 100,
                newHeistIds: []
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) must not exit before minFrames=6")
        }
        let finalStep = state.advance(
            visibleIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertEqual(finalStep, .done, "Direction-change profile exits at frame 6")
        XCTAssertEqual(state.frame, 6)
    }

    func testSettleLoopExitsAtMaxFramesWhenConditionsNeverSettle() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        for frameIndex in 0..<23 {
            let step = state.advance(
                visibleIds: ["id-\(frameIndex)"],
                anchorSignature: 200 + frameIndex,
                newHeistIds: ["id-\(frameIndex)"]
            )
            XCTAssertEqual(step, .continue, "Frame \(frameIndex + 1) churns, should continue")
        }
        let finalStep = state.advance(
            visibleIds: ["id-final"],
            anchorSignature: 999,
            newHeistIds: ["id-final"]
        )
        XCTAssertEqual(finalStep, .done, "Must exit at maxFrames=24 even if never settles")
        XCTAssertEqual(state.frame, 24)
    }

    func testSettleLoopMovedLatchesAndNeverClears() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: 100
        )
        XCTAssertFalse(state.moved)

        _ = state.advance(
            visibleIds: ["a"],
            anchorSignature: 200,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Differing anchor flags motion")

        _ = state.advance(
            visibleIds: ["a"],
            anchorSignature: 100,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "moved only latches true, never clears back to false")
    }

    func testSettleLoopFallsBackToViewportDiffWhenAnchorsUnavailable() {
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a"],
            previousAnchor: nil
        )
        _ = state.advance(
            visibleIds: ["b"],
            anchorSignature: nil,
            newHeistIds: []
        )
        XCTAssertTrue(state.moved, "Without anchors, viewport set difference signals motion")
    }

    func testSettleLoopEdgeBounceDoesNotReportMotion() {
        // Regression guard for the claim that visibleAnchorSignature
        // filters out edge-bounce false positives. When content-space
        // anchors are unchanged across frames, viewport id shuffles
        // (element reorder, reparse flicker) must NOT count as motion.
        var state = Navigation.SettleSwipeLoopState(
            profile: .directionChange,
            previousVisibleIds: ["a", "b"],
            previousAnchor: 500
        )
        _ = state.advance(
            visibleIds: ["a", "c"],
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
            type: .scrollable(contentSize: AccessibilitySize(contentSize)),
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

    private func makeButton(label: String, frame: CGRect) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(label, for: .normal)
        button.accessibilityLabel = label
        button.isAccessibilityElement = true
        button.frame = frame
        return button
    }

    private func makeAccessibleView(label: String, frame: CGRect) -> UIView {
        let view = UIView(frame: frame)
        view.backgroundColor = .white
        view.accessibilityLabel = label
        view.accessibilityTraits = .button
        view.isAccessibilityElement = true
        return view
    }

    private func installModalWindow(rootView: UIView) throws -> UIWindow {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view = rootView
        viewController.view.frame = UIScreen.main.bounds
        viewController.view.accessibilityViewIsModal = true

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 30
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        window.layoutIfNeeded()
        return window
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

    private final class AccessibilityRevealingScrollView: UIScrollView {
        var revealedElements: [UIView] = []
        private let revealThreshold: CGFloat = 500

        override var contentOffset: CGPoint {
            didSet {
                updateAccessibilityVisibility()
            }
        }

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            super.setContentOffset(contentOffset, animated: animated)
            updateAccessibilityVisibility(for: contentOffset)
        }

        func updateAccessibilityVisibility(for offset: CGPoint? = nil) {
            let isRevealed = (offset ?? contentOffset).y >= revealThreshold
            for element in revealedElements {
                element.isAccessibilityElement = isRevealed
            }
        }
    }
}

#endif

#if canImport(UIKit)
import XCTest
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
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.up), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.down), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.left), .horizontal)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.right), .horizontal)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.next), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollDirection.previous), .vertical)
    }

    func testRequiredAxisForScrollEdge() {
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollEdge.top), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollEdge.bottom), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollEdge.left), .horizontal)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollEdge.right), .horizontal)
    }

    func testRequiredAxisForScrollSearchDirection() {
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollSearchDirection.up), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollSearchDirection.down), .vertical)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollSearchDirection.left), .horizontal)
        XCTAssertEqual(TheBrains.requiredAxis(for: ScrollSearchDirection.right), .horizontal)
    }

    // MARK: - uiScrollDirection Mapping

    func testUIScrollDirectionFromScrollSearchDirection() {
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollSearchDirection.down), .down)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollSearchDirection.up), .up)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollSearchDirection.left), .left)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollSearchDirection.right), .right)
    }

    func testUIScrollDirectionFromScrollDirection() {
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.up), .up)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.down), .down)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.left), .left)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.right), .right)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.next), .next)
        XCTAssertEqual(TheBrains.uiScrollDirection(for: ScrollDirection.previous), .previous)
    }

    // MARK: - adaptDirection Cross-Axis Fallback

    func testAdaptDirectionForwardVerticalToHorizontal() {
        let horizontalOnly = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.down, for: horizontalOnly), .right,
                       "Forward vertical request on horizontal-only → .right")
    }

    func testAdaptDirectionBackwardVerticalToHorizontal() {
        let horizontalOnly = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.up, for: horizontalOnly), .left,
                       "Backward vertical request on horizontal-only → .left")
    }

    func testAdaptDirectionForwardHorizontalToVertical() {
        let verticalOnly = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.right, for: verticalOnly), .down,
                       "Forward horizontal request on vertical-only → .down")
    }

    func testAdaptDirectionBackwardHorizontalToVertical() {
        let verticalOnly = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.left, for: verticalOnly), .up,
                       "Backward horizontal request on vertical-only → .up")
    }

    func testAdaptDirectionMatchingAxisPassesThrough() {
        let verticalOnly = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.down, for: verticalOnly), .down)
        XCTAssertEqual(TheBrains.adaptDirection(.up, for: verticalOnly), .up)
    }

    func testAdaptDirectionBothAxesPassesThrough() {
        let biaxial = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 2000)
        )
        XCTAssertEqual(TheBrains.adaptDirection(.down, for: biaxial), .down)
        XCTAssertEqual(TheBrains.adaptDirection(.right, for: biaxial), .right)
        XCTAssertEqual(TheBrains.adaptDirection(.up, for: biaxial), .up)
        XCTAssertEqual(TheBrains.adaptDirection(.left, for: biaxial), .left)
    }

    // MARK: - ScrollableTarget Properties

    func testScrollableTargetFrameForUIScrollView() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let scrollView = UIScrollView(frame: frame)
        let target = TheBrains.ScrollableTarget.uiScrollView(scrollView)

        XCTAssertEqual(target.frame, frame)
    }

    func testScrollableTargetFrameForSwipeable() {
        let frame = CGRect(x: 10, y: 20, width: 300, height: 400)
        let contentSize = CGSize(width: 600, height: 800)
        let target = TheBrains.ScrollableTarget.swipeable(frame: frame, contentSize: contentSize)

        XCTAssertEqual(target.frame, frame)
        XCTAssertEqual(target.contentSize, contentSize)
    }

    func testScrollableTargetContentSizeForUIScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        scrollView.contentSize = CGSize(width: 375, height: 5000)
        let target = TheBrains.ScrollableTarget.uiScrollView(scrollView)

        XCTAssertEqual(target.contentSize, CGSize(width: 375, height: 5000))
    }

    // MARK: - Scroll Axis Detection (Swipeable variant)

    func testScrollableAxisSwipeableHorizontalOnly() {
        let target = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        let axis = TheBrains.scrollableAxis(of: target)
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertFalse(axis.contains(.vertical))
    }

    func testScrollableAxisSwipeableVerticalOnly() {
        let target = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 2000)
        )
        let axis = TheBrains.scrollableAxis(of: target)
        XCTAssertFalse(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisSwipeableNoOverflow() {
        let target = TheBrains.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 400, height: 200)
        )
        let axis = TheBrains.scrollableAxis(of: target)
        XCTAssertTrue(axis.isEmpty)
    }

    // MARK: - offViewportRegistryEntry

    func testOffViewportEntryByHeistIdReturnsWhenOffScreen() {
        let element = makeElement(label: "Item")
        let heistId = "button_item"
        brains.stash.registry.elements[heistId] = TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: CGPoint(x: 0, y: 2000),
            element: element,
            object: nil,
            scrollView: nil
        )
        brains.stash.registry.viewportIds = ["other_element"]

        let entry = brains.offViewportRegistryEntry(for: .heistId(heistId))
        XCTAssertNotNil(entry, "Should return entry when heistId is not in viewport")
        XCTAssertEqual(entry?.heistId, heistId)
    }

    func testOffViewportEntryByHeistIdReturnsNilWhenOnScreen() {
        let element = makeElement(label: "Item")
        let heistId = "button_item"
        brains.stash.registry.elements[heistId] = TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        )
        brains.stash.registry.viewportIds = [heistId]

        let entry = brains.offViewportRegistryEntry(for: .heistId(heistId))
        XCTAssertNil(entry, "Should return nil when heistId is in viewport")
    }

    func testOffViewportEntryByMatcherReturnsOffScreenMatch() {
        let element = makeElement(label: "Target Button", traits: .button)
        let heistId = "button_target_button"
        brains.stash.registry.elements[heistId] = TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: CGPoint(x: 0, y: 3000),
            element: element,
            object: nil,
            scrollView: nil
        )
        brains.stash.registry.viewportIds = ["other_element"]

        let matcher = ElementMatcher(label: "Target Button")
        let entry = brains.offViewportRegistryEntry(for: .matcher(matcher))
        XCTAssertNotNil(entry, "Should find off-viewport element by matcher")
        XCTAssertEqual(entry?.heistId, heistId)
    }

    func testOffViewportEntryByMatcherReturnsNilWhenOnScreen() {
        let element = makeElement(label: "Visible Item", traits: .button)
        let heistId = "button_visible_item"
        brains.stash.registry.elements[heistId] = TheStash.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            element: element,
            object: nil,
            scrollView: nil
        )
        brains.stash.registry.viewportIds = [heistId]

        let matcher = ElementMatcher(label: "Visible Item")
        let entry = brains.offViewportRegistryEntry(for: .matcher(matcher))
        XCTAssertNil(entry, "Should return nil when matched element is in viewport")
    }

    // MARK: - ContainerExploreState

    func testContainerExploreStateStoresValues() {
        let state = TheBrains.ContainerExploreState(
            visibleSubtreeFingerprint: 12345,
            discoveredHeistIds: ["id_a", "id_b", "id_c"]
        )
        XCTAssertEqual(state.visibleSubtreeFingerprint, 12345)
        XCTAssertEqual(state.discoveredHeistIds.count, 3)
        XCTAssertTrue(state.discoveredHeistIds.contains("id_a"))
    }

    // MARK: - ExplorePhase lifecycle

    func testExplorePhaseIdleOutsideExplore() {
        XCTAssertEqual(brains.explorePhase, .idle,
                       "explorePhase should be .idle when no explore cycle is active")
    }

    func testClearCacheResetsExploreState() {
        brains.containerExploreStates[
            AccessibilityContainer(
                type: .scrollable(contentSize: CGSize(width: 375, height: 2000)),
                frame: .zero
            )
        ] = TheBrains.ContainerExploreState(
            visibleSubtreeFingerprint: 1,
            discoveredHeistIds: ["x"]
        )
        brains.beginExploreCycle()

        brains.clearCache()

        XCTAssertTrue(brains.containerExploreStates.isEmpty,
                      "clearCache should empty containerExploreStates")
        XCTAssertEqual(brains.explorePhase, .idle,
                       "clearCache should reset explorePhase to .idle")
    }

    // MARK: - resolveScrollTarget

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

        let target = brains.resolveScrollTarget(
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

    func testResolveScrollTargetReturnsSwipeableWhenForceSwipeEnabled() {
        let forcedBrains = TheBrains(
            tripwire: TheTripwire(),
            forceSwipeScrolling: true
        )
        let scrollView = UIScrollView(frame: CGRect(x: 10, y: 20, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 1200)

        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: makeElement(),
            object: nil,
            scrollView: scrollView
        )

        let target = forcedBrains.resolveScrollTarget(
            screenElement: screenElement, axis: .vertical
        )
        if case .swipeable = target {
            XCTAssertTrue(true, "Forced swipe mode should convert UIScrollView targets to .swipeable")
        } else {
            XCTFail("Expected .swipeable in force mode, got \(String(describing: target))")
        }
    }

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        traits: UIAccessibilityTraits = .none
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: label ?? "",
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

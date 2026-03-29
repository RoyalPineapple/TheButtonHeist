#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBagmanScrollTests: XCTestCase {

    private var bagman: TheBagman!

    override func setUp() {
        super.setUp()
        bagman = TheBagman(tripwire: TheTripwire())
    }

    override func tearDown() {
        bagman = nil
        super.tearDown()
    }

    // MARK: - scrollableAncestors

    func testScrollableAncestorsReturnsInnermostFirst() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 400, height: 2000)

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 800, height: 200)
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        let ancestors = bagman.scrollableAncestors(of: label, includeSelf: false)
        XCTAssertEqual(ancestors.count, 2)
        XCTAssertTrue(ancestors[0] === innerScroll, "First ancestor should be innermost")
        XCTAssertTrue(ancestors[1] === outerScroll, "Second ancestor should be outermost")
    }

    func testScrollableAncestorsIncludesSelfWhenScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let ancestors = bagman.scrollableAncestors(of: scrollView, includeSelf: true)
        XCTAssertEqual(ancestors.count, 1)
        XCTAssertTrue(ancestors[0] === scrollView)
    }

    func testScrollableAncestorsExcludesDisabledScrollViews() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true

        let disabledScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        disabledScroll.isScrollEnabled = false
        outerScroll.addSubview(disabledScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        disabledScroll.addSubview(label)

        let ancestors = bagman.scrollableAncestors(of: label, includeSelf: false)
        XCTAssertEqual(ancestors.count, 1)
        XCTAssertTrue(ancestors[0] === outerScroll, "Disabled scroll view should be skipped")
    }

    func testScrollableAncestorReturnsInnermost() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        let ancestor = bagman.scrollableAncestor(of: label, includeSelf: false)
        XCTAssertTrue(ancestor === innerScroll, "scrollableAncestor should return innermost")
    }

    // MARK: - resolveScrollView

    func testResolveScrollViewWithExplicitHeistId() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))

        bagman.screenElements["myScrollView"] = TheBagman.ScreenElement(
            heistId: "myScrollView",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "myScrollView"),
            presented: true,
            object: scrollView,
            scrollView: nil
        )

        let resolved = bagman.resolveScrollView(heistId: "myScrollView", element: label, includeSelf: false)
        XCTAssertTrue(resolved === scrollView)
    }

    func testResolveScrollViewFallsBackToAncestorWhenNoHeistId() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        scrollView.addSubview(label)

        let resolved = bagman.resolveScrollView(heistId: nil, element: label, includeSelf: false)
        XCTAssertTrue(resolved === scrollView)
    }

    func testResolveScrollViewReturnsNilForUnknownHeistId() {
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))

        let resolved = bagman.resolveScrollView(heistId: "nonexistent", element: label, includeSelf: false)
        XCTAssertNil(resolved)
    }

    // MARK: - findAllScrollViews

    func testFindAllScrollViewsDeduplicates() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let label1 = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        scrollView.addSubview(label1)
        let label2 = UILabel(frame: CGRect(x: 10, y: 40, width: 100, height: 20))
        scrollView.addSubview(label2)

        registerOnScreen("label1", object: label1, index: 0)
        registerOnScreen("label2", object: label2, index: 1)

        let scrollViews = bagman.findAllScrollViews()
        XCTAssertEqual(scrollViews.count, 1, "Same scroll view should not be duplicated")
        XCTAssertTrue(scrollViews[0] === scrollView)
    }

    func testFindAllScrollViewsFindsNestedScrollViews() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        registerOnScreen("label", object: label, index: 0)

        let scrollViews = bagman.findAllScrollViews()
        XCTAssertEqual(scrollViews.count, 2)
        XCTAssertTrue(scrollViews[0] === innerScroll, "Innermost should be first")
        XCTAssertTrue(scrollViews[1] === outerScroll, "Outermost should be second")
    }

    // MARK: - Scroll Axis Detection

    func testScrollableAxisHorizontal() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 2000, height: 200)

        let axis = bagman.scrollableAxis(of: scrollView)
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertFalse(axis.contains(.vertical))
    }

    func testScrollableAxisVertical() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 2000)

        let axis = bagman.scrollableAxis(of: scrollView)
        XCTAssertFalse(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisBoth() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 2000, height: 2000)

        let axis = bagman.scrollableAxis(of: scrollView)
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisEmptyWhenContentFits() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let axis = bagman.scrollableAxis(of: scrollView)
        XCTAssertTrue(axis.isEmpty)
    }

    // MARK: - Axis-Aware resolveScrollView

    func testResolveScrollViewAxisSkipsHorizontalForDown() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 400, height: 2000)

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 2000, height: 200)
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        let resolved = bagman.resolveScrollView(
            heistId: nil, element: label, includeSelf: false, axis: .vertical
        )
        XCTAssertTrue(resolved === outerScroll, "Should skip horizontal inner, return vertical outer")
    }

    func testResolveScrollViewAxisReturnsHorizontalForRight() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 400, height: 2000)

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 2000, height: 200)
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        let resolved = bagman.resolveScrollView(
            heistId: nil, element: label, includeSelf: false, axis: .horizontal
        )
        XCTAssertTrue(resolved === innerScroll, "Should return horizontal inner for right scroll")
    }

    func testResolveScrollViewAxisFallsBackWhenNoMatch() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 2000, height: 800)

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 2000, height: 200)
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        let resolved = bagman.resolveScrollView(
            heistId: nil, element: label, includeSelf: false, axis: .vertical
        )
        XCTAssertNotNil(resolved, "Should fall back to innermost when no axis match")
        XCTAssertTrue(resolved === innerScroll, "Fallback should be innermost ancestor")
    }

    func testResolveScrollViewExplicitHeistIdIgnoresAxis() {
        let horizontalScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        horizontalScroll.isScrollEnabled = true
        horizontalScroll.contentSize = CGSize(width: 2000, height: 200)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))

        bagman.screenElements["myHorizScroll"] = TheBagman.ScreenElement(
            heistId: "myHorizScroll",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "myHorizScroll"),
            presented: true,
            object: horizontalScroll,
            scrollView: nil
        )

        let resolved = bagman.resolveScrollView(
            heistId: "myHorizScroll", element: label, includeSelf: false, axis: .vertical
        )
        XCTAssertTrue(resolved === horizontalScroll, "Explicit heistId should override axis")
    }

    // MARK: - Search Order

    func testFindAllScrollViewsOutermostFirstForSearch() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 400, height: 2000)

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 2000, height: 200)
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        registerOnScreen("label", object: label, index: 0)

        let scrollViews = bagman.findAllScrollViewsOutermostFirst()
        XCTAssertEqual(scrollViews.count, 2)
        XCTAssertTrue(scrollViews[0] === outerScroll, "Outermost should be first for search")
        XCTAssertTrue(scrollViews[1] === innerScroll, "Innermost should be second for search")
    }

    // MARK: - adaptDirection

    func testAdaptDirectionMatchingAxis() {
        let target = TheBagman.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(bagman.adaptDirection(.down, for: target), .down)
        XCTAssertEqual(bagman.adaptDirection(.up, for: target), .up)
    }

    func testAdaptDirectionCrossAxis() {
        let target = TheBagman.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(bagman.adaptDirection(.down, for: target), .right,
                       "Forward vertical → forward horizontal")
        XCTAssertEqual(bagman.adaptDirection(.up, for: target), .left,
                       "Backward vertical → backward horizontal")
    }

    func testAdaptDirectionCrossAxisVertical() {
        let target = TheBagman.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(bagman.adaptDirection(.right, for: target), .down,
                       "Forward horizontal → forward vertical")
        XCTAssertEqual(bagman.adaptDirection(.left, for: target), .up,
                       "Backward horizontal → backward vertical")
    }

    // MARK: - Helpers

    private func makeWire(heistId: String) -> HeistElement {
        HeistElement(
            heistId: heistId, order: 0, description: "", label: nil, value: nil,
            identifier: nil, hint: nil, traits: [], frameX: 0, frameY: 0,
            frameWidth: 0, frameHeight: 0, activationPointX: 0, activationPointY: 0,
            actions: []
        )
    }

    private func registerOnScreen(_ heistId: String, object: NSObject, index: Int) {
        bagman.screenElements[heistId] = TheBagman.ScreenElement(
            heistId: heistId,
            contentSpaceOrigin: nil,
            lastTraversalIndex: index,
            wire: makeWire(heistId: heistId),
            presented: true,
            object: object,
            scrollView: nil
        )
        bagman.onScreen.insert(heistId)
    }
}

#endif

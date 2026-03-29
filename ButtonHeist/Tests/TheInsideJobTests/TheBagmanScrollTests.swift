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

    // MARK: - scrollableAncestor (ensureOnScreen fallback)

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

    func testScrollableAncestorIncludesSelf() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let ancestor = bagman.scrollableAncestor(of: scrollView, includeSelf: true)
        XCTAssertTrue(ancestor === scrollView)
    }

    func testScrollableAncestorExcludesDisabled() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true

        let disabledScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        disabledScroll.isScrollEnabled = false
        outerScroll.addSubview(disabledScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        disabledScroll.addSubview(label)

        let ancestor = bagman.scrollableAncestor(of: label, includeSelf: false)
        XCTAssertTrue(ancestor === outerScroll, "Disabled scroll view should be skipped")
    }

    // MARK: - resolveScrollTarget (accessibility hierarchy driven)

    func testResolveScrollTargetFromScreenElementScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true
        scrollView.contentSize = CGSize(width: 400, height: 2000)

        let screenEl = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: UILabel(),
            scrollView: scrollView
        )

        let target = bagman.resolveScrollTarget(heistId: nil, screenElement: screenEl)
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === scrollView)
        } else {
            XCTFail("Expected .uiScrollView, got \(String(describing: target))")
        }
    }

    func testResolveScrollTargetAxisMismatchWalksAncestors() {
        let outerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        outerScroll.isScrollEnabled = true
        outerScroll.contentSize = CGSize(width: 400, height: 2000) // vertical only

        let innerScroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        innerScroll.isScrollEnabled = true
        innerScroll.contentSize = CGSize(width: 2000, height: 200) // horizontal only
        outerScroll.addSubview(innerScroll)

        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 100, height: 20))
        innerScroll.addSubview(label)

        // screenElement.scrollView is the inner horizontal, but we want vertical
        let screenEl = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: label,
            scrollView: innerScroll
        )

        let target = bagman.resolveScrollTarget(heistId: nil, screenElement: screenEl, axis: .vertical)
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === outerScroll, "Should walk ancestors to find vertical scroll view")
        } else {
            XCTFail("Expected .uiScrollView(outer), got \(String(describing: target))")
        }
    }

    func testResolveScrollTargetExplicitHeistId() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true

        let screenEl = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: UILabel(),
            scrollView: nil
        )

        bagman.screenElements["myScroll"] = TheBagman.ScreenElement(
            heistId: "myScroll",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 1,
            wire: makeWire(heistId: "myScroll"),
            presented: true,
            object: scrollView,
            scrollView: nil
        )

        let target = bagman.resolveScrollTarget(heistId: "myScroll", screenElement: screenEl)
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === scrollView)
        } else {
            XCTFail("Expected .uiScrollView, got \(String(describing: target))")
        }
    }

    func testResolveScrollTargetReturnsNilWhenNoScrollView() {
        let screenEl = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: UILabel(),
            scrollView: nil
        )

        let target = bagman.resolveScrollTarget(heistId: nil, screenElement: screenEl)
        XCTAssertNil(target)
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
}

#endif

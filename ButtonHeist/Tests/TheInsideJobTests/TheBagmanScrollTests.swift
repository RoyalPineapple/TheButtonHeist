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

    // MARK: - resolveScrollTarget (accessibility hierarchy driven)

    func testResolveScrollTargetFromScreenElementScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true
        scrollView.contentSize = CGSize(width: 400, height: 2000)

        let screenElement = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: UILabel(),
            scrollView: scrollView
        )

        let target = bagman.resolveScrollTarget(screenElement: screenElement)
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === scrollView)
        } else {
            XCTFail("Expected .uiScrollView, got \(String(describing: target))")
        }
    }

    func testResolveScrollTargetReturnsNilWhenNoScrollView() {
        let screenElement = TheBagman.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            lastTraversalIndex: 0,
            wire: makeWire(heistId: "item"),
            presented: true,
            object: UILabel(),
            scrollView: nil
        )

        let target = bagman.resolveScrollTarget(screenElement: screenElement)
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
            heistId: heistId, description: "", label: nil, value: nil,
            identifier: nil, hint: nil, traits: [], frameX: 0, frameY: 0,
            frameWidth: 0, frameHeight: 0, activationPointX: 0, activationPointY: 0,
            actions: []
        )
    }
}

#endif

#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
import TheScore

@MainActor
final class TheSafecrackerScrollTests: XCTestCase {

    private var safecracker: TheSafecracker!

    override func setUp() {
        super.setUp()
        safecracker = TheSafecracker()
    }

    override func tearDown() {
        safecracker = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a scroll view with given frame and content size at origin (0,0).
    private func makeScrollView(
        frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 800),
        contentSize: CGSize = CGSize(width: 400, height: 3000),
        contentOffset: CGPoint = .zero
    ) -> UIScrollView {
        let sv = UIScrollView(frame: frame)
        sv.contentSize = contentSize
        sv.contentOffset = contentOffset
        return sv
    }

    // MARK: - scrollByPage: basic clamped behavior

    func testScrollByPageDownClampsToContentSize() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 1000)
        )
        // Page = 800 - 44 = 756, content max = 1000 - 800 = 200
        let moved = safecracker.scrollByPage(sv, direction: .down, animated: false)
        XCTAssertTrue(moved)
        XCTAssertEqual(sv.contentOffset.y, 200, accuracy: 0.01)
    }

    func testScrollByPageDownReturnsFalseAtEdge() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 1000),
            contentOffset: CGPoint(x: 0, y: 200)
        )
        let moved = safecracker.scrollByPage(sv, direction: .down, animated: false)
        XCTAssertFalse(moved, "Should return false when already at bottom edge")
    }

    func testScrollByPageUpFromMiddle() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 1000))
        let moved = safecracker.scrollByPage(sv, direction: .up, animated: false)
        XCTAssertTrue(moved)
        // 1000 - (800 - 44) = 244
        XCTAssertEqual(sv.contentOffset.y, 244, accuracy: 0.01)
    }

    func testScrollByPageUpClampsToTop() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 100))
        let moved = safecracker.scrollByPage(sv, direction: .up, animated: false)
        XCTAssertTrue(moved)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollByPageRightClampsToContentSize() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 600, height: 800)
        )
        // Page = 400 - 44 = 356, content max = 600 - 400 = 200
        let moved = safecracker.scrollByPage(sv, direction: .right, animated: false)
        XCTAssertTrue(moved)
        XCTAssertEqual(sv.contentOffset.x, 200, accuracy: 0.01)
    }

    // MARK: - scrollByPage: unclamped (lazy container mode)

    // MARK: - scrollToEdge

    func testScrollToEdgeBottom() {
        let sv = makeScrollView()
        let moved = safecracker.scrollToEdge(sv, edge: .bottom)
        XCTAssertTrue(moved)
        XCTAssertEqual(sv.contentOffset.y, 3000 - 800, accuracy: 0.01)
    }

    func testScrollToEdgeTop() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 1000))
        let moved = safecracker.scrollToEdge(sv, edge: .top)
        XCTAssertTrue(moved)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollToEdgeReturnsFalseWhenAlreadyAtEdge() {
        let sv = makeScrollView(contentOffset: .zero)
        let moved = safecracker.scrollToEdge(sv, edge: .top)
        XCTAssertFalse(moved, "Already at edge should return false (no scroll needed)")
    }

    // MARK: - scrollToOppositeEdge

    func testScrollToOppositeEdgeFromDown() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 1000))
        safecracker.scrollToOppositeEdge(sv, from: .down)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01,
                       "Opposite of down is top")
    }

    func testScrollToOppositeEdgeFromUp() {
        let sv = makeScrollView(contentOffset: .zero)
        safecracker.scrollToOppositeEdge(sv, from: .up)
        // maxY = 3000 - 800 = 2200
        XCTAssertEqual(sv.contentOffset.y, 2200, accuracy: 0.01,
                       "Opposite of up is bottom")
    }

    func testScrollToOppositeEdgeFromRight() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 2000, height: 800),
            contentOffset: CGPoint(x: 500, y: 0)
        )
        safecracker.scrollToOppositeEdge(sv, from: .right)
        XCTAssertEqual(sv.contentOffset.x, 0, accuracy: 0.01)
    }

    // MARK: - queryCollectionTotalItems

    func testQueryCollectionTotalItemsReturnsNilForPlainScrollView() {
        let sv = makeScrollView()
        let result = safecracker.queryCollectionTotalItems(sv)
        XCTAssertNil(result, "Plain UIScrollView should return nil (lazy mode)")
    }

    // MARK: - scrollByPage: overlap verification

    func testScrollByPageUses44PointOverlap() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 5000)
        )
        _ = safecracker.scrollByPage(sv, direction: .down, animated: false)
        XCTAssertEqual(sv.contentOffset.y, 756, accuracy: 0.01,
                       "Page scroll should be frame.height - 44pt overlap = 756")

        let firstOffset = sv.contentOffset.y
        _ = safecracker.scrollByPage(sv, direction: .down, animated: false)
        XCTAssertEqual(sv.contentOffset.y, firstOffset + 756, accuracy: 0.01,
                       "Second page scroll should add another 756")
    }

    // MARK: - scrollToMakeVisible

    func testScrollToMakeVisibleWhenAlreadyVisible() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 3000)
        )
        let targetFrame = CGRect(x: 50, y: 50, width: 100, height: 44)
        let result = safecracker.scrollToMakeVisible(targetFrame, in: sv)
        XCTAssertTrue(result)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01,
                       "Should not scroll when target is already visible")
    }
    // MARK: - scrollToMakeVisible: comfort margin

    func testScrollToMakeVisibleComfortMarginScrollsElementOutsideComfortZone() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 3000)
        )
        // Comfort zone with 1/6 margin: top ≈ 133, bottom ≈ 667.
        // Element at y=750 is inside the full visible rect (0..800) but below
        // the comfort zone bottom (~667), so it should trigger a scroll.
        let targetFrame = CGRect(x: 50, y: 750, width: 100, height: 44)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        XCTAssertGreaterThan(sv.contentOffset.y, 0,
                             "Should scroll down to bring element into comfort zone")
    }

    func testScrollToMakeVisibleComfortMarginNoScrollWhenInsideComfortZone() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 3000)
        )
        // Element well within the comfort zone (middle 2/3 = ~133..667).
        let targetFrame = CGRect(x: 50, y: 300, width: 100, height: 44)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01,
                       "Should not scroll when element is already in comfort zone")
    }

    func testScrollToMakeVisibleLargeTargetFallsBackToFullVisibleRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: CGPoint(x: 0, y: 500)
        )
        // Comfort zone with 1/6 margin: height = 600 * (2/3) = 400.
        // Target is 450pt tall — exceeds the comfort zone, so the method
        // should fall back to the full visible rect instead.
        let targetFrame = CGRect(x: 0, y: 200, width: 400, height: 450)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        // With full visible rect fallback (500..1100), the target (200..650 in content space)
        // needs to scroll up. The key assertion is that it scrolled at all — the fallback
        // to fullVisibleRect allowed the scroll instead of using the too-small comfort zone.
        XCTAssertLessThan(sv.contentOffset.y, 500,
                          "Should fall back to full visible rect and scroll for oversized target")
    }

    func testScrollToMakeVisibleLargeTargetOnlyOneAxisExceedsComfortZone() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 2000, height: 3000),
            contentOffset: CGPoint(x: 500, y: 500)
        )
        // Comfort zone: width = 400 * 2/3 ≈ 267, height = 600 * 2/3 = 400.
        // Target width (300) exceeds comfort width (267) but target height (100) fits.
        // The fallback is all-or-nothing: both axes lose the margin.
        let targetFrame = CGRect(x: 200, y: 200, width: 300, height: 100)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        // Should use full visible rect (not comfort zone) since one axis exceeds comfort.
        // Target in content space starts at x: 200+500=700 relative to content,
        // but the key point is the fallback was applied — no crash, scroll happened.
        let offsetMoved = sv.contentOffset.x != 500 || sv.contentOffset.y != 500
        XCTAssertTrue(offsetMoved,
                      "Should scroll using full visible rect when target exceeds comfort zone on one axis")
    }
}
#endif

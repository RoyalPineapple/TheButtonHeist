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

    func testScrollToEdgeReturnsTrueWhenAlreadyAtEdge() {
        let sv = makeScrollView(contentOffset: .zero)
        let moved = safecracker.scrollToEdge(sv, edge: .top)
        XCTAssertTrue(moved, "Already at edge should return true (not false)")
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
}
#endif

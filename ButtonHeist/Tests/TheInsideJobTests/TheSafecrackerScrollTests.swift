#if canImport(UIKit)
import XCTest
@testable import TheInsideJob
import TheScore

@MainActor
final class TheSafecrackerScrollTests: XCTestCase {

    private var safecracker: TheSafecracker!

    override func setUp() async throws {
        try await super.setUp()
        safecracker = TheSafecracker()
    }

    override func tearDown() async throws {
        safecracker = nil
        try await super.tearDown()
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
        XCTAssertEqual(moved, .moved)
        XCTAssertEqual(sv.contentOffset.y, 200, accuracy: 0.01)
    }

    func testScrollByPageDownReportsAlreadyInPositionAtEdge() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 1000),
            contentOffset: CGPoint(x: 0, y: 200)
        )
        let moved = safecracker.scrollByPage(sv, direction: .down, animated: false)
        XCTAssertEqual(moved, .alreadyInPosition)
    }

    func testScrollByPageUpFromMiddle() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 1000))
        let moved = safecracker.scrollByPage(sv, direction: .up, animated: false)
        XCTAssertEqual(moved, .moved)
        // 1000 - (800 - 44) = 244
        XCTAssertEqual(sv.contentOffset.y, 244, accuracy: 0.01)
    }

    func testScrollByPageUpClampsToTop() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 100))
        let moved = safecracker.scrollByPage(sv, direction: .up, animated: false)
        XCTAssertEqual(moved, .moved)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollByPageRightClampsToContentSize() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 600, height: 800)
        )
        // Page = 400 - 44 = 356, content max = 600 - 400 = 200
        let moved = safecracker.scrollByPage(sv, direction: .right, animated: false)
        XCTAssertEqual(moved, .moved)
        XCTAssertEqual(sv.contentOffset.x, 200, accuracy: 0.01)
    }

    // MARK: - scrollByPage: unclamped (lazy container mode)

    // MARK: - scrollToEdge

    func testScrollToEdgeBottom() {
        let sv = makeScrollView()
        let result = safecracker.scrollToEdge(sv, edge: .bottom)
        XCTAssertEqual(result, .moved)
        XCTAssertEqual(sv.contentOffset.y, 3000 - 800, accuracy: 0.01)
    }

    func testScrollToEdgeTop() {
        let sv = makeScrollView(contentOffset: CGPoint(x: 0, y: 1000))
        let result = safecracker.scrollToEdge(sv, edge: .top)
        XCTAssertEqual(result, .moved)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollToEdgeReportsAlreadyAtEdge() {
        let sv = makeScrollView(contentOffset: .zero)
        let result = safecracker.scrollToEdge(sv, edge: .top)
        XCTAssertEqual(result, .alreadyInPosition)
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

    // MARK: - scrollToMakeScreenPointVisible

    func testScrollToMakeScreenPointVisibleReportsAlreadyInPositionWhenAlreadyInPreferredScreenRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 1000),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: .zero
        )
        let result = safecracker.scrollToMakeScreenPointVisible(
            CGPoint(x: 200, y: 300),
            in: sv,
            animated: false,
            preferredScreenRect: CGRect(x: 0, y: 120, width: 400, height: 600),
            minimumScreenRect: CGRect(x: 0, y: 0, width: 400, height: 874)
        )

        XCTAssertEqual(result, .alreadyInPosition)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }

    func testScrollToMakeScreenPointVisibleCentersPointInPreferredScreenRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 1000),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: .zero
        )
        let result = safecracker.scrollToMakeScreenPointVisible(
            CGPoint(x: 200, y: 888),
            in: sv,
            animated: false,
            preferredScreenRect: CGRect(x: 0, y: 120, width: 400, height: 600),
            minimumScreenRect: CGRect(x: 0, y: 0, width: 400, height: 874)
        )

        XCTAssertEqual(result, .moved)
        XCTAssertEqual(sv.contentOffset.y, 468, accuracy: 0.01)
    }

    func testScrollToMakeScreenPointVisibleReportsUnavailableWhenClampLeavesPointOutsideMinimumRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 1000),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: .zero
        )
        let result = safecracker.scrollToMakeScreenPointVisible(
            CGPoint(x: 200, y: -100),
            in: sv,
            animated: false,
            preferredScreenRect: CGRect(x: 0, y: 120, width: 400, height: 600),
            minimumScreenRect: CGRect(x: 0, y: 0, width: 400, height: 874)
        )

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(sv.contentOffset.y, 0, accuracy: 0.01)
    }
}
#endif

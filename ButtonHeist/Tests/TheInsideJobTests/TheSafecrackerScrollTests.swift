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

    func testScrollToMakeVisibleReturnsFalseWhenClampedOffsetStillLeavesTargetOffscreen() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 1200, height: 600),
            contentOffset: .zero
        )
        let targetFrame = CGRect(x: -80, y: 100, width: 40, height: 40)

        let result = safecracker.scrollToMakeVisible(targetFrame, in: sv, animated: false)

        XCTAssertFalse(result)
        XCTAssertEqual(sv.contentOffset.x, 0, accuracy: 0.01)
    }

    func testScrollToMakeVisibleReturnsFalseWhenChangedClampStillLeavesTargetOffscreen() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 1200, height: 600),
            contentOffset: CGPoint(x: 10, y: 0)
        )
        let targetFrame = CGRect(x: -80, y: 100, width: 40, height: 40)

        let result = safecracker.scrollToMakeVisible(targetFrame, in: sv, animated: false)

        XCTAssertFalse(result)
        XCTAssertEqual(sv.contentOffset.x, 10, accuracy: 0.01)
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

    func testScrollToMakeVisibleLargeTargetUsesFullVisibleRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: CGPoint(x: 0, y: 500)
        )
        // Comfort zone with 1/6 margin: height = 600 * (2/3) = 400.
        // Target is 450pt tall, so the method should use the full visible
        // rect on the oversized axis.
        let targetFrame = CGRect(x: 0, y: 200, width: 400, height: 450)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        // With the full visible rect (500..1100), the target (200..650 in content
        // space) needs to scroll up. The key assertion is that it scrolled at all.
        XCTAssertLessThan(sv.contentOffset.y, 500,
                          "Should use the full visible rect and scroll for oversized target")
    }

    func testScrollToMakeVisibleKeepsComfortMarginOnAxisThatFits() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 2000, height: 3000),
            contentOffset: .zero
        )
        // Comfort zone: width = 400 * 2/3, height = 600 * 2/3 = 400.
        // Target width (300) exceeds comfort width (267) but target height (100) fits.
        // Horizontal reveal uses the full visible rect, but vertical reveal should
        // still use the comfort margin and nudge the target upward.
        let targetFrame = CGRect(x: 50, y: 490, width: 300, height: 100)
        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )
        XCTAssertTrue(result)
        XCTAssertEqual(sv.contentOffset.x, 0, accuracy: 0.01)
        XCTAssertEqual(sv.contentOffset.y, 90, accuracy: 0.01,
                       "The axis that fits the comfort zone should keep its comfort margin")
    }

    func testScrollToMakeVisibleScrollsOversizedTargetUntilViewportIntersectsIt() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 600),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: .zero
        )
        let targetFrame = CGRect(x: 0, y: 900, width: 400, height: 900)

        let result = safecracker.scrollToMakeVisible(
            targetFrame, in: sv, animated: false,
            comfortMarginFraction: 1.0 / 6.0
        )

        XCTAssertTrue(result)
        XCTAssertEqual(sv.contentOffset.y, 1200, accuracy: 0.01,
                       "Oversized targets cannot fit fully, but reveal should still bring the target onto screen")
    }

    func testScrollToMakeActivationPointVisibleCentersPointInPreferredScreenRect() {
        let sv = makeScrollView(
            frame: CGRect(x: 0, y: 0, width: 400, height: 1000),
            contentSize: CGSize(width: 400, height: 3000),
            contentOffset: .zero
        )
        let result = safecracker.scrollToMakeActivationPointVisible(
            CGPoint(x: 200, y: 888),
            in: sv,
            animated: false,
            preferredScreenRect: CGRect(x: 0, y: 120, width: 400, height: 600),
            minimumScreenRect: CGRect(x: 0, y: 0, width: 400, height: 874)
        )

        XCTAssertTrue(result)
        XCTAssertEqual(sv.contentOffset.y, 468, accuracy: 0.01)
    }
}
#endif

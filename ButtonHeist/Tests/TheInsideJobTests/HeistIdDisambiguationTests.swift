#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

// MARK: - Regression: duplicate-heistId disambiguation through buildScreen

/// `TheBurglar.buildScreen(from:)` is the production path that turns parsed
/// accessibility elements into externally visible heistIds. These cases lock
/// the current duplicate-disambiguation contract for scrollable content:
/// duplicated synthesized ids get traversal-order `_N` suffixes through
/// `IdAssignment.assign`, and `buildScreen` does not emit `_at_X_Y` content
/// position suffixes for these observable cases.
@MainActor
final class HeistIdDisambiguationTests: XCTestCase {

    // MARK: - Helpers

    /// Anchor window kept alive for the lifetime of a test so the
    /// `scrollView.convert(_:from:)` calls in `TheBurglar` resolve against
    /// a deterministic window coordinate space.
    private var anchorWindow: UIWindow?

    override func setUp() async throws {
        try await super.setUp()
        anchorWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
    }

    override func tearDown() async throws {
        anchorWindow?.isHidden = true
        anchorWindow = nil
        try await super.tearDown()
    }

    /// Build a `ParseResult` with one scrollable container whose children are
    /// the given elements. The scroll view is parented to an anchor window
    /// at the origin so the content-space conversion is the identity transform.
    private func makeScrollableParseResult(
        elements: [AccessibilityElement]
    ) -> TheBurglar.ParseResult {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 2000))
        scrollView.contentSize = CGSize(width: 320, height: 4000)
        anchorWindow?.addSubview(scrollView)

        let container = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(scrollView.contentSize)),
            frame: scrollView.frame
        )
        let children: [AccessibilityHierarchy] = elements.enumerated().map { index, element in
            .element(element, traversalIndex: index)
        }
        return TheBurglar.ParseResult(
            hierarchy: [.container(container, children: children)],
            objects: [:],
            scrollViews: [container: scrollView]
        )
    }

    private func makeButton(
        label: String,
        frame: CGRect,
        value: String? = nil
    ) -> AccessibilityElement {
        .make(
            label: label,
            value: value,
            traits: .button,
            shape: .frame(frame),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            respondsToUserInteraction: true
        )
    }

    /// End-anchored regex matching the exact `_at_<int>_<int>` suffix shape
    /// produced by `contentPositionHeistId`. A substring check would
    /// false-positive on labels that slugify to contain "at" as a word.
    private static let contentPositionSuffixRegex = /_at_-?\d+_-?\d+$/

    private func assertNoContentPositionSuffix(
        in screen: Screen,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for heistId in screen.elements.keys {
            XCTAssertNil(
                heistId.firstMatch(of: Self.contentPositionSuffixRegex),
                "buildScreen produced an `_at_X_Y` suffix: \(heistId)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Regression table

    /// Two same-matcher elements at distinct content-space origins produce
    /// Phase 2 `_1` / `_2` suffixes.
    func testTwoSameMatcherDuplicatesProducePhase2Suffixes() {
        let upper = makeButton(label: "Row", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let lower = makeButton(label: "Row", frame: CGRect(x: 0, y: 400, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [upper, lower])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2,
                       "Both elements should survive disambiguation")
        XCTAssertEqual(screen.heistIdByElement[upper], "row_button_1")
        XCTAssertEqual(screen.heistIdByElement[lower], "row_button_2")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Three same-matcher elements produce `_1` / `_2` / `_3` in traversal order.
    func testThreeSameMatcherDuplicatesProduceSequentialPhase2Suffixes() {
        let first = makeButton(label: "Item", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let second = makeButton(label: "Item", frame: CGRect(x: 0, y: 100, width: 320, height: 44))
        let third = makeButton(label: "Item", frame: CGRect(x: 0, y: 250, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [first, second, third])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 3,
                       "All three same-matcher rows should produce distinct heistIds")
        XCTAssertEqual(screen.heistIdByElement[first], "item_button_1")
        XCTAssertEqual(screen.heistIdByElement[second], "item_button_2")
        XCTAssertEqual(screen.heistIdByElement[third], "item_button_3")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Two same-matcher elements within the 0.5pt content-position epsilon
    /// are still disambiguated by Phase 2 because Phase 2 keys on label/trait,
    /// not position.
    func testSameMatcherDuplicatesWithinHalfPointEpsilonStillDisambiguatedByPhase2() {
        let first = makeButton(label: "Cell", frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        let second = makeButton(label: "Cell", frame: CGRect(x: 0, y: 0.3, width: 320, height: 44))

        let result = makeScrollableParseResult(elements: [first, second])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2,
                       "Phase 2 distinct-ifies before content-position epsilon collapse applies")
        XCTAssertEqual(screen.heistIdByElement[first], "cell_button_1")
        XCTAssertEqual(screen.heistIdByElement[second], "cell_button_2")
        assertNoContentPositionSuffix(in: screen)
    }

    /// Two different-matcher elements that synthesize to the same base id
    /// produce Phase 2 `_1` / `_2` suffixes, not `_at_X_Y`.
    func testDifferentMatcherCollisionUsesPhase2NotAtXY() {
        let firstFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        let secondFrame = CGRect(x: 0, y: 500, width: 100, height: 44)
        let first = AccessibilityElement.make(
            description: "thing",
            label: nil,
            value: "alpha",
            shape: .frame(firstFrame),
            activationPoint: CGPoint(x: firstFrame.midX, y: firstFrame.midY)
        )
        let second = AccessibilityElement.make(
            description: "thing",
            label: nil,
            value: "beta",
            shape: .frame(secondFrame),
            activationPoint: CGPoint(x: secondFrame.midX, y: secondFrame.midY)
        )

        let result = makeScrollableParseResult(elements: [first, second])
        let screen = TheBurglar.buildScreen(from: result)

        XCTAssertEqual(screen.elements.count, 2)
        XCTAssertEqual(screen.heistIdByElement[first], "thing_element_1",
                       "Different-matcher collisions resolve via Phase 2 `_N` suffixes")
        XCTAssertEqual(screen.heistIdByElement[second], "thing_element_2")
        assertNoContentPositionSuffix(in: screen)
    }
}

#endif // canImport(UIKit)

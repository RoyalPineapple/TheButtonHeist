#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheStashScrollTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
    }

    // MARK: - resolveScrollTarget (accessibility hierarchy driven)

    func testResolveScrollTargetFromScreenElementScrollView() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        scrollView.isScrollEnabled = true
        scrollView.contentSize = CGSize(width: 400, height: 2000)

        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: dummyElement(),

            object: UILabel(),
            scrollView: scrollView
        )

        let target = brains.navigation.resolveScrollTarget(screenElement: screenElement)
        if case .uiScrollView(let sv) = target {
            XCTAssertTrue(sv === scrollView)
        } else {
            XCTFail("Expected .uiScrollView, got \(String(describing: target))")
        }
    }

    func testResolveScrollTargetReturnsNilWhenNoScrollView() {
        let screenElement = TheStash.ScreenElement(
            heistId: "item",
            contentSpaceOrigin: nil,
            element: dummyElement(),

            object: UILabel(),
            scrollView: nil
        )

        let target = brains.navigation.resolveScrollTarget(screenElement: screenElement)
        XCTAssertNil(target)
    }

    // MARK: - Scroll Axis Detection

    func testScrollableAxisHorizontal() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 2000, height: 200)

        let axis = Navigation.scrollableAxis(of: .uiScrollView(scrollView))
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertFalse(axis.contains(.vertical))
    }

    func testScrollableAxisVertical() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 2000)

        let axis = Navigation.scrollableAxis(of: .uiScrollView(scrollView))
        XCTAssertFalse(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisBoth() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 2000, height: 2000)

        let axis = Navigation.scrollableAxis(of: .uiScrollView(scrollView))
        XCTAssertTrue(axis.contains(.horizontal))
        XCTAssertTrue(axis.contains(.vertical))
    }

    func testScrollableAxisEmptyWhenContentFits() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let axis = Navigation.scrollableAxis(of: .uiScrollView(scrollView))
        XCTAssertTrue(axis.isEmpty)
    }

    // MARK: - adaptDirection

    func testAdaptDirectionMatchingAxis() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.down, for: target), .down)
        XCTAssertEqual(Navigation.adaptDirection(.up, for: target), .up)
    }

    func testAdaptDirectionCrossAxis() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 200),
            contentSize: CGSize(width: 2000, height: 200)
        )
        XCTAssertEqual(Navigation.adaptDirection(.down, for: target), .right,
                       "Forward vertical → forward horizontal")
        XCTAssertEqual(Navigation.adaptDirection(.up, for: target), .left,
                       "Backward vertical → backward horizontal")
    }

    func testAdaptDirectionCrossAxisVertical() {
        let target = Navigation.ScrollableTarget.swipeable(
            frame: CGRect(x: 0, y: 0, width: 400, height: 800),
            contentSize: CGSize(width: 400, height: 2000)
        )
        XCTAssertEqual(Navigation.adaptDirection(.right, for: target), .down,
                       "Forward horizontal → forward vertical")
        XCTAssertEqual(Navigation.adaptDirection(.left, for: target), .up,
                       "Backward horizontal → backward vertical")
    }

    // MARK: - Helpers

    private func dummyElement() -> AccessibilityElement {
        AccessibilityElement(
            description: "",
            label: nil,
            value: nil,
            traits: .none,
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

#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsScrollTests {

    // MARK: - Element Scroll Target Resolution

    func testScrollWithVisibleElementReportsMissingScrollableAncestor() async throws {
        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        await installSyntheticObservation(InterfaceObservation.makeForTests(
            elements: [treeElement.heistId: treeElement],
            hierarchy: [.element(treeElement.element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): treeElement.heistId],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" with no live scrollable ancestor; "
                + "target an element inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementReportsAxisMismatch() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 200)

        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        await installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "axis_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(
            result.message,
            "scroll target failed: observed \"Item\" inside a scroll view that supports no scrolling; "
                + "expected vertical scrolling; try a matching scroll direction or target an element "
                + "inside the intended scroll region"
        )
    }

    func testScrollWithVisibleElementUsesElementScrollViewWhenAxisMatches() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.contentSize = CGSize(width: 400, height: 1200)

        let treeElement = InterfaceTree.Element(
            heistId: "item",
            scrollMembership: nil,
            element: makeElement(label: "Item")
        )
        await installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "vertical_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down))
        )

        XCTAssertTrue(result.success, "Expected element scroll to succeed: \(String(describing: result.message))")
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
    }

    // MARK: - safeSwipeFrame

    func testScrollableTargetUsesAccessibilityContainerFrameForSemanticOnlySwipeFallback() async throws {
        let captureFrame = CGRect(x: 40, y: 120, width: 240, height: 360)
        let contentSize = AccessibilitySize(width: 320, height: 2000)
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: contentSize,
            frame: AccessibilityRect(captureFrame)
        )
        let path = TreePath([0])
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: retainedLiveObject())],
            firstResponderHeistId: nil
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .swipeable(let liveContainer, let resolvedContentSize) = target else {
            XCTFail("Expected semantic-only scroll container to use swipeable accessibility geometry")
            return
        }
        XCTAssertEqual(liveContainer.frame, captureFrame)
        XCTAssertEqual(resolvedContentSize, contentSize.cgSize)
    }

    func testScrollableTargetUsesPathKeyedLiveScrollView() async throws {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let contentSize = AccessibilitySize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        let path = TreePath([0])
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [path: "main_scroll"],
            containerRefsByPath: [path: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: scrollView)]
        ))

        let target = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        guard case .uiScrollView(_, let resolvedScrollView) = target else {
            XCTFail("Expected path-keyed UIScrollView target, got \(target)")
            return
        }
        XCTAssertTrue(resolvedScrollView === scrollView)
    }

    func testPageScrollReacquiresContainerFromCurrentCapture() async throws {
        let path = TreePath([0])
        let oldScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        oldScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: oldScrollView.contentSize, frame: oldScrollView.frame)
        let contentSize = try XCTUnwrap(container.scrollableContentSize)
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
        ))
        let staleTarget = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        ))

        let transition = await brains.navigation.scrollOnePageAndSettle(
            staleTarget,
            direction: .down,
            animated: false
        )

        XCTAssertEqual(transition.outcome, .moved)
        XCTAssertEqual(oldScrollView.contentOffset, .zero)
        XCTAssertGreaterThan(replacementScrollView.contentOffset.y, 0)
    }

    func testEdgeScrollReacquiresContainerFromCurrentCapture() async throws {
        let path = TreePath([0])
        let oldScrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        oldScrollView.contentSize = CGSize(width: 320, height: 1_600)
        let container = makeScrollableContainer(contentSize: oldScrollView.contentSize, frame: oldScrollView.frame)
        let contentSize = try XCTUnwrap(container.scrollableContentSize)
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
        ))
        let staleTarget = try XCTUnwrap(brains.navigation.scrollableTarget(
            for: container,
            path: path,
            contentSize: contentSize
        ))

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        ))

        let transition = await brains.navigation.scrollToEdgeAndSettle(staleTarget, edge: .bottom)

        XCTAssertEqual(transition.outcome, .moved)
        XCTAssertEqual(oldScrollView.contentOffset, .zero)
        XCTAssertEqual(replacementScrollView.contentOffset.y, 1_200)
    }

    func testSafeSwipeFrameFullyInSafeBoundsIsUnchanged() async throws {
        // A frame sitting comfortably inside the safe area passes through
        // intersected with itself, which is the frame.
        let screen = UIScreen.main.bounds
        let inner = screen.insetBy(dx: 80, dy: 120)
        let result = try XCTUnwrap(brains.navigation.safeSwipeFrame(from: inner))
        XCTAssertEqual(result, inner)
    }

    func testSafeSwipeFrameZeroWidthReturnsNil() async {
        // Degenerate input has no targetable on-screen geometry, so command
        // execution must fail instead of swiping the stale original frame.
        let input = CGRect(x: 0, y: 0, width: 0, height: 100)
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: input))
    }

    func testSafeSwipeFrameFullyOffscreenReturnsNil() async {
        let input = CGRect(x: -500, y: -500, width: 100, height: 100)
        XCTAssertNil(brains.navigation.safeSwipeFrame(from: input))
    }

    func testSafeSwipeFrameOversizedFrameClampsWithinScreen() async throws {
        // A frame larger than any iPhone screen must clamp to the safe
        // region and stay within the current screen bounds.
        let huge = CGRect(x: -1000, y: -1000, width: 10000, height: 10000)
        let result = try XCTUnwrap(brains.navigation.safeSwipeFrame(from: huge))
        let screenBounds = UIScreen.main.bounds
        XCTAssertTrue(
            screenBounds.contains(result),
            "Result \(result) must fit within the screen \(screenBounds)"
        )
    }

    func testSafeSwipeFrameClampsAboveTabBarContainer() async throws {
        // A .tabBar container in the accessibility hierarchy defines the
        // bottom clear line. A swipe rectangle that overlaps the tab bar
        // must be clipped to end at its top edge.
        let tabBarFrame = CGRect(x: 0, y: 700, width: 400, height: 80)
        let tabBarContainer = AccessibilityContainer(type: .tabBar, frame: AccessibilityRect(tabBarFrame))
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(tabBarContainer, children: [])],
            firstResponderHeistId: nil,
        ))
        let result = try XCTUnwrap(
            brains.navigation.safeSwipeFrame(from: CGRect(x: 100, y: 400, width: 200, height: 500))
        )
        XCTAssertEqual(
            result.maxY, tabBarFrame.minY,
            "Swipe area must end at the tab bar's top edge"
        )
    }

}

#endif

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
        let element = makeElement(label: "Item")
        let treeElement = InterfaceTree.Element(
            heistId: "item",
            path: TreePath([0]),
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: .root,
                screen: TheVault.onscreenSpace(for: element)
            ),
            element: element
        )
        await installSyntheticObservation(InterfaceObservation.makeForTests(
            elements: [treeElement.heistId: treeElement],
            hierarchy: [.element(treeElement.element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): treeElement.heistId],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down)),
            deadline: semanticRevealDeadline()
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

        let element = makeElement(label: "Item")
        let treeElement = InterfaceTree.Element(
            heistId: "item",
            path: TreePath([0, 0]),
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: TreePath([0]),
                screen: TheVault.onscreenSpace(for: element)
            ),
            element: element
        )
        await installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "axis_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down)),
            deadline: semanticRevealDeadline()
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

        let element = makeElement(label: "Item")
        let treeElement = InterfaceTree.Element(
            heistId: "item",
            path: TreePath([0, 0]),
            scrollMembership: nil,
            geometry: testGeometry(
                for: element,
                ownerPath: TreePath([0]),
                screen: TheVault.onscreenSpace(for: element)
            ),
            element: element
        )
        await installLiveScrollTarget(treeElement, scrollView: scrollView, containerName: "vertical_scroll")

        let result = await brains.navigation.executeScroll(
            try resolvedScrollTarget(ScrollTarget(target: .label("Item"), direction: .down)),
            deadline: semanticRevealDeadline()
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
        await installSyntheticObservation(
            InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: retainedLiveObject())],
            firstResponderHeistId: nil
            )
        )

        let semanticContainer = try XCTUnwrap(brains.vault.interfaceTree.containers[path])
        let target = try XCTUnwrap(
            brains.navigation.scrollableTarget(for: semanticContainer)
        )

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
        let container = makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame)
        let path = TreePath([0])
        await installSyntheticObservation(
            InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [path: "main_scroll"],
            containerRefsByPath: [path: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: scrollView)]
            )
        )

        let semanticContainer = try XCTUnwrap(brains.vault.interfaceTree.containers[path])
        let target = try XCTUnwrap(
            brains.navigation.scrollableTarget(for: semanticContainer)
        )

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
        await installSyntheticObservation(
            InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
            )
        )
        let semanticContainer = try XCTUnwrap(brains.vault.interfaceTree.containers[path])
        let staleTarget = try XCTUnwrap(
            brains.navigation.scrollableTarget(for: semanticContainer)
        )

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        let replacementObservation = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        )
        await installSyntheticObservation(replacementObservation)

        let transition = await brains.navigation.performViewportTransition(
            .page(staleTarget, direction: .down, animated: false),
            deadline: semanticRevealDeadline()
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
        await installSyntheticObservation(
            InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: oldScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: oldScrollView)]
            )
        )
        let semanticContainer = try XCTUnwrap(brains.vault.interfaceTree.containers[path])
        let staleTarget = try XCTUnwrap(
            brains.navigation.scrollableTarget(for: semanticContainer)
        )

        let replacementScrollView = UIScrollView(frame: oldScrollView.frame)
        replacementScrollView.contentSize = oldScrollView.contentSize
        let replacementObservation = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerRefsByPath: [path: .init(object: replacementScrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [path: .init(view: replacementScrollView)]
        )
        await installSyntheticObservation(replacementObservation)

        let transition = await brains.navigation.performViewportTransition(
            .edge(staleTarget, edge: .bottom),
            deadline: semanticRevealDeadline()
        )

        XCTAssertEqual(transition.outcome, .moved)
        XCTAssertEqual(oldScrollView.contentOffset, .zero)
        XCTAssertEqual(replacementScrollView.contentOffset.y, 1_200)
    }

}

#endif

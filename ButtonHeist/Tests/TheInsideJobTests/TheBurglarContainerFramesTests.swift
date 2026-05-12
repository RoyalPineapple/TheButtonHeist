#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

/// Direct tests for `TheBurglar.buildContainerIdentityContext` — the parent-
/// scrollable-threading walk that converts each container's screen-space
/// frame into the nearest enclosing scrollable's content space. Container
/// stableIds depend on these frames, so a bug in the walker would silently
/// degrade identity for every nested container.
@MainActor
final class TheBurglarContainerFramesTests: XCTestCase {

    private func makeElement() -> AccessibilityElement {
        .make(respondsToUserInteraction: false)
    }

    func testTopLevelContainerKeepsScreenSpaceFrame() {
        let container = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 100, width: 320, height: 400)
        )
        let element = makeElement()
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [.element(element, traversalIndex: 0)])
        ]

        let result = TheBurglar.buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerViews: [:]
        )

        XCTAssertEqual(result.contentFrames[container], container.frame)
        XCTAssertFalse(result.nestedInScrollView.contains(container))
    }

    func testNestedContainerExpressedInParentScrollableContentSpace() {
        // A real UIWindow is needed so `convert(_:from: nil)` resolves
        // through window space rather than the no-window degenerate case.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 5000)
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        window.addSubview(scrollView)
        window.isHidden = false

        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        let inner = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 200, width: 320, height: 200)
        )
        let element = makeElement()
        let hierarchy: [AccessibilityHierarchy] = [
            .container(outer, children: [
                .container(inner, children: [.element(element, traversalIndex: 0)])
            ])
        ]

        let result = TheBurglar.buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerViews: [outer: scrollView]
        )

        XCTAssertEqual(result.contentFrames[outer], outer.frame,
                       "Top-level scrollable: no enclosing scrollable, frame stays in screen space")
        XCTAssertFalse(result.nestedInScrollView.contains(outer))

        let innerContent = try? XCTUnwrap(result.contentFrames[inner])
        XCTAssertEqual(innerContent?.origin.x ?? .nan, 0, accuracy: 0.5)
        XCTAssertEqual(innerContent?.origin.y ?? .nan, 300, accuracy: 0.5,
                       "screen-y 200 + contentOffset.y 100 = content-y 300")
        XCTAssertEqual(innerContent?.size, inner.frame.size,
                       "Size is unchanged by coordinate conversion")
        XCTAssertTrue(result.nestedInScrollView.contains(inner))
    }

    func testNestedContainerScrollIndependence() {
        // Same inner container, two different parent contentOffsets — the
        // content-frame must remain anchored to the underlying content,
        // not the viewport.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 5000)
        window.addSubview(scrollView)
        window.isHidden = false

        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: CGSize(width: 320, height: 5000)),
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )

        // Parse 1: contentOffset 0, inner is at screen-y 200 → content-y 200.
        scrollView.contentOffset = .zero
        let innerParse1 = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: 200, width: 320, height: 200)
        )
        let result1 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse1, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerViews: [outer: scrollView]
        )

        // Parse 2: scrolled down by 1000pt. The same logical inner container
        // — same data behind it — is now at screen-y -800. Content-frame
        // should still resolve to content-y 200, the same logical anchor.
        scrollView.contentOffset = CGPoint(x: 0, y: 1000)
        let innerParse2 = AccessibilityContainer(
            type: .list,
            frame: CGRect(x: 0, y: -800, width: 320, height: 200)
        )
        let result2 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse2, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerViews: [outer: scrollView]
        )

        XCTAssertEqual(result1.contentFrames[innerParse1]?.origin.y ?? .nan, 200, accuracy: 0.5)
        XCTAssertEqual(result2.contentFrames[innerParse2]?.origin.y ?? .nan, 200, accuracy: 0.5,
                       "Inner container's content-frame must be invariant under outer scroll")
        XCTAssertTrue(result1.nestedInScrollView.contains(innerParse1))
        XCTAssertTrue(result2.nestedInScrollView.contains(innerParse2))
    }
}

#endif

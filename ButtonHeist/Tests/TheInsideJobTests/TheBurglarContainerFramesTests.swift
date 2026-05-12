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

    // MARK: - heistId synthesis: pathological geometry

    /// `contentPositionHeistId` builds a wire-format heistId fragment from
    /// `(origin.x, origin.y)`. `Int(_:)` traps on non-finite or finite-but-
    /// out-of-range inputs, which would crash the parse the first time a
    /// pathological content-space origin appears. Must use `safeInt`.
    func testContentPositionHeistIdHandlesPathologicalOrigin() {
        let base = "button_save"

        let nanOrigin = TheBurglar.contentPositionHeistId(
            base, origin: CGPoint(x: 1e100, y: .nan)
        )
        XCTAssertFalse(nanOrigin.isEmpty)
        XCTAssertTrue(nanOrigin.hasPrefix("\(base)_at_"))

        // Determinism: same pathological input produces the same id.
        let nanOriginAgain = TheBurglar.contentPositionHeistId(
            base, origin: CGPoint(x: 1e100, y: .nan)
        )
        XCTAssertEqual(nanOrigin, nanOriginAgain)

        // Non-finite components clamp to 0, finite-but-huge clamp to Int.max/min.
        let infOrigin = TheBurglar.contentPositionHeistId(
            base, origin: CGPoint(x: .infinity, y: -.infinity)
        )
        XCTAssertEqual(infOrigin, "\(base)_at_0_0")

        let hugeOrigin = TheBurglar.contentPositionHeistId(
            base, origin: CGPoint(x: 1e100, y: -1e100)
        )
        XCTAssertEqual(hugeOrigin, "\(base)_at_\(Int.max)_\(Int.min)")
    }

    /// `coarseFrameHash` is a wire-format heistId fragment for container
    /// stableIds (`list_...`, `landmark_...`, `tabBar_...`, etc.). After the
    /// `sanitizedForJSON` pass, non-finite inputs become 0 but finite-but-huge
    /// values still flow through and would trap `Int(_:)`. Must use `safeInt`.
    func testCoarseFrameHashHandlesPathologicalFrame() {
        let hugeFrame = CGRect(
            x: 1e100,
            y: -1e100,
            width: CGFloat.greatestFiniteMagnitude,
            height: 1e200
        )
        let hash = TheBurglar.coarseFrameHash(hugeFrame)
        XCTAssertFalse(hash.isEmpty)
        // Bucket-divided clamped output remains deterministic across calls.
        XCTAssertEqual(hash, TheBurglar.coarseFrameHash(hugeFrame))

        let nonFiniteFrame = CGRect(
            x: .nan,
            y: .infinity,
            width: -.infinity,
            height: .signalingNaN
        )
        let nonFiniteHash = TheBurglar.coarseFrameHash(nonFiniteFrame)
        XCTAssertEqual(nonFiniteHash, "0_0_0_0",
                       "sanitizedForJSON folds non-finite to 0; safeInt(0/8) is 0")
    }

    /// Locks in the no-change-for-normal-inputs invariant for `coarseFrameHash`.
    /// `safeInt` must be the identity for any in-range finite CGFloat — otherwise
    /// switching `Int` → `safeInt` is a wire-format break.
    func testCoarseFrameHashUnchangedForOrdinaryFrame() {
        // All-integer-after-divide frame so banker's rounding can't cause drift.
        let frame = CGRect(x: 16, y: 96, width: 320, height: 40)
        // Expected: 16/8=2, 96/8=12, 320/8=40, 40/8=5
        XCTAssertEqual(TheBurglar.coarseFrameHash(frame), "2_12_40_5")
    }
}

#endif

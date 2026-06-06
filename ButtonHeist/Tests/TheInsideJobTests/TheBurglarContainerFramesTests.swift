#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import TheScore

/// Direct tests for `TheBurglar.buildContainerIdentityContext` — the
/// parent-scrollable-threading walk that keeps container identity derived from
/// hierarchy structure and accessibility size, not live scroll-view coordinate
/// conversion or moving viewport origin.
@MainActor
final class TheBurglarContainerFramesTests: XCTestCase {

    private func makeElement(label: String = "Element") -> AccessibilityElement {
        .make(label: label, respondsToUserInteraction: false)
    }

    func testTopLevelContainerKeepsScreenSpaceFrame() {
        let container = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 100, width: 320, height: 400)
        )
        let element = makeElement()
        let hierarchy: [AccessibilityHierarchy] = [
            .container(container, children: [.element(element, traversalIndex: 0)])
        ]

        let result = TheBurglar.buildContainerIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerViews: [:]
        )

        XCTAssertEqual(result.contentFrames[container], container.frame.cgRect)
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
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 5000)),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        let inner = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 200, width: 320, height: 200)
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

        XCTAssertEqual(result.contentFrames[outer], outer.frame.cgRect,
                       "Top-level scrollable: no enclosing scrollable, frame stays in screen space")
        XCTAssertFalse(result.nestedInScrollView.contains(outer))

        let innerContent = result.contentFrames[inner]
        XCTAssertNotNil(innerContent)
        XCTAssertEqual(innerContent?.origin.x ?? .nan, 0, accuracy: 0.5)
        XCTAssertEqual(innerContent?.origin.y ?? .nan, 0, accuracy: 0.5,
                       "Nested container identity drops moving viewport origin")
        XCTAssertEqual(innerContent?.size, inner.frame.size.cgSize,
                       "Size remains parser evidence; origin is capture-local hierarchy evidence")
        XCTAssertTrue(result.nestedInScrollView.contains(inner))
    }

    func testNestedContainerScrollIndependence() {
        // Same inner container, two different parent contentOffsets: semantic
        // container identity must not follow moving viewport origin.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentSize = CGSize(width: 320, height: 5000)
        window.addSubview(scrollView)
        window.isHidden = false

        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 5000)),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )

        // Parse 1: contentOffset 0, inner is at screen-y 200.
        scrollView.contentOffset = .zero
        let innerParse1 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 200, width: 320, height: 200)
        )
        let result1 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse1, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerViews: [outer: scrollView]
        )

        // Parse 2: scrolled down by 1000pt. The same logical inner container
        // — same data behind it — is now at screen-y -800. Its identity frame
        // should still drop origin and keep size.
        scrollView.contentOffset = CGPoint(x: 0, y: 1000)
        let innerParse2 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: -800, width: 320, height: 200)
        )
        let result2 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse2, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerViews: [outer: scrollView]
        )

        XCTAssertEqual(result1.contentFrames[innerParse1]?.origin.y ?? .nan, 0, accuracy: 0.5)
        XCTAssertEqual(result2.contentFrames[innerParse2]?.origin.y ?? .nan, 0, accuracy: 0.5,
                       "Inner container identity must be invariant under outer scroll")
        XCTAssertTrue(result1.nestedInScrollView.contains(innerParse1))
        XCTAssertTrue(result2.nestedInScrollView.contains(innerParse2))
    }

    /// `coarseFrameHash` is a wire-format heistId fragment for container
    /// containerNames (`list_...`, `landmark_...`, `tabBar_...`, etc.). After the
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
                       "non-finite geometry folds to 0 before coarse frame bucketing")
    }

    /// Locks in the no-change-for-normal-inputs invariant for `coarseFrameHash`.
    /// `safeInt` must be the identity for any in-range finite CGFloat — otherwise
    /// switching `Int` → `safeInt` is a wire-format break.
    func testCoarseFrameHashUnchangedForOrdinaryFrame() {
        let bucket = CoarseFrameComparison.currentBucket
        let frame = CGRect(x: bucket * 2, y: bucket * 12, width: bucket * 40, height: bucket * 5)
        XCTAssertEqual(TheBurglar.coarseFrameHash(frame), "2_12_40_5")
    }

    func testCoarseFrameComparisonUsesDeviceBuckets() {
        XCTAssertEqual(CoarseFrameComparison.bucket(for: .phone), 8)
        XCTAssertEqual(CoarseFrameComparison.bucket(for: .pad), 13)
    }

    func testDuplicateReadableContainerIdsGetCaptureLocalHashes() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let firstContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1_000)),
            frame: AccessibilityRect(frame)
        )
        let secondContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 2_000)),
            frame: AccessibilityRect(frame)
        )
        let firstElement = makeElement(label: "First")
        let secondElement = makeElement(label: "Second")
        let firstScrollView = UIScrollView(frame: frame)
        let secondScrollView = UIScrollView(frame: frame)

        let screen = TheBurglar.buildScreen(from: TheBurglar.ParseResult(
            hierarchy: [
                .container(firstContainer, children: [.element(firstElement, traversalIndex: 0)]),
                .container(secondContainer, children: [.element(secondElement, traversalIndex: 1)]),
            ],
            objects: [:],
            scrollViews: [
                firstContainer: firstScrollView,
                secondContainer: secondScrollView,
            ]
        ))
        let interface = TheStash.WireConversion.toInterface(from: screen)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)

        XCTAssertEqual(containerNames.count, 2)
        XCTAssertEqual(Set(containerNames).count, 2)
        XCTAssertTrue(containerNames.allSatisfy { $0.hasPrefix("scrollable_0_0_40_50-") })
        XCTAssertTrue(screen.liveCapture.scrollView(forContainer: containerNames[0]) === firstScrollView)
        XCTAssertTrue(screen.liveCapture.scrollView(forContainer: containerNames[1]) === secondScrollView)
    }

    func testCaptureLocalContainerHashHandlesNonFiniteParserGeometry() {
        let container = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: .nan, y: .infinity, width: -.infinity, height: 400)
        )
        let node = AccessibilityHierarchy.container(
            container,
            children: [.element(makeElement(label: "Row"), traversalIndex: 0)]
        )

        let containerName = TheBurglar.captureLocalContainerId(
            readableName: "list_0_0_0_50",
            node: node,
            path: TreePath([0])
        )

        XCTAssertTrue(containerName.hasPrefix("list_0_0_0_50-"))
        XCTAssertEqual(
            containerName,
            TheBurglar.captureLocalContainerId(
                readableName: "list_0_0_0_50",
                node: node,
                path: TreePath([0])
            )
        )
    }

    func testNestedDuplicateScrollableFrameIdsGetCaptureLocalHashes() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let pagerFrame = CGRect(x: 0, y: 0, width: 960, height: 400)
        let repeatedContentSize = AccessibilitySize(width: 320, height: 800)
        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: repeatedContentSize),
            frame: AccessibilityRect(frame)
        )
        let pager = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 960, height: 400)),
            frame: AccessibilityRect(pagerFrame)
        )
        let page = AccessibilityContainer(
            type: .scrollable(contentSize: repeatedContentSize),
            frame: AccessibilityRect(frame)
        )
        let list = AccessibilityContainer(
            type: .scrollable(contentSize: repeatedContentSize),
            frame: AccessibilityRect(frame)
        )
        let outerScrollView = UIScrollView(frame: frame)
        let pagerScrollView = UIScrollView(frame: frame)
        let pageScrollView = UIScrollView(frame: frame)
        let listScrollView = UIScrollView(frame: frame)

        let screen = TheBurglar.buildScreen(from: TheBurglar.ParseResult(
            hierarchy: [
                .container(outer, children: [
                    .container(pager, children: [
                        .container(page, children: [
                            .container(list, children: [
                                .element(makeElement(label: "Checkout"), traversalIndex: 0),
                            ]),
                        ]),
                    ]),
                ]),
            ],
            objects: [:],
            scrollViews: [
                outer: outerScrollView,
                pager: pagerScrollView,
            ],
            scrollViewsByPath: [
                TreePath([0]): outerScrollView,
                TreePath([0, 0]): pagerScrollView,
                TreePath([0, 0, 0]): pageScrollView,
                TreePath([0, 0, 0, 0]): listScrollView,
            ]
        ))
        let interface = TheStash.WireConversion.toInterface(from: screen)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)
        let repeatedFrameIds = containerNames.filter { $0.hasPrefix("scrollable_0_0_40_50-") }

        XCTAssertEqual(containerNames.count, 4)
        XCTAssertEqual(repeatedFrameIds.count, 3)
        XCTAssertEqual(Set(repeatedFrameIds).count, 3)
        XCTAssertTrue(containerNames.contains("scrollable_0_0_120_50"))
        let repeatedScrollViews = repeatedFrameIds.compactMap { screen.liveCapture.scrollView(forContainer: $0) }
        XCTAssertEqual(repeatedScrollViews.count, 3)
        XCTAssertEqual(Set(repeatedScrollViews.map(ObjectIdentifier.init)).count, 3)
    }

    func testUniqueContainerKeepsReadableIdWithoutHashSuffix() {
        let container = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
        )
        let screen = TheBurglar.buildScreen(from: TheBurglar.ParseResult(
            hierarchy: [
                .container(container, children: [.element(makeElement(), traversalIndex: 0)]),
            ],
            objects: [:],
            scrollViews: [:]
        ))

        let interface = TheStash.WireConversion.toInterface(from: screen)

        XCTAssertEqual(interface.annotations.containers.first?.containerName, "list_0_0_40_50")
    }
}

#endif

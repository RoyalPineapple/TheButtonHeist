#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
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
        )

        XCTAssertEqual(result.contentFramesByPath[TreePath([0])], container.frame.cgRect)
        XCTAssertFalse(result.nestedInScrollViewPaths.contains(TreePath([0])))
    }

    func testNestedContainerExpressedInParentScrollableContentSpace() {
        let scrollContainerPath = TreePath([0])
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
            scrollableContainerPaths: [scrollContainerPath]
        )

        XCTAssertEqual(result.contentFramesByPath[TreePath([0])], outer.frame.cgRect,
                       "Top-level scrollable: no enclosing scrollable, frame stays in screen space")
        XCTAssertFalse(result.nestedInScrollViewPaths.contains(TreePath([0])))

        let innerContent = result.contentFramesByPath[TreePath([0, 0])]
        XCTAssertNotNil(innerContent)
        XCTAssertEqual(innerContent?.origin.x ?? .nan, 0, accuracy: 0.5)
        XCTAssertEqual(innerContent?.origin.y ?? .nan, 0, accuracy: 0.5,
                       "Nested container identity drops moving viewport origin")
        XCTAssertEqual(innerContent?.size, inner.frame.size.cgSize,
                       "Size remains parser evidence; origin is capture-local hierarchy evidence")
        XCTAssertTrue(result.nestedInScrollViewPaths.contains(TreePath([0, 0])))
    }

    func testNestedContainerScrollIndependence() {
        // Same inner container, two different viewport-relative parser frames:
        // semantic container identity must not follow moving viewport origin.
        let scrollContainerPath = TreePath([0])

        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 5000)),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )

        // Parse 1: inner is at screen-y 200.
        let innerParse1 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 200, width: 320, height: 200)
        )
        let result1 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse1, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerPaths: [scrollContainerPath]
        )

        // Parse 2: the same logical inner container — same data behind it — is
        // now at screen-y -800. Its identity frame
        // should still drop origin and keep size.
        let innerParse2 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: -800, width: 320, height: 200)
        )
        let result2 = TheBurglar.buildContainerIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse2, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerPaths: [scrollContainerPath]
        )

        XCTAssertEqual(result1.contentFramesByPath[TreePath([0, 0])]?.origin.y ?? .nan, 0, accuracy: 0.5)
        XCTAssertEqual(result2.contentFramesByPath[TreePath([0, 0])]?.origin.y ?? .nan, 0, accuracy: 0.5,
                       "Inner container identity must be invariant under outer scroll")
        XCTAssertTrue(result1.nestedInScrollViewPaths.contains(TreePath([0, 0])))
        XCTAssertTrue(result2.nestedInScrollViewPaths.contains(TreePath([0, 0])))
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
            scrollViewsByPath: [
                TreePath([0]): firstScrollView,
                TreePath([1]): secondScrollView,
            ]
        ))
        let interface = TheStash.WireConversion.toInterface(from: screen)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)
        let repeatedFramePrefix = "scrollable_\(TheBurglar.coarseFrameHash(frame))-"

        XCTAssertEqual(containerNames.count, 2)
        XCTAssertEqual(Set(containerNames).count, 2)
        XCTAssertTrue(containerNames.allSatisfy { $0.rawValue.hasPrefix(repeatedFramePrefix) })
        XCTAssertTrue(screen.liveCapture.scrollView(forContainerPath: TreePath([0])) === firstScrollView)
        XCTAssertTrue(screen.liveCapture.scrollView(forContainerPath: TreePath([1])) === secondScrollView)
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

        XCTAssertTrue(containerName.rawValue.hasPrefix("list_0_0_0_50-"))
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
            scrollViewsByPath: [
                TreePath([0]): outerScrollView,
                TreePath([0, 0]): pagerScrollView,
                TreePath([0, 0, 0]): pageScrollView,
                TreePath([0, 0, 0, 0]): listScrollView,
            ]
        ))
        let interface = TheStash.WireConversion.toInterface(from: screen)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)
        let repeatedFramePrefix = "scrollable_\(TheBurglar.coarseFrameHash(frame))-"
        let pagerName = ContainerName(rawValue: "scrollable_\(TheBurglar.coarseFrameHash(pagerFrame))")
        let repeatedFrameIds = containerNames.filter { $0.rawValue.hasPrefix(repeatedFramePrefix) }

        XCTAssertEqual(containerNames.count, 4)
        XCTAssertEqual(repeatedFrameIds.count, 3)
        XCTAssertEqual(Set(repeatedFrameIds).count, 3)
        XCTAssertTrue(containerNames.contains(pagerName))
        let repeatedScrollViews = [
            TreePath([0]),
            TreePath([0, 0, 0]),
            TreePath([0, 0, 0, 0]),
        ].compactMap { screen.liveCapture.scrollView(forContainerPath: $0) }
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
        ))

        let interface = TheStash.WireConversion.toInterface(from: screen)

        XCTAssertEqual(
            interface.annotations.containers.first?.containerName,
            ContainerName(rawValue: "list_\(TheBurglar.coarseFrameHash(container.frame.cgRect))")
        )
    }
}

#endif

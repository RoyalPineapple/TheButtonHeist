#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
import TheScore

/// Direct tests for the one hierarchy identity fold. Container and element
/// context stays derived from hierarchy structure and accessibility size, not
/// live scroll-view coordinate conversion or moving viewport origin.
@MainActor
final class TheVaultIdentityContextTests: XCTestCase {

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

        let result = TheVault.buildIdentityContext(
            hierarchy: hierarchy,
        )

        XCTAssertEqual(result.contentFramesByPath[TreePath([0])]?.cgRect, container.frame.cgRect)
        XCTAssertFalse(result.nestedInScrollViewPaths.contains(TreePath([0])))
    }

    func testNestedContainerExpressedInParentScrollableContentSpace() {
        let scrollContainerPath = TreePath([0])
        let outer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 5000),
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

        let result = TheVault.buildIdentityContext(
            hierarchy: hierarchy,
            scrollableContainerPaths: [scrollContainerPath]
        )

        XCTAssertEqual(result.contentFramesByPath[TreePath([0])]?.cgRect, outer.frame.cgRect,
                       "Top-level scrollable: no enclosing scrollable, frame stays in observation space")
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
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 5000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )

        // Parse 1: inner is at observation-y 200.
        let innerParse1 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 200, width: 320, height: 200)
        )
        let result1 = TheVault.buildIdentityContext(
            hierarchy: [.container(outer, children: [
                .container(innerParse1, children: [.element(makeElement(), traversalIndex: 0)])
            ])],
            scrollableContainerPaths: [scrollContainerPath]
        )

        // Parse 2: the same logical inner container — same data behind it — is
        // now at observation-y -800. Its identity frame
        // should still drop origin and keep size.
        let innerParse2 = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: -800, width: 320, height: 200)
        )
        let result2 = TheVault.buildIdentityContext(
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

    func testOneFoldKeepsNestedScrollAndDuplicateElementContextsPathDistinct() {
        let outerPath = TreePath([0])
        let groupPath = TreePath([0, 0])
        let outerElementPath = TreePath([0, 0, 0])
        let innerPath = TreePath([0, 1])
        let innerElementPath = TreePath([0, 1, 0])
        let repeated = makeElement(label: "Repeated")
        let outer = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(width: 320, height: 2_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        let group = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 40, width: 320, height: 100)
        )
        let inner = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(width: 320, height: 800),
            frame: AccessibilityRect(x: 0, y: 200, width: 320, height: 200)
        )
        let result = TheVault.buildIdentityContext(
            hierarchy: [
                .container(outer, children: [
                    .container(group, children: [
                        .element(repeated, traversalIndex: 0),
                    ]),
                    .container(inner, children: [
                        .element(repeated, traversalIndex: 1),
                    ]),
                ]),
            ],
            scrollableContainerPaths: [outerPath, innerPath]
        )
        let elementsByPath = Dictionary(uniqueKeysWithValues: result.elements.map { ($0.path, $0) })

        XCTAssertEqual(result.containers.count, 3)
        XCTAssertEqual(result.elements.count, 2)
        XCTAssertEqual(
            result.scrollMembershipsByPath[groupPath]?.containerPath,
            outerPath
        )
        XCTAssertEqual(
            result.scrollMembershipsByPath[innerPath]?.containerPath,
            outerPath,
            "A nested scroll container is itself content of its enclosing scroll container"
        )
        XCTAssertEqual(
            elementsByPath[outerElementPath]?.scrollMembership?.containerPath,
            outerPath
        )
        XCTAssertEqual(
            elementsByPath[innerElementPath]?.scrollMembership?.containerPath,
            innerPath,
            "Element membership uses the nearest scroll container"
        )
        XCTAssertEqual(elementsByPath[outerElementPath]?.element, repeated)
        XCTAssertEqual(elementsByPath[innerElementPath]?.element, repeated)
        XCTAssertEqual(result.contentFramesByPath[groupPath]?.origin, .zero)
        XCTAssertEqual(result.contentFramesByPath[innerPath]?.origin, .zero)
    }

    /// `coarseFrameHash` is a wire-format heistId fragment for container
    /// containerNames (`list_...`, `landmark_...`, `tabBar_...`, etc.).
    func testCoarseFrameHashHandlesPathologicalFrame() {
        let hugeFrame = CGRect(
            x: 1e100,
            y: -1e100,
            width: CGFloat.greatestFiniteMagnitude,
            height: 1e200
        )
        let hash = TheVault.coarseFrameHash(hugeFrame)
        XCTAssertFalse(hash.isEmpty)
        // Bucket-divided clamped output remains deterministic across calls.
        XCTAssertEqual(hash, TheVault.coarseFrameHash(hugeFrame))

        let nonFiniteFrame = CGRect(
            x: .nan,
            y: .infinity,
            width: -.infinity,
            height: .signalingNaN
        )
        let nonFiniteHash = TheVault.coarseFrameHash(nonFiniteFrame)
        XCTAssertEqual(nonFiniteHash, "unavailable")
    }

    /// Locks in the no-change-for-normal-inputs invariant for `coarseFrameHash`.
    func testCoarseFrameHashUnchangedForOrdinaryFrame() {
        let bucket = CoarseFrameComparison.currentBucket
        let frame = CGRect(x: bucket * 2, y: bucket * 12, width: bucket * 40, height: bucket * 5)
        XCTAssertEqual(TheVault.coarseFrameHash(frame), "2_12_40_5")
    }

    func testCoarseFrameHashTreatsNegativeSizeAsUnavailable() {
        XCTAssertEqual(
            TheVault.coarseFrameHash(CGRect(x: 10, y: 20, width: -1, height: 44)),
            "unavailable"
        )
    }

    func testCoarseFrameComparisonUsesDeviceBuckets() {
        XCTAssertEqual(CoarseFrameComparison.bucket(for: .phone), 8)
        XCTAssertEqual(CoarseFrameComparison.bucket(for: .pad), 13)
    }

    func testDuplicateReadableContainerIdsGetCaptureLocalHashes() {
        let frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        let firstContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(frame)
        )
        let secondContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 2_000),
            frame: AccessibilityRect(frame)
        )
        let firstElement = makeElement(label: "First")
        let secondElement = makeElement(label: "Second")
        let firstScrollView = UIScrollView(frame: frame)
        let secondScrollView = UIScrollView(frame: frame)

        let observation = TheVault.buildObservation(from: TheVault.CaptureResult(
            hierarchy: [
                .container(firstContainer, children: [.element(firstElement, traversalIndex: 0)]),
                .container(secondContainer, children: [.element(secondElement, traversalIndex: 1)]),
            ],
            scrollViewsByPath: [
                TreePath([0]): firstScrollView,
                TreePath([1]): secondScrollView,
            ]
        ))
        let interface = TheVault.WireConversion.toSemanticInterface(from: observation.tree)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)
        let repeatedFramePrefix = "scrollable_\(TheVault.coarseFrameHash(frame))-"

        XCTAssertEqual(containerNames.count, 2)
        XCTAssertEqual(Set(containerNames).count, 2)
        XCTAssertTrue(containerNames.allSatisfy { $0.rawValue.hasPrefix(repeatedFramePrefix) })
        XCTAssertTrue(observation.liveCapture.scrollView(forContainerPath: TreePath([0])) === firstScrollView)
        XCTAssertTrue(observation.liveCapture.scrollView(forContainerPath: TreePath([1])) === secondScrollView)
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

        let containerName = TheVault.captureLocalContainerId(
            readableName: "list_0_0_0_50",
            node: node,
            path: TreePath([0])
        )

        XCTAssertTrue(containerName.rawValue.hasPrefix("list_0_0_0_50-"))
        XCTAssertEqual(
            containerName,
            TheVault.captureLocalContainerId(
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
            type: .none, scrollableContentSize: repeatedContentSize,
            frame: AccessibilityRect(frame)
        )
        let pager = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 960, height: 400),
            frame: AccessibilityRect(pagerFrame)
        )
        let page = AccessibilityContainer(
            type: .none, scrollableContentSize: repeatedContentSize,
            frame: AccessibilityRect(frame)
        )
        let list = AccessibilityContainer(
            type: .none, scrollableContentSize: repeatedContentSize,
            frame: AccessibilityRect(frame)
        )
        let outerScrollView = UIScrollView(frame: frame)
        let pagerScrollView = UIScrollView(frame: frame)
        let pageScrollView = UIScrollView(frame: frame)
        let listScrollView = UIScrollView(frame: frame)

        let observation = TheVault.buildObservation(from: TheVault.CaptureResult(
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
        let interface = TheVault.WireConversion.toSemanticInterface(from: observation.tree)
        let containerNames = interface.annotations.containers.compactMap(\.containerName)
        let repeatedFramePrefix = "scrollable_\(TheVault.coarseFrameHash(frame))-"
        let pagerName = ContainerName(stringLiteral: "scrollable_\(TheVault.coarseFrameHash(pagerFrame))")
        let repeatedFrameIds = containerNames.filter { $0.rawValue.hasPrefix(repeatedFramePrefix) }

        XCTAssertEqual(containerNames.count, 4)
        XCTAssertEqual(repeatedFrameIds.count, 3)
        XCTAssertEqual(Set(repeatedFrameIds).count, 3)
        XCTAssertTrue(containerNames.contains(pagerName))
        let repeatedScrollViews = [
            TreePath([0]),
            TreePath([0, 0, 0]),
            TreePath([0, 0, 0, 0]),
        ].compactMap { observation.liveCapture.scrollView(forContainerPath: $0) }
        XCTAssertEqual(repeatedScrollViews.count, 3)
        XCTAssertEqual(Set(repeatedScrollViews.map(ObjectIdentifier.init)).count, 3)
    }

    func testUniqueContainerKeepsReadableIdWithoutHashSuffix() {
        let container = AccessibilityContainer(
            type: .list,
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 400)
        )
        let observation = TheVault.buildObservation(from: TheVault.CaptureResult(
            hierarchy: [
                .container(container, children: [.element(makeElement(), traversalIndex: 0)]),
            ],
        ))

        let interface = TheVault.WireConversion.toSemanticInterface(from: observation.tree)

        XCTAssertEqual(
            interface.annotations.containers.first?.containerName,
            ContainerName(stringLiteral: "list_\(TheVault.coarseFrameHash(container.frame.cgRect))")
        )
    }
}

#endif

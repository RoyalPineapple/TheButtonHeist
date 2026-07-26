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

    /// The regression this naming scheme exists for: a container that moves —
    /// by a third of a point, or across a would-be bucket edge, or off the
    /// screen entirely — keeps its name. A frame-derived name could not promise
    /// that, because a name is one value with nothing to compare against.
    func testContainerNameSurvivesFrameMotion() {
        let frames = [
            CGRect(x: 0, y: 100, width: 320, height: 44),
            CGRect(x: 0, y: 100.3, width: 320, height: 44),
            CGRect(x: 0, y: 96, width: 320, height: 44),
            CGRect(x: 0, y: -800, width: 320, height: 44),
            CGRect(x: .nan, y: .infinity, width: -.infinity, height: 44),
        ]
        let names = frames.map { frame in
            TheVault.containerName(
                for: AccessibilityContainer(type: .list, frame: AccessibilityRect(frame))
            )
        }

        XCTAssertEqual(Set(names).count, 1, "Container names must not encode position or size")
        XCTAssertEqual(names.first, ContainerName(stringLiteral: "list"))
    }

    /// Values the container exposes still separate roles and identifiers, so the
    /// readable prefix stays readable without geometry.
    func testContainerNameUsesExposedValuesNotGeometry() {
        let frame = AccessibilityRect(CGRect(x: 7, y: 11, width: 320, height: 44))

        XCTAssertEqual(
            TheVault.containerName(for: AccessibilityContainer(type: .tabBar, frame: frame)),
            ContainerName(stringLiteral: "tabBar")
        )
        XCTAssertEqual(
            TheVault.containerName(
                for: AccessibilityContainer(type: .list, identifier: "orders-list", frame: frame)
            ),
            ContainerName(stringLiteral: "list_orders-list")
        )
        XCTAssertEqual(
            TheVault.containerName(
                for: AccessibilityContainer(
                    type: .none,
                    scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
                    frame: frame
                )
            ),
            ContainerName(stringLiteral: "scrollable")
        )
    }

    func testCoarseFrameComparisonUsesDeviceTolerances() {
        XCTAssertEqual(CoarseFrameComparison.tolerance(for: .phone), 8)
        XCTAssertEqual(CoarseFrameComparison.tolerance(for: .pad), 13)
    }

    /// The reason the comparison is a tolerance and not a grid: a frame parked on
    /// what would be a bucket edge — `y = 100` with an 8pt bucket — would flip
    /// buckets under noise no user could see, so grid comparison would call the
    /// stillest elements the ones that moved. Distance has no edges to sit on.
    func testFramesWithinToleranceAreInTheSamePlaceEvenAcrossABucketEdge() {
        let onEdge = CGRect(x: 0, y: 100, width: 200, height: 44)
        XCTAssertTrue(onEdge.isInSamePlace(as: onEdge.offsetBy(dx: 0, dy: 0.3), tolerance: 8))
        XCTAssertTrue(onEdge.isInSamePlace(as: onEdge.offsetBy(dx: 0, dy: -0.3), tolerance: 8))
        XCTAssertFalse(onEdge.isInSamePlace(as: onEdge.offsetBy(dx: 0, dy: 9), tolerance: 8))
    }

    /// Unreadable geometry is never in the same place as anything, including
    /// itself: a frame we could not read is not a frame we saw hold still.
    func testUnreadableFrameIsNeverInTheSamePlace() {
        let unreadable = CGRect(x: 0, y: 0, width: -1, height: 44)
        XCTAssertFalse(unreadable.isInSamePlace(as: unreadable, tolerance: 8))
    }

    func testDuplicateReadableContainerIdsGetTreePathSuffixes() {
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

        XCTAssertEqual(
            Set(containerNames),
            [ContainerName(stringLiteral: "scrollable-0"), ContainerName(stringLiteral: "scrollable-1")],
            "Colliding siblings are separated by tree position, never by frame"
        )
        XCTAssertTrue(observation.liveCapture.scrollView(forContainerPath: TreePath([0])) === firstScrollView)
        XCTAssertTrue(observation.liveCapture.scrollView(forContainerPath: TreePath([1])) === secondScrollView)
    }

    /// The disambiguation suffix reads no geometry, so parser frames it could not
    /// have read cannot reach it.
    func testCaptureLocalContainerIdIsGeometryFree() {
        XCTAssertEqual(
            TheVault.captureLocalContainerId(readableName: "list", path: TreePath([0, 3, 1])),
            ContainerName(stringLiteral: "list-0_3_1")
        )
        XCTAssertEqual(
            TheVault.captureLocalContainerId(readableName: "list", path: TreePath([0, 3, 1])),
            TheVault.captureLocalContainerId(readableName: "list", path: TreePath([0, 3, 1]))
        )
        XCTAssertNotEqual(
            TheVault.captureLocalContainerId(readableName: "list", path: TreePath([0, 3, 1])),
            TheVault.captureLocalContainerId(readableName: "list", path: TreePath([0, 3, 2]))
        )
    }

    func testNestedDuplicateScrollableIdsGetTreePathSuffixes() {
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

        XCTAssertEqual(
            Set(containerNames),
            [
                ContainerName(stringLiteral: "scrollable-0"),
                ContainerName(stringLiteral: "scrollable-0_0"),
                ContainerName(stringLiteral: "scrollable-0_0_0"),
                ContainerName(stringLiteral: "scrollable-0_0_0_0"),
            ],
            "Nested containers exposing the same values are separated by depth, not by frame width"
        )
        let repeatedScrollViews = [
            TreePath([0]),
            TreePath([0, 0, 0]),
            TreePath([0, 0, 0, 0]),
        ].compactMap { observation.liveCapture.scrollView(forContainerPath: $0) }
        XCTAssertEqual(repeatedScrollViews.count, 3)
        XCTAssertEqual(Set(repeatedScrollViews.map(ObjectIdentifier.init)).count, 3)
    }

    func testUniqueContainerKeepsReadableIdWithoutPathSuffix() {
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
            ContainerName(stringLiteral: "list")
        )
    }

    /// The regression at the level that matters: two parses of the same screen
    /// whose layout drifted a fraction of a point produce identical container
    /// names, disambiguation suffixes included.
    func testContainerNamesAreIdenticalAcrossTwoParsesOfADriftedScreen() {
        func names(originY: CGFloat) -> [ContainerName] {
            let frame = CGRect(x: 0, y: originY, width: 320, height: 400)
            let outer = AccessibilityContainer(
                type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
                frame: AccessibilityRect(frame)
            )
            let inner = AccessibilityContainer(
                type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
                frame: AccessibilityRect(frame)
            )
            let tabBar = AccessibilityContainer(
                type: .tabBar,
                frame: AccessibilityRect(CGRect(x: 0, y: originY + 400, width: 320, height: 49))
            )
            let observation = TheVault.buildObservation(from: TheVault.CaptureResult(
                hierarchy: [
                    .container(outer, children: [
                        .container(inner, children: [
                            .element(makeElement(label: "Row"), traversalIndex: 0),
                        ]),
                    ]),
                    .container(tabBar, children: [
                        .element(makeElement(label: "Home"), traversalIndex: 1),
                    ]),
                ],
                scrollViewsByPath: [
                    TreePath([0]): UIScrollView(frame: frame),
                    TreePath([0, 0]): UIScrollView(frame: frame),
                ]
            ))
            let interface = TheVault.WireConversion.toSemanticInterface(from: observation.tree)
            return interface.annotations.containers.compactMap(\.containerName).sorted()
        }

        // 100 is exactly on an 8pt bucket edge: the frame-derived scheme renamed
        // these containers under 0.3pt of drift.
        XCTAssertEqual(names(originY: 100), names(originY: 100.3))
        XCTAssertEqual(names(originY: 100), names(originY: 99.7))
        XCTAssertEqual(
            names(originY: 100),
            [
                ContainerName(stringLiteral: "scrollable-0"),
                ContainerName(stringLiteral: "scrollable-0_0"),
                ContainerName(stringLiteral: "tabBar"),
            ]
        )
    }
}

#endif

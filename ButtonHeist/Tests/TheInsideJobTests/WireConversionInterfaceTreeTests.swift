#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension WireConverterTests {
    // MARK: - Tree Conversion

    func testToWireTreePreservesParserModalBoundary() throws {
        let element = makeElement(label: "Confirm", traits: [.button])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil), identifier: nil,
            frame: .zero,
            isModalBoundary: true
        )
        let parse = TheVault.CaptureResult(
            hierarchy: [.container(container, children: [.element(element, traversalIndex: 0)])],
        )
        let screen = TheVault.buildObservation(from: parse)

        let tree = WireConversion.toSemanticInterface(from: screen.tree).tree

        guard case .container(let info, _) = tree.first else {
            return XCTFail("Expected container root")
        }
        XCTAssertTrue(info.isModalBoundary)
    }

    func testSemanticInterfaceAnnotatesTraceIdentityFromHeistIds() throws {
        let treeElement = makeScreenElement(
            heistId: "checkout_button",
            label: "Checkout",
            traits: [.button],
            respondsToUserInteraction: true
        )
        let screen = InterfaceObservation.makeForTests(
            elements: ["checkout_button": treeElement],
            hierarchy: [.element(treeElement.element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): "checkout_button"],
            firstResponderHeistId: nil
        )

        let interface = WireConversion.toSemanticInterface(from: screen.tree)
        let record = try XCTUnwrap(interface.projectedElementRecords.single)

        XCTAssertEqual(record.element.label, "Checkout")
        XCTAssertEqual(record.traceIdentity, HeistId(rawValue: "checkout_button").traceElementIdentity)
    }

    func testSemanticInterfacePreservesContainersWhenKnownElementsShareParserPath() throws {
        let containerPath = TreePath([0])
        let recycledElementPath = TreePath([0, 0])
        let containerIdentifier = "SquareCheckoutAppletCore.OrderEntryContainerViewController"
        let container = AccessibilityContainer(
            type: .none, identifier: containerIdentifier,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let first = makeElement(label: "First row", traits: [.staticText])
        let second = makeElement(label: "Second row", traits: [.staticText])
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "first_row_staticText": InterfaceTree.Element(
                        heistId: "first_row_staticText",
                        path: recycledElementPath,
                        scrollMembership: nil,
                        element: first
                    ),
                    "second_row_staticText": InterfaceTree.Element(
                        heistId: "second_row_staticText",
                        path: recycledElementPath,
                        scrollMembership: nil,
                        element: second
                    ),
                ],
                containers: [
                    containerPath: InterfaceTree.Container(
                        container: container,
                        path: containerPath,
                        containerName: "container_order_entry",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(container, children: [
                    .element(second, traversalIndex: 0),
                ])],
                containerNamesByPath: [containerPath: "container_order_entry"],
                heistIdsByPath: [recycledElementPath: "second_row_staticText"],
                elementRefs: [:],
                firstResponderHeistId: nil
            )
        )

        let interface = WireConversion.toSemanticInterface(from: screen.tree)
        let expression = AccessibilityPredicate.exists(.container(.identifier(containerIdentifier)))
        let predicate = try expression.resolve(in: .empty)
        let evidence = try XCTUnwrap(AccessibilityTraceEvidence(
            trace: AccessibilityTrace(captures: [
                AccessibilityTrace.Capture(sequence: 1, interface: interface),
            ]),
            completeness: .incomplete
        ))
        let result = predicate.evaluate(in: evidence)

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
        XCTAssertEqual(Set(interface.projectedElements.compactMap(\.label)), ["First row", "Second row"])
    }

    func testSemanticInterfaceDensifiesSparseContainerPathsBeforeValidation() throws {
        let rootPath = TreePath([0])
        let splitPath = TreePath([0, 2])
        let orderPath = TreePath([0, 2, 63])
        let libraryPath = TreePath([0, 2, 63, 83])
        let rowPath = TreePath([0, 2, 63, 83, 10])
        let orderIdentifier = "SquareCheckoutAppletCore.OrderEntryContainerViewController"
        let root = AccessibilityContainer(
            type: .none, identifier: "RGUIStatusBarContentViewController",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 1_024, height: 768))
        )
        let split = AccessibilityContainer(
            type: .none, identifier: "MarketUI.MarketSplitViewController",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 1_024, height: 768))
        )
        let order = AccessibilityContainer(
            type: .none, identifier: orderIdentifier,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 1_024, height: 768))
        )
        let library = AccessibilityContainer(
            type: .semanticGroup(label: "LibraryListScreen", value: nil),
            identifier: "LibraryListScreen",
            frame: AccessibilityRect(CGRect(x: 0, y: 96, width: 820, height: 672))
        )
        let row = makeElement(label: "Search all items", identifier: "LibraryListScreen-SearchField", traits: [.searchField])
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "library_search_searchField": InterfaceTree.Element(
                        heistId: "library_search_searchField",
                        path: rowPath,
                        scrollMembership: nil,
                        element: row
                    ),
                ],
                containers: [
                    rootPath: InterfaceTree.Container(
                        container: root,
                        path: rootPath,
                        containerName: "root",
                        contentFrame: nil
                    ),
                    splitPath: InterfaceTree.Container(
                        container: split,
                        path: splitPath,
                        containerName: "split",
                        contentFrame: nil
                    ),
                    orderPath: InterfaceTree.Container(
                        container: order,
                        path: orderPath,
                        containerName: "order_entry",
                        contentFrame: nil
                    ),
                    libraryPath: InterfaceTree.Container(
                        container: library,
                        path: libraryPath,
                        containerName: "library",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(root, children: [])],
                containerNamesByPath: [rootPath: "root"],
                elementRefs: [:],
                firstResponderHeistId: nil
            )
        )

        let interface = WireConversion.toSemanticInterface(from: screen.tree)
        let expression = AccessibilityPredicate.exists(.container(.identifier(orderIdentifier)))
        let predicate = try expression.resolve(in: .empty)
        let evidence = try XCTUnwrap(AccessibilityTraceEvidence(
            trace: AccessibilityTrace(captures: [
                AccessibilityTrace.Capture(sequence: 1, interface: interface),
            ]),
            completeness: .incomplete
        ))
        let result = predicate.evaluate(in: evidence)

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
        XCTAssertEqual(interface.annotations.containers.count, 4)
        XCTAssertEqual(interface.projectedElements.single?.label, "Search all items")
        XCTAssertEqual(interface.graph.nodesInPathOrder.count, 5)
    }

    func testInterfaceSelectionPreservesTraceIdentityAnnotations() throws {
        let first = makeScreenElement(heistId: "first_button", label: "First", traits: [.button])
        let second = makeScreenElement(heistId: "second_button", label: "Second", traits: [.button])
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "first_button": first,
                "second_button": second,
            ],
            hierarchy: [
                .element(first.element, traversalIndex: 0),
                .element(second.element, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): "first_button",
                TreePath([1]): "second_button",
            ],
            firstResponderHeistId: nil
        )
        let vault = TheVault(tripwire: TheTripwire())
        vault.installObservationForTesting(screen)
        let selected = try vault.selectInterface(InterfaceQuery(
            subtree: .predicate(ElementPredicateTemplate(label: "Second"))
        ))
        let record = try XCTUnwrap(selected.projectedElementRecords.single)

        XCTAssertEqual(record.element.label, "Second")
        XCTAssertEqual(record.traceIdentity, HeistId(rawValue: "second_button").traceElementIdentity)
    }

    func testContainerSubtreeSelectionPreservesAnnotationsAndTraceIdentity() throws {
        let first = makeScreenElement(heistId: "first_button", label: "First", traits: [.button])
        let second = makeScreenElement(heistId: "second_button", label: "Second", traits: [.button])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: nil,
            frame: .zero
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "first_button": first,
                "second_button": second,
            ],
            hierarchy: [
                .container(container, children: [
                    .element(first.element, traversalIndex: 0),
                    .element(second.element, traversalIndex: 1),
                ]),
            ],
            containerNamesByPath: [TreePath([0]): "actions"],
            heistIdsByPath: [
                TreePath([0, 0]): "first_button",
                TreePath([0, 1]): "second_button",
            ],
            firstResponderHeistId: nil
        )
        let vault = TheVault(tripwire: TheTripwire())
        vault.installObservationForTesting(screen)
        let selected = try vault.selectInterface(InterfaceQuery(
            subtree: .container(.label("Actions"))
        ))
        let records = selected.projectedElementRecords

        XCTAssertEqual(selected.projectedElements.map(\.label), ["First", "Second"])
        XCTAssertEqual(selected.annotations.containerByPath[TreePath([0])]?.containerName, "actions")
        XCTAssertEqual(selected.annotations.elementByPath[TreePath([0, 0])]?.actions, [.activate])
        XCTAssertEqual(records.map(\.traceIdentity), [
            HeistId(rawValue: "first_button").traceElementIdentity,
            HeistId(rawValue: "second_button").traceElementIdentity,
        ])
    }

    func testDiscoveryInterfaceGraftsKnownOffViewportElementsUnderScrollContainer() throws {
        let visible = makeElement(
            label: "aardvark",
            traits: [.staticText],
            frameX: 16,
            frameY: 100,
            frameWidth: 288,
            frameHeight: 44
        )
        let offViewport = makeElement(
            label: "zymurgy",
            traits: [.staticText],
            frameX: 16,
            frameY: 100,
            frameWidth: 288,
            frameHeight: 44
        )
        let container = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "aardvark_staticText": InterfaceTree.Element(
                    heistId: "aardvark_staticText",
                    path: TreePath([0, 0]),
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0),
                    element: visible
                ),
                "zymurgy_staticText": InterfaceTree.Element(
                    heistId: "zymurgy_staticText",
                    path: TreePath([0, 1]),
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 1),
                    element: offViewport
                ),
            ],
            hierarchy: [
                .container(container, children: [
                    .element(visible, traversalIndex: 0),
                ]),
            ],
            containerNamesByPath: [TreePath([0]): "words_list"],
            heistIdsByPath: [TreePath([0, 0]): "aardvark_staticText"],
            firstResponderHeistId: nil,
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.compactMap(\.testLabel), ["aardvark", "zymurgy"])
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 1])])

        let projected = interface.projectedElements
        XCTAssertEqual(projected.compactMap(\.label), ["aardvark", "zymurgy"])

        let vault = TheVault(tripwire: TheTripwire())
        vault.installObservationForTesting(screen)
        let selectedInterface = try vault.selectInterface(InterfaceQuery(
            subtree: .predicate(ElementPredicateTemplate(label: "zymurgy"))
        ))
        let selectedProjection = try XCTUnwrap(selectedInterface.projectedElements.first)
        XCTAssertEqual(selectedProjection.label, "zymurgy")
    }

    func testDiscoveryInterfaceDoesNotRegraftOffscreenElementsAlreadyInFullTreeCapture() throws {
        let visible = makeElement(label: "Visible", traits: [.staticText])
        let offscreen = AccessibilityElement.make(
            label: "Offscreen",
            traits: .staticText,
            visibility: .offscreen
        )
        let container = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [
                "visible": InterfaceTree.Element(
                    heistId: "visible",
                    path: TreePath([0, 0]),
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0),
                    element: visible
                ),
                "offscreen": InterfaceTree.Element(
                    heistId: "offscreen",
                    path: TreePath([0, 1]),
                    scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 1),
                    element: offscreen
                ),
            ],
            hierarchy: [
                .container(container, children: [
                    .element(visible, traversalIndex: 0),
                    .element(offscreen, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                TreePath([0, 0]): "visible",
                TreePath([0, 1]): "offscreen",
            ],
            firstResponderHeistId: nil
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        XCTAssertEqual(interface.projectedElements.compactMap(\.label), ["Visible", "Offscreen"])
        XCTAssertEqual(interface.projectedElements.filter { $0.label == "Offscreen" }.count, 1)
    }

    func testDiscoveryInterfaceGraftsKnownNestedScrollContainers() throws {
        let outer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let inner = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 280, height: 900)),
            frame: AccessibilityRect(CGRect(x: 20, y: 700, width: 280, height: 240))
        )
        let nestedWord = makeElement(label: "interstitial", traits: [.staticText])
        let liveScreen = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(outer, children: [])],
            containerNamesByPath: [TreePath([0]): "outer_words"],
            firstResponderHeistId: nil,
        )
        var containers = liveScreen.tree.containers
        containers[TreePath([0, 0])] = InterfaceTree.Container(
            container: inner,
            path: TreePath([0, 0]),
            containerName: "inner_words",
            contentFrame: nil,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0)
        )
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "interstitial_staticText": InterfaceTree.Element(
                        heistId: "interstitial_staticText",
                        path: TreePath([0, 0, 0]),
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0, 0]), index: 0),
                        element: nestedWord
                    ),
                ],
                containers: containers
            ),
            liveCapture: liveScreen.liveCapture
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        guard case .container(_, let outerChildren) = interface.tree.first else {
            return XCTFail("Expected outer container")
        }
        guard case .container(_, let innerChildren) = outerChildren.first else {
            return XCTFail("Expected nested discovered container")
        }
        XCTAssertEqual(innerChildren.compactMap(\.testLabel), ["interstitial"])
        XCTAssertEqual(interface.annotations.containerByPath[TreePath([0, 0])]?.containerName, "inner_words")
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 0, 0])])
    }

    func testDiscoveryInterfaceEmitsCanonicalGraftedHeistIdOnce() throws {
        let rootContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let recycledCell = makeElement(
            label: "618F3ADF",
            traits: [.staticText],
            frameX: 0,
            frameY: 724,
            frameWidth: 393,
            frameHeight: 64
        )
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "recycled_cell": InterfaceTree.Element(
                        heistId: "recycled_cell",
                        path: TreePath([0, 0]),
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0),
                        element: recycledCell
                    ),
                ],
                containers: [
                    TreePath([0]): InterfaceTree.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.compactMap(\.testLabel), ["618F3ADF"])
        XCTAssertEqual(interface.projectedElements.filter { $0.label == "618F3ADF" }.count, 1)
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 0])])
        XCTAssertNil(interface.annotations.elementByPath[TreePath([0, 1])])
    }

    func testDiscoveryInterfacePreservesDistinctDisambiguatedHeistIds() throws {
        let rootContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let firstCell = makeElement(
            label: "Repeat",
            traits: [.button],
            frameX: 0,
            frameY: 724,
            frameWidth: 393,
            frameHeight: 64
        )
        let secondCell = makeElement(
            label: "Repeat",
            traits: [.button],
            frameX: 0,
            frameY: 788,
            frameWidth: 393,
            frameHeight: 64
        )
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "repeat_button": InterfaceTree.Element(
                        heistId: "repeat_button",
                        path: TreePath([0, 0]),
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0),
                        element: firstCell
                    ),
                    "repeat_button_1": InterfaceTree.Element(
                        heistId: "repeat_button_1",
                        path: TreePath([0, 1]),
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 1),
                        element: secondCell
                    ),
                ],
                containers: [
                    TreePath([0]): InterfaceTree.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.compactMap(\.testLabel), ["Repeat", "Repeat"])
        XCTAssertEqual(interface.projectedElements.filter { $0.label == "Repeat" }.count, 2)
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 0])])
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 1])])
    }

    func testDiscoveryInterfaceEmitsDuplicateGraftedContainerNamesByPath() throws {
        let rootContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(CGSize(width: 320, height: 2_000)),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let recycledContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Saved carts", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 640, width: 320, height: 120))
        )
        let screen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [:],
                containers: [
                    TreePath([0]): InterfaceTree.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                    TreePath([0, 0]): InterfaceTree.Container(
                        container: recycledContainer,
                        path: TreePath([0, 0]),
                        containerName: "saved_carts_group",
                        contentFrame: nil,
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 0)
                    ),
                    TreePath([0, 1]): InterfaceTree.Container(
                        container: recycledContainer,
                        path: TreePath([0, 1]),
                        containerName: "saved_carts_group",
                        contentFrame: nil,
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: TreePath([0]), index: 1)
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.discoveryProjection(from: screen.tree).interface

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(
            interface.annotations.containers.filter { $0.containerName == "saved_carts_group" }.count,
            2
        )
        XCTAssertNotNil(interface.annotations.containerByPath[TreePath([0, 0])])
        XCTAssertNotNil(interface.annotations.containerByPath[TreePath([0, 1])])
    }

}

#endif

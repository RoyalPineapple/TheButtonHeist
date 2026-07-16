#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

// Test-only conveniences over the canonical fact stream.
private struct ComputedChangeFacts {
    let trace: AccessibilityTrace
    let changeFacts: [AccessibilityTrace.ChangeFact]

    var current: Interface? { trace.captures.last?.interface }

    var testEdits: ElementEdits {
        changeFacts.reduce(into: ElementEdits()) { edits, fact in
            guard case .elementsChanged(let elements) = fact else { return }
            edits = ElementEdits(
                added: edits.added + projectedElements(
                    elements.appeared,
                    capture: elements.metadata.captureEdge?.after
                ),
                removed: edits.removed + projectedElements(
                    elements.disappeared,
                    capture: elements.metadata.captureEdge?.before
                ),
                updated: edits.updated + elements.updated
            )
        }
    }

    private func projectedElements(
        _ nodes: [AccessibilityTrace.InterfaceChangeNode],
        capture reference: AccessibilityTrace.CaptureRef?
    ) -> [HeistElement] {
        guard let reference, let capture = trace.capture(ref: reference) else { return [] }
        return nodes.compactMap { node in
            capture.interface.graph.elementsInTraversalOrder
                .first { $0.path == node.path }?
                .projectedElement
        }
    }
}

private func XCTAssertNotScreenChanged(
    _ trace: ComputedChangeFacts,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(trace.changeFacts.contains { $0.kind == .screenChanged }, file: file, line: line)
}

private func XCTAssertDeltaElementCount(
    _ trace: ComputedChangeFacts,
    _ expected: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(trace.current?.projectedElements.count, expected, file: file, line: line)
}

private extension ElementEdits {
    var addedOptional: [HeistElement]? { added.isEmpty ? nil : added }
    /// Removed elements are wire `HeistElement`s (no heistId). Project their
    /// labels for assertion convenience.
    var removedOptional: [String]? { removed.isEmpty ? nil : removed.map { $0.label ?? "" } }
    var updatedOptional: [ElementUpdate]? { updated.isEmpty ? nil : updated }
}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

private extension AccessibilityHierarchy {
    var testLabel: String? {
        guard case .element(let element, _) = self else { return nil }
        return element.label
    }
}

private final class WireActivationOverrideView: UIView {
    override func accessibilityActivate() -> Bool {
        true
    }
}

@MainActor
final class WireConverterTests: XCTestCase {

    private typealias WireConversion = TheStash.WireConversion

    // MARK: - Helpers

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPoint: CGPoint? = nil,
        customContent: [AccessibilityElement.CustomContent] = [],
        customRotors: [AccessibilityElement.CustomRotor] = [],
        respondsToUserInteraction: Bool = true
    ) -> AccessibilityElement {
        let frame = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        let hasExplicitActivationPoint = activationPoint != nil
        let resolvedActivationPoint = activationPoint ?? CGPoint(x: frame.midX, y: frame.midY)
        return .make(
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: UIAccessibilityTraits.fromNames(traits.map(\.rawValue)),
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: resolvedActivationPoint,
            usesDefaultActivationPoint: !hasExplicitActivationPoint,
            customContent: customContent,
            customRotors: customRotors,
            respondsToUserInteraction: respondsToUserInteraction
        )
    }

    private func makeScreenElement(
        heistId: HeistId,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 0,
        frameHeight: Double = 0,
        activationPoint: CGPoint? = nil,
        customContent: [AccessibilityElement.CustomContent] = [],
        customRotors: [AccessibilityElement.CustomRotor] = [],
        respondsToUserInteraction: Bool = true
    ) -> InterfaceTree.Element {
        InterfaceTree.Element(
            heistId: heistId,
            scrollMembership: nil,
            element: makeElement(
                label: label, value: value, identifier: identifier, hint: hint,
                traits: traits, frameX: frameX, frameY: frameY,
                frameWidth: frameWidth, frameHeight: frameHeight,
                activationPoint: activationPoint,
                customContent: customContent,
                customRotors: customRotors,
                respondsToUserInteraction: respondsToUserInteraction
            )
        )
    }

    /// Build a test tree node from a InterfaceTree.Element leaf.
    private func wireLeaf(_ element: InterfaceTree.Element) -> TestInterfaceNode {
        .parsedElement(
            element.element,
            actions: TheStash.WireConversion.convert(element.element).actions
        )
    }

    /// Build a test tree container node with a fixed containerName.
    private func wireContainer(
        containerName: ContainerName,
        type: AccessibilityContainer.ContainerType = .list,
        frame: CGRect = .zero,
        children: [TestInterfaceNode]
    ) -> TestInterfaceNode {
        .container(
            AccessibilityContainer(
                type: type,
                frame: AccessibilityRect(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
            ),
            containerName: containerName,
            children: children
        )
    }

    private func makeInterface(
        nodes: [TestInterfaceNode],
        timestamp: Date
    ) -> Interface {
        makeTestInterface(nodes: nodes, timestamp: timestamp)
    }

    private func computeDelta(
        before: [InterfaceTree.Element],
        after: [InterfaceTree.Element],
        beforeTree: [TestInterfaceNode]? = nil,
        afterTree: [TestInterfaceNode]? = nil,
        isScreenChange: Bool
    ) -> ComputedChangeFacts {
        let resolvedAfterTree: [TestInterfaceNode]
        if let afterTree, !afterTree.isEmpty {
            resolvedAfterTree = afterTree
        } else {
            resolvedAfterTree = after.map(wireLeaf)
        }
        let beforeInterface = makeInterface(nodes: beforeTree ?? before.map(wireLeaf), timestamp: Date(timeIntervalSince1970: 0))
        let afterInterface = makeInterface(nodes: resolvedAfterTree, timestamp: Date(timeIntervalSince1970: 1))
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: beforeCapture.hash,
            transition: isScreenChange
                ? AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
                : .empty
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        return ComputedChangeFacts(
            trace: trace,
            changeFacts: trace.changeFacts
        )
    }

    // MARK: - Trait Mapping

    func testSingleTraitMapped() throws {
        let traits = AccessibilityTraits.button.heistTraits
        XCTAssertEqual(traits, [.button])
    }

    func testMultipleTraitsMapped() throws {
        let traits: AccessibilityTraits = [.button, .selected]
        let heistTraits = traits.heistTraits
        XCTAssertTrue(heistTraits.contains(.button))
        XCTAssertTrue(heistTraits.contains(.selected))
        XCTAssertEqual(heistTraits.count, 2)
    }

    func testBackButtonPrivateTraitMapped() throws {
        let traits = AccessibilityTraits(rawValue: 1 << 27).heistTraits
        XCTAssertEqual(traits, [.backButton])
    }

    func testNoTraitsReturnsEmpty() throws {
        let traits = AccessibilityTraits().heistTraits
        XCTAssertTrue(traits.isEmpty)
    }

    func testTraitMappingDeclarationOrder() throws {
        let traits: AccessibilityTraits = [.button, .selected]
        let heistTraits = traits.heistTraits
        XCTAssertEqual(heistTraits[0], .button)
        XCTAssertEqual(heistTraits[1], .selected)
    }

    // MARK: - Trait Name Sync

    func testHeistTraitAllCasesMatchParser() throws {
        let parserNames = AccessibilityTraits.knownTraitNames
        let wireNames = Set(HeistTrait.allCases.map(\.rawValue))
        XCTAssertEqual(wireNames, parserNames,
                       "HeistTrait.allCases must match parser's UIKit knownTraitNames")
    }

    /// Wire payload regression: a secure text field must emit `"secureTextField"` exactly once
    /// in its `traits` array. A duplicate row in the parser's `knownTraits` table caused
    /// `traits: ["secureTextField", "secureTextField"]` to ship to every client.
    func testSecureTextFieldEmitsSecureTraitOnce() throws {
        let traits = AccessibilityTraits.secureTextField.heistTraits
        let secureCount = traits.filter { $0 == .secureTextField }.count
        XCTAssertEqual(secureCount, 1,
                       "secureTextField must appear exactly once in wire trait list, got \(traits)")
    }

    /// Every known trait in `HeistTrait.allCases` must round-trip through `AccessibilityTraits.heistTraits`
    /// without duplication. Generalises the secure-text-field regression across the table.
    func testAllKnownTraitsRoundTripWithoutDuplicates() throws {
        for trait in HeistTrait.allCases {
            let bitmask = UIAccessibilityTraits.fromNames([trait.rawValue])
            let wire = AccessibilityTraits(bitmask).heistTraits
            XCTAssertEqual(wire.count, Set(wire).count,
                           "Trait \(trait.rawValue) produced duplicates on the wire: \(wire)")
        }
    }

    // MARK: - Unknown Trait Bits

    /// Trait bits outside the current contract do not become public trait
    /// values. The parser may observe them, but the wire model exposes only
    /// named `HeistTrait` cases.
    func testUnknownTraitBitDoesNotBecomeWireTrait() throws {
        let unknownBit: UInt64 = 1 << 42
        let traits = UIAccessibilityTraits(rawValue: unknownBit)
        let wire = AccessibilityTraits(traits).heistTraits
        XCTAssertTrue(wire.isEmpty, "Unknown trait bits must stay out of the wire contract, got: \(wire)")
    }

    /// Mixing a known trait with an unknown bit emits only the known name from
    /// the current contract.
    func testKnownPlusUnknownTraitMixEmitsKnownTraitOnly() throws {
        let mixed = UIAccessibilityTraits(rawValue: UIAccessibilityTraits.button.rawValue | (1 << 42))
        let wire = AccessibilityTraits(mixed).heistTraits
        XCTAssertEqual(wire, [.button], "Only named contract traits should appear, got: \(wire)")
    }

    /// All known bits stay in the named contract.
    func testAllKnownTraitsRoundTripThroughCurrentContract() throws {
        for trait in HeistTrait.allCases {
            let bitmask = UIAccessibilityTraits.fromNames([trait.rawValue])
            let wire = AccessibilityTraits(bitmask).heistTraits
            XCTAssertEqual(wire, [trait], "Known trait \(trait.rawValue) must round-trip, got: \(wire)")
        }
    }

    // MARK: - Action Conversion

    func testToInterfaceDoesNotInferElementActionsFromLiveObject() throws {
        let element = makeElement(
            label: "Plain action",
            respondsToUserInteraction: false
        )
        let liveObject = WireActivationOverrideView()
        let parse = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): liveObject],
        )
        let screen = TheBurglar.buildObservation(from: parse)

        let annotations = WireConversion.toInterface(from: screen.tree).annotations.elements

        XCTAssertEqual(annotations.first?.actions, [])
    }

    func testToWireIncludesActivateFromParsedInteractivity() throws {
        let element = makeScreenElement(
            heistId: "button",
            label: "Button",
            respondsToUserInteraction: true
        )

        let wire = WireConversion.convert(element.element)

        XCTAssertEqual(wire.actions, [.activate])
    }

    func testToWireIncludesTypeTextForEveryTextInputTrait() throws {
        for trait in [.textEntry, .searchField, .secureTextField, .textArea] as [HeistTrait] {
            let element = makeScreenElement(
                heistId: HeistId(rawValue: trait.rawValue),
                label: trait.rawValue,
                traits: [trait],
                respondsToUserInteraction: false
            )

            XCTAssertTrue(
                WireConversion.convert(element.element).actions.contains(.typeText),
                "Expected typeText for \(trait.rawValue)"
            )
        }
    }

    func testToWireDoesNotInferTypeTextFromUnrelatedTraits() throws {
        let element = makeScreenElement(
            heistId: "button",
            label: "Button",
            traits: [.button],
            respondsToUserInteraction: false
        )

        XCTAssertFalse(WireConversion.convert(element.element).actions.contains(.typeText))
    }

    // MARK: - Tree Conversion

    func testToWireTreePreservesParserModalBoundary() throws {
        let element = makeElement(label: "Confirm", traits: [.button])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil), identifier: nil,
            frame: .zero,
            isModalBoundary: true
        )
        let parse = TheBurglar.ParseResult(
            hierarchy: [.container(container, children: [.element(element, traversalIndex: 0)])],
        )
        let screen = TheBurglar.buildObservation(from: parse)

        let tree = WireConversion.toInterface(from: screen.tree).tree

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
        let stash = TheStash(tripwire: TheTripwire())
        stash.installScreenForTesting(screen)
        let selected = try stash.selectInterface(InterfaceQuery(
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
        let stash = TheStash(tripwire: TheTripwire())
        stash.installScreenForTesting(screen)
        let selected = try stash.selectInterface(InterfaceQuery(
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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.compactMap(\.testLabel), ["aardvark", "zymurgy"])
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 1])])

        let projected = interface.projectedElements
        XCTAssertEqual(projected.compactMap(\.label), ["aardvark", "zymurgy"])

        let stash = TheStash(tripwire: TheTripwire())
        stash.installScreenForTesting(screen)
        let selectedInterface = try stash.selectInterface(InterfaceQuery(
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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

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

        let interface = WireConversion.toDiscoveryInterface(from: screen.tree)

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

    // MARK: - Delta: Identical Snapshots

    func testIdenticalSnapshotsReturnNoChange() throws {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
        XCTAssertDeltaElementCount(delta, 1)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertNil(delta.testEdits.updatedOptional)
    }

    func testEmptySnapshotsReturnNoChange() throws {
        let empty: [InterfaceTree.Element] = []
        let delta = computeDelta(
            before: empty, after: empty, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
        XCTAssertDeltaElementCount(delta, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() throws {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.addedOptional?.count, 1)
        XCTAssertEqual(delta.testEdits.addedOptional?.first?.label, "Cancel")
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    // MARK: - Delta: Element Removed

    func testElementRemovedProducesElementsChanged() throws {
        let before = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.removedOptional, ["Cancel"])
        XCTAssertNil(delta.testEdits.addedOptional)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(change?.oldDisplayText, "50%")
        XCTAssertEqual(change?.newDisplayText, "75%")
    }

    func testTraitsChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(change?.oldDisplayText, "button")
        XCTAssertEqual(change?.newDisplayText, "button, selected")
    }

    func testHintChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(change?.oldDisplayText, "Tap to continue")
        XCTAssertEqual(change?.newDisplayText, "Tap to go back")
    }

    func testActionsChangeProducesUpdate() throws {
        // Same identity (label/identifier/non-transient traits unchanged) so the
        // elements pair; toggling interactivity flips the `.activate` action,
        // producing an `.actions` update rather than a remove+add.
        let before = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: true)]
        let after = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: false)]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertNotNil(delta.testEdits.updatedOptional)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .actions)
    }

    func testFrameChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(change?.oldDisplayText, "0,0,100,50")
        XCTAssertEqual(change?.newDisplayText, "10,20,100,50")
    }

    func testActivationPointChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 50, y: 25))]
        let after = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 75, y: 40))]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(change?.oldDisplayText, "50,25")
        XCTAssertEqual(change?.newDisplayText, "75,40")
    }

    func testMultiplePropertyChangesOnSameElement() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeScreenElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertEqual(delta.testEdits.updatedOptional?.first?.changes.count, 2)
        let properties = delta.testEdits.updatedOptional?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.hint) == true)
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() throws {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.removedOptional, ["OK"])
        XCTAssertEqual(delta.testEdits.addedOptional?.first?.label, "Done")
        XCTAssertNil(delta.testEdits.updatedOptional)
    }

    // MARK: - Delta: InterfaceObservation Change

    func testScreenChangeReturnsFull() throws {
        let before = [makeScreenElement(heistId: "button_ok")]
        let afterElement = makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header])
        let after = [afterElement]
        // The new wire shape derives newInterface from the screen's tree, not
        // the flat snapshot — so the tree must reflect after.
        let afterTree = [wireLeaf(afterElement)]

        let delta = computeDelta(
            before: before, after: after, afterTree: afterTree, isScreenChange: true
        )
        XCTAssertEqual(
            delta.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        XCTAssertEqual(delta.current?.projectedElements.count, 1)
    }

    func testTreeOnlyChangeProducesDeliveredNodeLifecycleFacts() throws {
        let element = makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])
        let beforeTree = [wireLeaf(element)]
        let afterTree = [
            wireContainer(
                containerName: "list_0",
                type: .list,
                frame: CGRect(x: 0, y: 0, width: 320, height: 100),
                children: [wireLeaf(element)]
            )
        ]

        let delta = computeDelta(
            before: [element],
            after: [element],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        guard case .elementsChanged(let fact) = delta.changeFacts.single else {
            return XCTFail("Expected delivered-node lifecycle fact")
        }
        XCTAssertTrue(fact.appeared.contains { $0.kind == .container })
    }

    func testTreeReorderDoesNotProduceExistenceOrUpdateFacts() throws {
        let first = makeScreenElement(heistId: "first", label: "First")
        let second = makeScreenElement(heistId: "second", label: "Second")
        let beforeTree = [
            wireLeaf(first),
            wireLeaf(second),
        ]
        let afterTree = [
            wireLeaf(second),
            wireLeaf(first),
        ]

        let delta = computeDelta(
            before: [first, second],
            after: [second, first],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
    }

    func testMovedIdenticalElementWithSiblingReorderReportsFrameUpdate() throws {
        // Same content (label + non-transient `.button`), only the frame and
        // activation point move. Under content-signature pairing these elements
        // pair instead of churning, so the move surfaces as a `.frame` update on
        // a single element — not a remove+add, and not suppressed by move
        // inference (which only runs on unpaired added/removed).
        let beforeElement = makeScreenElement(
            heistId: "telescope_far_light_3_32_button",
            label: "Telescope, Far Light, 3:32",
            traits: [.button],
            frameY: 100,
            activationPoint: CGPoint(x: 0, y: 122)
        )
        let afterElement = makeScreenElement(
            heistId: "telescope_far_light_3_32_button_at_0_200",
            label: "Telescope, Far Light, 3:32",
            traits: [.button],
            frameY: 200,
            activationPoint: CGPoint(x: 0, y: 222)
        )
        let other = makeScreenElement(heistId: "daybreak_morning_ritual_button", label: "Daybreak")
        let beforeTree = [
            wireLeaf(beforeElement),
            wireLeaf(other),
        ]
        let afterTree = [
            wireLeaf(other),
            wireLeaf(afterElement),
        ]

        let delta = computeDelta(
            before: [beforeElement, other],
            after: [other, afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let update = delta.testEdits.updatedOptional?.first
        XCTAssertEqual(update?.after.label, "Telescope, Far Light, 3:32")
        XCTAssertTrue(update?.changes.contains { $0.property == .frame } == true)
    }

    func testStableMatchWithStateChangeReturnsElementUpdate() throws {
        let beforeElement = makeScreenElement(
            heistId: "favorite_button",
            label: "Favorite",
            value: "0",
            traits: [.button],
            frameY: 100,
            activationPoint: CGPoint(x: 0, y: 122)
        )
        let afterElement = makeScreenElement(
            heistId: "favorite_button_at_0_200",
            label: "Favorite",
            value: "1",
            traits: [.button, .selected],
            frameY: 200,
            activationPoint: CGPoint(x: 0, y: 222)
        )
        let other = makeScreenElement(heistId: "queue_button", label: "Queue")
        let beforeTree = [
            wireLeaf(beforeElement),
            wireLeaf(other),
        ]
        let afterTree = [
            wireLeaf(other),
            wireLeaf(afterElement),
        ]

        let delta = computeDelta(
            before: [beforeElement, other],
            after: [other, afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        let update = delta.testEdits.updatedOptional?.first { $0.after.label == "Favorite" }
        XCTAssertNotNil(update)
        XCTAssertTrue(update?.changes.contains { $0.property == .value && $0.oldDisplayText == "0" && $0.newDisplayText == "1" } == true)
        XCTAssertTrue(update?.changes.contains { $0.property == .traits } == true)
    }

    func testMovedIdenticalElementReportsFrameUpdate() throws {
        // A lone element with identical content moves to a new frame/activation
        // point. Content-signature pairing keeps it paired, so the move is a
        // single `.frame` update rather than a remove+add.
        let beforeElement = makeScreenElement(
            heistId: "telescope_far_light_3_32_button",
            label: "Telescope, Far Light, 3:32",
            traits: [.button],
            frameY: 100,
            activationPoint: CGPoint(x: 0, y: 122)
        )
        let afterElement = makeScreenElement(
            heistId: "telescope_far_light_3_32_button_at_0_200",
            label: "Telescope, Far Light, 3:32",
            traits: [.button],
            frameY: 200,
            activationPoint: CGPoint(x: 0, y: 222)
        )
        let beforeTree = [wireLeaf(beforeElement)]
        let afterTree = [wireLeaf(afterElement)]

        let delta = computeDelta(
            before: [beforeElement],
            after: [afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let update = delta.testEdits.updatedOptional?.first
        XCTAssertEqual(update?.after.label, "Telescope, Far Light, 3:32")
        XCTAssertTrue(update?.changes.contains { $0.property == .frame } == true)
    }

    func testElementDeletionReturnsRemovedId() throws {
        let first = makeScreenElement(heistId: "first", label: "First")
        let second = makeScreenElement(heistId: "second", label: "Second")
        let beforeTree = [
            wireLeaf(first),
            wireLeaf(second),
        ]
        let afterTree = [wireLeaf(first)]

        let delta = computeDelta(
            before: [first, second],
            after: [first],
            beforeTree: beforeTree,
            afterTree: afterTree,
            isScreenChange: false
        )

        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.removedOptional, ["Second"])
    }

    // MARK: - Delta: Duplicate heistId Pairing

    func testDuplicateHeistIdPairedByIndex() throws {
        let before = [
            makeScreenElement(heistId: "cell_1", value: "A"),
            makeScreenElement(heistId: "cell_1", value: "B"),
        ]
        let after = [
            makeScreenElement(heistId: "cell_1", value: "X"),
            makeScreenElement(heistId: "cell_1", value: "Y"),
        ]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 2)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    func testDuplicateHeistIdExcessGoesToAddedRemoved() throws {
        let before = [
            makeScreenElement(heistId: "cell", value: "A"),
            makeScreenElement(heistId: "cell", value: "B"),
            makeScreenElement(heistId: "cell", value: "C"),
        ]
        let after = [
            makeScreenElement(heistId: "cell", value: "X"),
        ]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        XCTAssertEqual(delta.testEdits.removedOptional?.count, 2)
    }

    // MARK: - Delta: Empty Diff Coerced to noChange

    func testNoDifferencesCoercedToNoChange() throws {
        let treeElement = makeScreenElement(heistId: "btn", label: "OK", traits: [.button])

        let delta = computeDelta(
            before: [treeElement], after: [treeElement], afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
    }

    // MARK: - Custom Content Conversion

    func testCustomContentConvertedToWire() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Size", value: "2.4 MB", isImportant: false),
            .init(label: "Type", value: "PDF", isImportant: true),
        ]
        let element = makeElement(label: "Report", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 2)
        XCTAssertEqual(wire.customContent?[0].label, "Size")
        XCTAssertEqual(wire.customContent?[0].value, "2.4 MB")
        XCTAssertFalse(wire.customContent?[0].isImportant ?? true)
        XCTAssertEqual(wire.customContent?[1].label, "Type")
        XCTAssertEqual(wire.customContent?[1].value, "PDF")
        XCTAssertTrue(wire.customContent?[1].isImportant ?? false)
    }

    func testEmptyCustomContentConvertedToNil() throws {
        let element = makeElement(label: "Button", customContent: [])
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    func testEmptyLabelAndValueCustomContentFilteredOut() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Size")
    }

    func testAllEmptyCustomContentConvertedToNil() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    // MARK: - Custom Rotor Conversion

    func testCustomRotorsConvertedToWire() throws {
        let element = makeElement(
            label: "Validation Results",
            customRotors: [
                .init(name: "Errors"),
                .init(name: "Warnings"),
            ]
        )

        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.rotors, [
            HeistRotor(name: "Errors"),
            HeistRotor(name: "Warnings"),
        ])
    }

    func testEmptyCustomRotorNamesFilteredOut() throws {
        let element = makeElement(
            label: "Validation Results",
            customRotors: [
                .init(name: ""),
                .init(name: "Errors"),
            ]
        )

        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.rotors, [HeistRotor(name: "Errors")])
    }

    func testNoCustomRotorsConvertedToNil() throws {
        let element = makeElement(label: "Validation Results")
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.rotors)
    }

    func testCustomRotorChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "results", label: "Validation Results")]
        let after = [makeScreenElement(
            heistId: "results",
            label: "Validation Results",
            customRotors: [.init(name: "Errors")]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .rotors)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Errors")
    }

    // MARK: - Delta: Custom Content Changes

    func testCustomContentChangeProducesUpdate() throws {
        let before = [makeScreenElement(
            heistId: "file_report",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: false)]
        )]
        let after = [makeScreenElement(
            heistId: "file_report",
            label: "Report",
            customContent: [.init(label: "Size", value: "3.1 MB", isImportant: false)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Size: 2.4 MB")
        XCTAssertEqual(change?.newDisplayText, "Size: 3.1 MB")
    }

    func testCustomContentAddedProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "card", label: "Item")]
        let after = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Price: $9.99")
    }

    func testCustomContentRemovedProducesUpdate() throws {
        let before = [makeScreenElement(
            heistId: "card",
            label: "Item",
            customContent: [.init(label: "Price", value: "$9.99", isImportant: true)]
        )]
        let after = [makeScreenElement(heistId: "card", label: "Item")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Price: $9.99")
        XCTAssertNil(change?.newDisplayText)
    }

    func testMultipleCustomContentItemsFormattedCorrectly() throws {
        let before = [makeScreenElement(heistId: "weather", label: "Portland")]
        let after = [makeScreenElement(
            heistId: "weather",
            label: "Portland",
            customContent: [
                .init(label: "Temperature", value: "58°F", isImportant: true),
                .init(label: "Humidity", value: "82%", isImportant: false),
            ]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.newDisplayText, "Temperature: 58°F; Humidity: 82%")
    }

    // MARK: - Custom Content: Importance Preserved

    func testImportanceFlagPreservedInConversion() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Price", value: "$79.99", isImportant: true),
            .init(label: "Rating", value: "4.5", isImportant: false),
            .init(label: "Color", value: "Black", isImportant: false),
        ]
        let element = makeElement(label: "Headphones", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 3)
        XCTAssertTrue(wire.customContent?[0].isImportant ?? false)
        XCTAssertFalse(wire.customContent?[1].isImportant ?? true)
        XCTAssertFalse(wire.customContent?[2].isImportant ?? true)
    }

    // MARK: - Custom Content: Partial Label/Value

    func testLabelOnlyCustomContentPreserved() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Featured", value: "", isImportant: true),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Featured")
        XCTAssertEqual(wire.customContent?.first?.value, "")
    }

    func testValueOnlyCustomContentPreserved() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "Available", isImportant: false),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "")
        XCTAssertEqual(wire.customContent?.first?.value, "Available")
    }

    // MARK: - Custom Content: Order Preserved

    func testCustomContentOrderPreserved() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Author", value: "Jordan", isImportant: false),
            .init(label: "Type", value: "PDF", isImportant: true),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
            .init(label: "Modified", value: "March 15", isImportant: false),
        ]
        let element = makeElement(label: "Report", customContent: content)
        let wire = WireConversion.convert(element)

        XCTAssertEqual(wire.customContent?.count, 4)
        XCTAssertEqual(wire.customContent?[0].label, "Author")
        XCTAssertEqual(wire.customContent?[1].label, "Type")
        XCTAssertEqual(wire.customContent?[2].label, "Size")
        XCTAssertEqual(wire.customContent?[3].label, "Modified")
    }

    // MARK: - Custom Content: Mixed Filter

    func testMixedValidAndEmptyContentFiltersCorrectly() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Price", value: "$9.99", isImportant: true),
            .init(label: "", value: "", isImportant: true),
            .init(label: "Color", value: "Red", isImportant: false),
        ]
        let element = makeElement(label: "Product", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 2)
        XCTAssertEqual(wire.customContent?[0].label, "Price")
        XCTAssertTrue(wire.customContent?[0].isImportant ?? false)
        XCTAssertEqual(wire.customContent?[1].label, "Color")
        XCTAssertFalse(wire.customContent?[1].isImportant ?? true)
    }

    // MARK: - Delta: Custom Content Unchanged

    func testIdenticalCustomContentProducesNoChange() throws {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let elements = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: content
        )]

        let delta = computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertTrue(delta.changeFacts.isEmpty)
    }

    // MARK: - Delta: Importance Change

    func testImportanceChangeProducesUpdate() throws {
        let before = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: false)]
        )]
        let after = [makeScreenElement(
            heistId: "file",
            label: "Report",
            customContent: [.init(label: "Size", value: "2.4 MB", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
    }

    // MARK: - Delta: Custom Content with Other Changes

    func testCustomContentChangeAlongsideValueChange() throws {
        let before = [makeScreenElement(
            heistId: "product",
            label: "Headphones",
            value: "$79.99",
            customContent: [.init(label: "Stock", value: "In Stock", isImportant: true)]
        )]
        let after = [makeScreenElement(
            heistId: "product",
            label: "Headphones",
            value: "$59.99",
            customContent: [.init(label: "Stock", value: "Low Stock", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        XCTAssertFalse(delta.changeFacts.isEmpty)
        let properties = delta.testEdits.updatedOptional?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.customContent) == true)
    }

    // MARK: - Delta: Custom Content Label-Only Format

    func testDeltaFormatWithLabelOnly() throws {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "Featured", value: "", isImportant: true)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.newDisplayText, "Featured")
    }

    func testDeltaFormatWithValueOnly() throws {
        let before = [makeScreenElement(heistId: "item", label: "Item")]
        let after = [makeScreenElement(
            heistId: "item",
            label: "Item",
            customContent: [.init(label: "", value: "Available", isImportant: false)]
        )]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.newDisplayText, "Available")
    }
}

#endif

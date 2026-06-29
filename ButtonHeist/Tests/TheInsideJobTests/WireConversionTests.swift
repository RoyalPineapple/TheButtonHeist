#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

// Test-only conveniences for nil-or-array assertions.
private extension AccessibilityTrace.Delta {
    /// Edit fields for a `.elementsChanged` delta.
    /// Empty for other cases.
    var testEdits: ElementEdits {
        switch self {
        case .noChange: return ElementEdits()
        case .elementsChanged(let payload): return payload.edits
        case .screenChanged: return ElementEdits()
        }
    }
}

private func XCTAssertNotScreenChanged(
    _ delta: AccessibilityTrace.Delta,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .screenChanged = delta {
        XCTFail("Expected non-screen-change delta, got \(delta)", file: file, line: line)
    }
}

private func XCTAssertDeltaElementCount(
    _ delta: AccessibilityTrace.Delta,
    _ expected: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch delta {
    case .noChange(let payload):
        XCTAssertEqual(payload.elementCount, expected, file: file, line: line)
    case .elementsChanged(let payload):
        XCTAssertEqual(payload.elementCount, expected, file: file, line: line)
    case .screenChanged(let payload):
        XCTAssertEqual(payload.elementCount, expected, file: file, line: line)
    }
}

private extension ElementEdits {
    var addedOptional: [HeistElement]? { added.isEmpty ? nil : added }
    /// Removed elements are wire `HeistElement`s (no heistId). Project their
    /// labels for assertion convenience.
    var removedOptional: [String]? { removed.isEmpty ? nil : removed.map { $0.label ?? "" } }
    var updatedOptional: [ElementUpdate]? { updated.isEmpty ? nil : updated }
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
    ) -> Screen.ScreenElement {
        Screen.ScreenElement(
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

    /// Build a test tree node from a ScreenElement leaf.
    private func wireLeaf(_ element: Screen.ScreenElement) -> TestInterfaceNode {
        .screenElement(element)
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
        TestInterfaceFixture(nodes: nodes, timestamp: timestamp).interface
    }

    private func computeDelta(
        before: [Screen.ScreenElement],
        after: [Screen.ScreenElement],
        beforeTree: [TestInterfaceNode]? = nil,
        afterTree: [TestInterfaceNode]? = nil,
        isScreenChange: Bool
    ) -> AccessibilityTrace.Delta {
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
                ? AccessibilityTrace.Transition(screenChangeReason: "testScreenChange")
                : .empty
        )
        return AccessibilityTrace.Delta.between(beforeCapture, afterCapture)
    }

    // MARK: - Trait Mapping

    func testSingleTraitMapped() {
        let traits = AccessibilityTraits.button.heistTraits
        XCTAssertEqual(traits, [.button])
    }

    func testMultipleTraitsMapped() {
        let traits: AccessibilityTraits = [.button, .selected]
        let heistTraits = traits.heistTraits
        XCTAssertTrue(heistTraits.contains(.button))
        XCTAssertTrue(heistTraits.contains(.selected))
        XCTAssertEqual(heistTraits.count, 2)
    }

    func testBackButtonPrivateTraitMapped() {
        let traits = AccessibilityTraits(rawValue: 1 << 27).heistTraits
        XCTAssertEqual(traits, [.backButton])
    }

    func testNoTraitsReturnsEmpty() {
        let traits = AccessibilityTraits().heistTraits
        XCTAssertTrue(traits.isEmpty)
    }

    func testTraitMappingDeclarationOrder() {
        let traits: AccessibilityTraits = [.button, .selected]
        let heistTraits = traits.heistTraits
        XCTAssertEqual(heistTraits[0], .button)
        XCTAssertEqual(heistTraits[1], .selected)
    }

    // MARK: - Trait Name Sync

    func testHeistTraitAllCasesMatchParser() {
        let parserNames = AccessibilityTraits.knownTraitNames
        let wireNames = Set(HeistTrait.allCases.map(\.rawValue))
        XCTAssertEqual(wireNames, parserNames,
                       "HeistTrait.allCases must match parser's UIKit knownTraitNames")
    }

    /// Wire payload regression: a secure text field must emit `"secureTextField"` exactly once
    /// in its `traits` array. A duplicate row in the parser's `knownTraits` table caused
    /// `traits: ["secureTextField", "secureTextField"]` to ship to every client.
    func testSecureTextFieldEmitsSecureTraitOnce() {
        let traits = AccessibilityTraits.secureTextField.heistTraits
        let secureCount = traits.filter { $0 == .secureTextField }.count
        XCTAssertEqual(secureCount, 1,
                       "secureTextField must appear exactly once in wire trait list, got \(traits)")
    }

    /// Every known trait in `HeistTrait.allCases` must round-trip through `AccessibilityTraits.heistTraits`
    /// without duplication. Generalises the secure-text-field regression across the table.
    func testAllKnownTraitsRoundTripWithoutDuplicates() {
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
    func testUnknownTraitBitDoesNotBecomeWireTrait() {
        let unknownBit: UInt64 = 1 << 42
        let traits = UIAccessibilityTraits(rawValue: unknownBit)
        let wire = AccessibilityTraits(traits).heistTraits
        XCTAssertTrue(wire.isEmpty, "Unknown trait bits must stay out of the wire contract, got: \(wire)")
    }

    /// Mixing a known trait with an unknown bit emits only the known name from
    /// the current contract.
    func testKnownPlusUnknownTraitMixEmitsKnownTraitOnly() {
        let mixed = UIAccessibilityTraits(rawValue: UIAccessibilityTraits.button.rawValue | (1 << 42))
        let wire = AccessibilityTraits(mixed).heistTraits
        XCTAssertEqual(wire, [.button], "Only named contract traits should appear, got: \(wire)")
    }

    /// All known bits stay in the named contract.
    func testAllKnownTraitsRoundTripThroughCurrentContract() {
        for trait in HeistTrait.allCases {
            let bitmask = UIAccessibilityTraits.fromNames([trait.rawValue])
            let wire = AccessibilityTraits(bitmask).heistTraits
            XCTAssertEqual(wire, [trait], "Known trait \(trait.rawValue) must round-trip, got: \(wire)")
        }
    }

    // MARK: - Action Conversion

    func testToInterfaceDoesNotInferElementActionsFromLiveObject() {
        let element = makeElement(
            label: "Plain action",
            respondsToUserInteraction: false
        )
        let liveObject = WireActivationOverrideView()
        let parse = TheBurglar.ParseResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): liveObject],
        )
        let screen = TheBurglar.buildScreen(from: parse)

        let annotations = WireConversion.toInterface(from: screen).annotations.elements

        XCTAssertEqual(annotations.first?.actions, [])
    }

    func testToWireIncludesActivateFromParsedInteractivity() {
        let element = makeScreenElement(
            heistId: "button",
            label: "Button",
            respondsToUserInteraction: true
        )

        let wire = WireConversion.convert(element.element)

        XCTAssertEqual(wire.actions, [.activate])
    }

    // MARK: - Tree Conversion

    func testToWireTreePreservesParserModalBoundary() {
        let element = makeElement(label: "Confirm", traits: [.button])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Alert", value: nil, identifier: nil),
            frame: .zero,
            isModalBoundary: true
        )
        let parse = TheBurglar.ParseResult(
            hierarchy: [.container(container, children: [.element(element, traversalIndex: 0)])],
        )
        let screen = TheBurglar.buildScreen(from: parse)

        let tree = WireConversion.toInterface(from: screen).tree

        guard case .container(let info, _) = tree.first else {
            return XCTFail("Expected container root")
        }
        XCTAssertTrue(info.isModalBoundary)
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
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 320, height: 2_000))),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let screen = Screen(
            elements: [
                "aardvark_staticText": Screen.ScreenElement(
                    heistId: "aardvark_staticText",
                    scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 0),
                    element: visible
                ),
                "zymurgy_staticText": Screen.ScreenElement(
                    heistId: "zymurgy_staticText",
                    scrollMembership: Screen.ScrollMembership(containerPath: TreePath([0]), index: 1),
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

        let interface = WireConversion.toDiscoveryInterface(from: screen)

        guard case .container(_, let children) = interface.tree.first else {
            return XCTFail("Expected root scroll container")
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children.compactMap(\.testLabel), ["aardvark", "zymurgy"])
        XCTAssertNotNil(interface.annotations.elementByPath[TreePath([0, 1])])

        let projected = interface.projectedElements
        XCTAssertEqual(projected.compactMap(\.label), ["aardvark", "zymurgy"])

        let selectedInterface = try InterfaceSelector(interface: interface).select(InterfaceQuery(
            matcher: ElementPredicate(label: "zymurgy")
        ))
        let selectedProjection = try XCTUnwrap(selectedInterface.projectedElements.first)
        XCTAssertEqual(selectedProjection.label, "zymurgy")
    }

    func testDiscoveryInterfaceGraftsKnownNestedScrollContainers() throws {
        let outer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 320, height: 2_000))),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let inner = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 280, height: 900))),
            frame: AccessibilityRect(CGRect(x: 20, y: 700, width: 280, height: 240))
        )
        let nestedWord = makeElement(label: "interstitial", traits: [.staticText])
        let liveScreen = Screen(
            elements: [:],
            hierarchy: [.container(outer, children: [])],
            containerNamesByPath: [TreePath([0]): "outer_words"],
            firstResponderHeistId: nil,
        )
        var containers = liveScreen.semantic.containers
        containers[TreePath([0, 0])] = SemanticScreen.Container(
            container: inner,
            path: TreePath([0, 0]),
            containerName: "inner_words",
            contentFrame: nil,
            scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 0)
        )
        let screen = Screen(
            semantic: SemanticScreen(
                elements: [
                    "interstitial_staticText": SemanticScreen.Element(
                        heistId: "interstitial_staticText",
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0, 0]), index: 0),
                        element: nestedWord
                    ),
                ],
                containers: containers
            ),
            liveCapture: liveScreen.liveCapture
        )

        let interface = WireConversion.toDiscoveryInterface(from: screen)

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

    func testDiscoveryInterfaceEmitsDuplicateGraftedHeistIdOnce() throws {
        let rootContainer = AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 320, height: 2_000))),
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
        let screen = Screen(
            semantic: SemanticScreen(
                elements: [
                    "recycled_cell": SemanticScreen.Element(
                        heistId: "recycled_cell",
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 0),
                        element: recycledCell
                    ),
                    "stale_recycled_cell_path": SemanticScreen.Element(
                        heistId: "recycled_cell",
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 0),
                        element: recycledCell
                    ),
                ],
                containers: [
                    TreePath([0]): SemanticScreen.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.toDiscoveryInterface(from: screen)

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
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 320, height: 2_000))),
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
        let screen = Screen(
            semantic: SemanticScreen(
                elements: [
                    "repeat_button": SemanticScreen.Element(
                        heistId: "repeat_button",
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 0),
                        element: firstCell
                    ),
                    "repeat_button_1": SemanticScreen.Element(
                        heistId: "repeat_button_1",
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 1),
                        element: secondCell
                    ),
                ],
                containers: [
                    TreePath([0]): SemanticScreen.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.toDiscoveryInterface(from: screen)

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
            type: .scrollable(contentSize: AccessibilitySize(CGSize(width: 320, height: 2_000))),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let recycledContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Saved carts", value: nil, identifier: nil),
            frame: AccessibilityRect(CGRect(x: 0, y: 640, width: 320, height: 120))
        )
        let screen = Screen(
            semantic: SemanticScreen(
                elements: [:],
                containers: [
                    TreePath([0]): SemanticScreen.Container(
                        container: rootContainer,
                        path: TreePath([0]),
                        containerName: "transactions_list",
                        contentFrame: nil
                    ),
                    TreePath([0, 0]): SemanticScreen.Container(
                        container: recycledContainer,
                        path: TreePath([0, 0]),
                        containerName: "saved_carts_group",
                        contentFrame: nil,
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 0)
                    ),
                    TreePath([0, 1]): SemanticScreen.Container(
                        container: recycledContainer,
                        path: TreePath([0, 1]),
                        containerName: "saved_carts_group",
                        contentFrame: nil,
                        scrollMembership: SemanticScreen.ScrollMembership(containerPath: TreePath([0]), index: 1)
                    ),
                ]
            ),
            liveCapture: LiveCapture(
                hierarchy: [.container(rootContainer, children: [])],
                containerNamesByPath: [TreePath([0]): "transactions_list"],
                elementRefs: [:],
                firstResponderHeistId: nil,
            )
        )

        let interface = WireConversion.toDiscoveryInterface(from: screen)

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

    func testIdenticalSnapshotsReturnNoChange() {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = computeDelta(
            before: elements, after: elements, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .elementsChanged = delta { XCTFail("Expected .noChange, got .elementsChanged") }
        XCTAssertDeltaElementCount(delta, 1)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertNil(delta.testEdits.updatedOptional)
    }

    func testEmptySnapshotsReturnNoChange() {
        let empty: [TheStash.ScreenElement] = []
        let delta = computeDelta(
            before: empty, after: empty, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .elementsChanged = delta { XCTFail("Expected .noChange, got .elementsChanged") }
        XCTAssertDeltaElementCount(delta, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.addedOptional?.count, 1)
        XCTAssertEqual(delta.testEdits.addedOptional?.first?.label, "Cancel")
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    // MARK: - Delta: Element Removed

    func testElementRemovedProducesElementsChanged() {
        let before = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.removedOptional, ["Cancel"])
        XCTAssertNil(delta.testEdits.addedOptional)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(change?.oldDisplayText, "50%")
        XCTAssertEqual(change?.newDisplayText, "75%")
    }

    func testTraitsChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(change?.oldDisplayText, "button")
        XCTAssertEqual(change?.newDisplayText, "button, selected")
    }

    func testHintChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(change?.oldDisplayText, "Tap to continue")
        XCTAssertEqual(change?.newDisplayText, "Tap to go back")
    }

    func testActionsChangeProducesUpdate() {
        // Same identity (label/identifier/non-transient traits unchanged) so the
        // elements pair; toggling interactivity flips the `.activate` action,
        // producing an `.actions` update rather than a remove+add.
        let before = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: true)]
        let after = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: false)]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertNotNil(delta.testEdits.updatedOptional)
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .actions)
    }

    func testFrameChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(change?.oldDisplayText, "0,0,100,50")
        XCTAssertEqual(change?.newDisplayText, "10,20,100,50")
    }

    func testActivationPointChangeProducesUpdate() {
        let before = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 50, y: 25))]
        let after = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 75, y: 40))]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(change?.oldDisplayText, "50,25")
        XCTAssertEqual(change?.newDisplayText, "75,40")
    }

    func testMultiplePropertyChangesOnSameElement() {
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

    func testLabelChangeProducesAddAndRemove() {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = computeDelta(
            before: before, after: after, afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.removedOptional, ["OK"])
        XCTAssertEqual(delta.testEdits.addedOptional?.first?.label, "Done")
        XCTAssertNil(delta.testEdits.updatedOptional)
    }

    // MARK: - Delta: Screen Change

    func testScreenChangeReturnsFull() {
        let before = [makeScreenElement(heistId: "button_ok")]
        let afterElement = makeScreenElement(heistId: "header_settings", label: "Settings", traits: [.header])
        let after = [afterElement]
        // The new wire shape derives newInterface from the screen's tree, not
        // the flat snapshot — so the tree must reflect after.
        let afterTree = [wireLeaf(afterElement)]

        let delta = computeDelta(
            before: before, after: after, afterTree: afterTree, isScreenChange: true
        )
        guard case .screenChanged(let payload) = delta else {
            return XCTFail("Expected .screenChanged, got \(delta)")
        }
        XCTAssertEqual(payload.newInterface.projectedElements.count, 1)
        XCTAssertEqual(payload.elementCount, 1)
    }

    func testTreeOnlyChangeStaysOutOfElementDelta() {
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
        if case .elementsChanged = delta { XCTFail("Expected tree-only change to stay out of ElementEdits") }
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    func testTreeReorderStaysOutOfElementDelta() {
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
        if case .elementsChanged = delta { XCTFail("Expected tree-only reorder to stay out of ElementEdits") }
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    func testMovedIdenticalElementWithSiblingReorderReportsFrameUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let update = delta.testEdits.updatedOptional?.first
        XCTAssertEqual(update?.after.label, "Telescope, Far Light, 3:32")
        XCTAssertTrue(update?.changes.contains { $0.property == .frame } == true)
    }

    func testStableMatchWithStateChangeReturnsElementUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        let update = delta.testEdits.updatedOptional?.first { $0.after.label == "Favorite" }
        XCTAssertNotNil(update)
        XCTAssertTrue(update?.changes.contains { $0.property == .value && $0.oldDisplayText == "0" && $0.newDisplayText == "1" } == true)
        XCTAssertTrue(update?.changes.contains { $0.property == .traits } == true)
    }

    func testMovedIdenticalElementReportsFrameUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        let update = delta.testEdits.updatedOptional?.first
        XCTAssertEqual(update?.after.label, "Telescope, Far Light, 3:32")
        XCTAssertTrue(update?.changes.contains { $0.property == .frame } == true)
    }

    func testElementDeletionReturnsRemovedId() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.removedOptional, ["Second"])
    }

    // MARK: - Delta: Duplicate heistId Pairing

    func testDuplicateHeistIdPairedByIndex() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 2)
        XCTAssertNil(delta.testEdits.addedOptional)
        XCTAssertNil(delta.testEdits.removedOptional)
    }

    func testDuplicateHeistIdExcessGoesToAddedRemoved() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        XCTAssertEqual(delta.testEdits.updatedOptional?.count, 1)
        XCTAssertEqual(delta.testEdits.removedOptional?.count, 2)
    }

    // MARK: - Delta: Empty Diff Coerced to noChange

    func testNoDifferencesCoercedToNoChange() {
        let screenElement = makeScreenElement(heistId: "btn", label: "OK", traits: [.button])

        let delta = computeDelta(
            before: [screenElement], after: [screenElement], afterTree: [], isScreenChange: false
        )
        XCTAssertNotScreenChanged(delta)
        if case .elementsChanged = delta { XCTFail("Expected .noChange, got .elementsChanged") }
    }

    // MARK: - Custom Content Conversion

    func testCustomContentConvertedToWire() {
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

    func testEmptyCustomContentConvertedToNil() {
        let element = makeElement(label: "Button", customContent: [])
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    func testEmptyLabelAndValueCustomContentFilteredOut() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
            .init(label: "Size", value: "2.4 MB", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Size")
    }

    func testAllEmptyCustomContentConvertedToNil() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "", value: "", isImportant: false),
        ]
        let element = makeElement(label: "File", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.customContent)
    }

    // MARK: - Custom Rotor Conversion

    func testCustomRotorsConvertedToWire() {
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

    func testEmptyCustomRotorNamesFilteredOut() {
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

    func testNoCustomRotorsConvertedToNil() {
        let element = makeElement(label: "Validation Results")
        let wire = WireConversion.convert(element)
        XCTAssertNil(wire.rotors)
    }

    func testCustomRotorChangeProducesUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .rotors)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Errors")
    }

    // MARK: - Delta: Custom Content Changes

    func testCustomContentChangeProducesUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Size: 2.4 MB")
        XCTAssertEqual(change?.newDisplayText, "Size: 3.1 MB")
    }

    func testCustomContentAddedProducesUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertNil(change?.oldDisplayText)
        XCTAssertEqual(change?.newDisplayText, "Price: $9.99")
    }

    func testCustomContentRemovedProducesUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
        XCTAssertEqual(change?.oldDisplayText, "Price: $9.99")
        XCTAssertNil(change?.newDisplayText)
    }

    func testMultipleCustomContentItemsFormattedCorrectly() {
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

    func testImportanceFlagPreservedInConversion() {
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

    func testLabelOnlyCustomContentPreserved() {
        let content: [AccessibilityElement.CustomContent] = [
            .init(label: "Featured", value: "", isImportant: true),
        ]
        let element = makeElement(label: "Item", customContent: content)
        let wire = WireConversion.convert(element)
        XCTAssertEqual(wire.customContent?.count, 1)
        XCTAssertEqual(wire.customContent?.first?.label, "Featured")
        XCTAssertEqual(wire.customContent?.first?.value, "")
    }

    func testValueOnlyCustomContentPreserved() {
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

    func testCustomContentOrderPreserved() {
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

    func testMixedValidAndEmptyContentFiltersCorrectly() {
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

    func testIdenticalCustomContentProducesNoChange() {
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
        if case .elementsChanged = delta { XCTFail("Expected .noChange, got .elementsChanged") }
    }

    // MARK: - Delta: Importance Change

    func testImportanceChangeProducesUpdate() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let change = delta.testEdits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .customContent)
    }

    // MARK: - Delta: Custom Content with Other Changes

    func testCustomContentChangeAlongsideValueChange() {
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
        if case .noChange = delta { XCTFail("Expected .elementsChanged, got .noChange") }
        let properties = delta.testEdits.updatedOptional?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.customContent) == true)
    }

    // MARK: - Delta: Custom Content Label-Only Format

    func testDeltaFormatWithLabelOnly() {
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

    func testDeltaFormatWithValueOnly() {
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

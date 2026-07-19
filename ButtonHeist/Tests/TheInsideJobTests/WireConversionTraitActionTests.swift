#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

extension ElementEdits {
    var addedOptional: [HeistElement]? { added.isEmpty ? nil : added }
    /// Removed elements are wire `HeistElement`s (no heistId). Project their
    /// labels for assertion convenience.
    var removedOptional: [String]? { removed.isEmpty ? nil : removed.map { $0.label ?? "" } }
    var updatedOptional: [ElementUpdate]? { updated.isEmpty ? nil : updated }
}

extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

extension AccessibilityHierarchy {
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

    typealias WireConversion = TheVault.WireConversion

    // Test-only conveniences over the canonical fact stream.
    struct ComputedChangeFacts {
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

    func XCTAssertNotScreenChanged(
        _ trace: ComputedChangeFacts,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(trace.changeFacts.contains { $0.kind == .screenChanged }, file: file, line: line)
    }

    func XCTAssertDeltaElementCount(
        _ trace: ComputedChangeFacts,
        _ expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(trace.current?.projectedElements.count, expected, file: file, line: line)
    }

    // MARK: - Helpers

    func makeElement(
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

    func makeScreenElement(
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
    func wireLeaf(_ element: InterfaceTree.Element) -> TestInterfaceNode {
        .parsedElement(
            element.element,
            actions: TheVault.WireConversion.convert(element.element).actions
        )
    }

    /// Build a test tree container node with a fixed containerName.
    func wireContainer(
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

    func makeInterface(
        nodes: [TestInterfaceNode],
        timestamp: Date
    ) -> Interface {
        makeTestInterface(nodes: nodes, timestamp: timestamp)
    }

    func computeDelta(
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

    func testSemanticInterfaceDoesNotInferElementActionsFromLiveObject() throws {
        let element = makeElement(
            label: "Plain action",
            respondsToUserInteraction: false
        )
        let liveObject = WireActivationOverrideView()
        let parse = TheVault.CaptureResult(
            hierarchy: [.element(element, traversalIndex: 0)],
            objectsByPath: [TreePath([0]): liveObject],
        )
        let screen = TheVault.buildObservation(from: parse)

        let annotations = WireConversion.toSemanticInterface(from: screen.tree).annotations.elements

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

}

#endif

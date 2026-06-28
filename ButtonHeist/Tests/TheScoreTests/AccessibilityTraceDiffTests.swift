import XCTest
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

private extension AccessibilityTrace.Delta {
    var testElementEdits: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }

    var testTransient: [HeistElement] {
        switch self {
        case .noChange(let payload):
            return payload.transient
        case .elementsChanged(let payload):
            return payload.transient
        case .screenChanged(let payload):
            return payload.transient
        }
    }

    var testCaptureEdge: AccessibilityTrace.CaptureEdge? {
        switch self {
        case .noChange(let payload):
            return payload.captureEdge
        case .elementsChanged(let payload):
            return payload.captureEdge
        case .screenChanged(let payload):
            return payload.captureEdge
        }
    }

    var testInteractionDigest: AccessibilityTrace.InteractionDigest? {
        switch self {
        case .noChange(let payload):
            return payload.interactionDigest
        case .elementsChanged(let payload):
            return payload.interactionDigest
        case .screenChanged(let payload):
            return payload.interactionDigest
        }
    }
}

final class AccessibilityTraceDiffTests: XCTestCase {

    func testElementDiffIsSingleElementHierarchyDiff() {
        let before = makeElement(label: "Total", value: "$5.00", traits: [.staticText])
        let after = makeElement(label: "Total", value: "$7.00", traits: [.staticText])
        let beforeInterface = makeTestInterface(elements: [before])
        let afterInterface = makeTestInterface(elements: [after])

        XCTAssertEqual(
            ElementEdits.between(before, after),
            ElementEdits.between(beforeInterface, afterInterface)
        )
        let delta = captureDelta(before: beforeInterface, after: afterInterface)
        XCTAssertEqual(delta.testElementEdits, ElementEdits.between(before, after))
    }

    func testNodeDiffIsTreeDiff() {
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "section", children: [
                testElement(makeElement(label: "Menu", traits: [.header])),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "section", children: [
                testElement(makeElement(label: "Checkout", traits: [.header])),
            ]),
        ])

        let edits = ElementEdits.between(before, after)
        let delta = captureDelta(before: before, after: after)
        XCTAssertEqual(delta.testElementEdits, edits)
    }

    func testFunctionalElementMoveDoesNotReportRemoveInsertChurn() {
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(makeElement(label: "Pasta", traits: [.button])),
                testElement(makeElement(label: "Sauce", traits: [.button])),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(makeElement(label: "Sauce", traits: [.button])),
                testElement(makeElement(label: "Pasta", traits: [.button])),
            ]),
        ])

        let elementEdits = ElementEdits.between(before, after)

        XCTAssertTrue(elementEdits.added.isEmpty)
        XCTAssertTrue(elementEdits.removed.isEmpty)
    }

    func testTreeOnlyReorderCanRemainNoChangeButDigestPreservesStableElementSet() throws {
        let first = makeElement(label: "Pasta", traits: [.button])
        let second = makeElement(label: "Sauce", traits: [.button])
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(first),
                testElement(second),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(second),
                testElement(first),
            ]),
        ])

        let delta = captureDelta(before: before, after: after)

        guard case .noChange = delta else {
            return XCTFail("Expected noChange for tree-only reorder, got \(delta)")
        }
        let digest = try XCTUnwrap(delta.testInteractionDigest)
        XCTAssertEqual(digest.elementCountBefore, 2)
        XCTAssertEqual(digest.elementCountAfter, 2)
        XCTAssertFalse(digest.elementCountChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testFooterIdentitySwapDoesNotCollapseToNoChangeWhenElementCountMatches() throws {
        let before = makeTestInterface(elements: [
            makeElement(label: "Bagel", traits: [.button]),
            makeElement(label: "Charge $0.00", identifier: "FooterButton.Charge", traits: [.button]),
        ])
        let after = makeTestInterface(elements: [
            makeElement(label: "Bagel", traits: [.button]),
            makeElement(label: "Review sale 1 item", identifier: "FooterButton.ReviewSale", traits: [.button]),
        ])

        let delta = captureDelta(before: before, after: after)

        guard case .elementsChanged(let payload) = delta else {
            return XCTFail("Expected elementsChanged for footer identity swap, got \(delta)")
        }
        let digest = try XCTUnwrap(payload.interactionDigest)
        XCTAssertEqual(digest.elementCountBefore, 2)
        XCTAssertEqual(digest.elementCountAfter, 2)
        XCTAssertFalse(digest.elementCountChanged)
        XCTAssertTrue(digest.elementSetChanged)
        XCTAssertEqual(payload.edits.removed.map(\.label), ["Charge $0.00"])
        XCTAssertEqual(payload.edits.added.map(\.label), ["Review sale 1 item"])
    }

    func testTreeInterfaceAndCaptureDiffsShareTheSameEdits() {
        let beforeInterface = makeTestInterface(
            nodes: [
                testContainer(makeContainer(), containerName: "main", children: [
                    testElement(makeElement(label: "Menu", traits: [.header])),
                    testElement(makeElement(label: "Total", value: "$5.00", traits: [.staticText])),
                ]),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let afterInterface = makeTestInterface(
            nodes: [
                testContainer(makeContainer(), containerName: "main", children: [
                    testElement(makeElement(label: "Menu", traits: [.header])),
                    testElement(makeElement(label: "Total", value: "$7.00", traits: [.staticText])),
                ]),
            ],
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: beforeCapture.hash)

        XCTAssertEqual(
            ElementEdits.between(beforeInterface.projectedElements, afterInterface.projectedElements).updated,
            ElementEdits.between(beforeInterface, afterInterface).updated
        )
        let delta = AccessibilityTrace.Delta.between(beforeCapture, afterCapture)
        XCTAssertEqual(delta.testElementEdits, ElementEdits.between(beforeInterface, afterInterface))
    }

    func testCaptureBackedNoChangeDeltaCarriesSourceEdgeAndDerivesFromTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(), parentHash: before.hash)
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .noChange = delta else {
            return XCTFail("Expected noChange, got \(delta)")
        }
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testCaptureBackedElementsChangedDeltaCarriesSourceEdgeAndDerivesFromTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .elementsChanged = delta else {
            return XCTFail("Expected elementsChanged, got \(delta)")
        }
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testCaptureBackedScreenChangedDeltaCarriesSourceEdgeAndDerivesFromTransition() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .screenChanged(let payload) = delta else {
            return XCTFail("Expected screenChanged, got \(delta)")
        }
        XCTAssertEqual(payload.newInterface, after.interface)
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testTransitionTransientLivesOnCaptureEdgeAndProjectsToCompactDeltaField() throws {
        let transient = makeElement(label: "Loading", traits: [.staticText])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(transient: [transient])
        )

        let delta = AccessibilityTrace.Delta.between(before, after)

        XCTAssertEqual(after.transition.transient, [transient])
        XCTAssertEqual(delta.testTransient, [transient])
        XCTAssertEqual(delta.testCaptureEdge?.before.hash, before.hash)
        XCTAssertEqual(delta.testCaptureEdge?.after.hash, after.hash)
    }

    func testCaptureContextOnlyDiffsAsElementsChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(keyboardVisible: true)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(keyboardVisible: false)
        )

        guard case .elementsChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertEqual(payload.elementCount, interface.projectedElements.count)
        XCTAssertTrue(payload.edits.isEmpty)
    }

    func testCaptureScreenContextDiffsAsScreenChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(screenId: "menu")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "checkout")
        )

        guard case .screenChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected screenChanged for screen id context change")
        }
        XCTAssertEqual(payload.newInterface, interface)
    }

    func testInteractionDigestReportsScreenAndFirstResponderChanges() throws {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicate(label: "Email")),
                screenId: "login"
            )
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicate(label: "Password")),
                screenId: "signup"
            )
        )

        let delta = AccessibilityTrace.Delta.between(before, after)
        let digest = try XCTUnwrap(delta.testInteractionDigest)

        XCTAssertTrue(digest.screenIdChanged)
        XCTAssertEqual(digest.screenIdBefore, "login")
        XCTAssertEqual(digest.screenIdAfter, "signup")
        XCTAssertTrue(digest.firstResponderChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testCaptureChainMetadataDoesNotAffectDiff() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface, parentHash: nil)
        let after = AccessibilityTrace.Capture(sequence: 99, interface: interface, parentHash: "sha256:parent")

        XCTAssertEqual(
            AccessibilityTrace.Delta.between(before, after),
            .noChange(AccessibilityTrace.NoChange(
                elementCount: interface.projectedElements.count,
                captureEdge: AccessibilityTrace.CaptureEdge(before: before, after: after),
                interactionDigest: AccessibilityTrace.InteractionDigest(between: before, and: after)
            ))
        )
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() {
        let before = makeElement(label: "Item", traits: [.staticText])
        let after = makeElement(label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    func testDiffPairingKeyUsesTypedIdentityTraitSet() {
        let orderedTraits = makeElement(label: "Favorite", traits: [.button, .header])
        let reorderedTraits = makeElement(label: "Favorite", traits: [.header, .button])
        let transientStateTrait = makeElement(label: "Favorite", traits: [.selected, .header, .button])
        let differentIdentityTrait = makeElement(label: "Favorite", traits: [.selected, .staticText])
        let identified = makeElement(label: "Favorite", identifier: "favorite.button", traits: [.button])

        XCTAssertEqual(orderedTraits.diffPairingKey, reorderedTraits.diffPairingKey)
        XCTAssertEqual(orderedTraits.diffPairingKey, transientStateTrait.diffPairingKey)
        XCTAssertEqual(orderedTraits.diffPairingKey.identityTraits, Set<HeistTrait>([.button, .header]))
        XCTAssertNotEqual(orderedTraits.diffPairingKey, differentIdentityTrait.diffPairingKey)
        XCTAssertEqual(identified.diffPairingKey.text, "favorite.button")
    }

    func testTypedDiffEqualityUsesDomainValues() throws {
        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Favorite", traits: [.button, .selected]),
            new: makeElement(label: "Favorite", traits: [.selected, .button])
        ))

        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Document", traits: [.staticText], customContent: nil),
            new: makeElement(label: "Document", traits: [.staticText], customContent: [])
        ))

        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Document", traits: [.staticText], rotors: nil),
            new: makeElement(label: "Document", traits: [.staticText], rotors: [])
        ))
    }

    func testTypedDiffRendersTraitsActionsRotorsAndCustomContent() throws {
        let traits = try XCTUnwrap(singleChange(
            property: .traits,
            old: makeElement(label: "Favorite", traits: [.button]),
            new: makeElement(label: "Favorite", traits: [.button, .selected])
        ))
        XCTAssertEqual(traits.oldValue, .traits([.button]))
        XCTAssertEqual(traits.newValue, .traits([.button, .selected]))
        XCTAssertEqual(traits.oldDisplayText, "button")
        XCTAssertEqual(traits.newDisplayText, "button, selected")

        let actions = try XCTUnwrap(singleChange(
            property: .actions,
            old: makeElement(label: "Row", traits: [.button], actions: [.activate]),
            new: makeElement(label: "Row", traits: [.button], actions: [.activate, .custom("Share")])
        ))
        XCTAssertEqual(actions.oldValue, .actions([.activate]))
        XCTAssertEqual(actions.newValue, .actions([.activate, .custom("Share")]))
        XCTAssertEqual(actions.oldDisplayText, "activate")
        XCTAssertEqual(actions.newDisplayText, "activate, Share")

        let rotors = try XCTUnwrap(singleChange(
            property: .rotors,
            old: makeElement(label: "Editor", traits: [.textArea], rotors: [HeistRotor(name: "Headings")]),
            new: makeElement(
                label: "Editor",
                traits: [.textArea],
                rotors: [HeistRotor(name: "Headings"), HeistRotor(name: "Errors")]
            )
        ))
        XCTAssertEqual(rotors.oldValue, .rotors([HeistRotor(name: "Headings")]))
        XCTAssertEqual(rotors.newValue, .rotors([HeistRotor(name: "Headings"), HeistRotor(name: "Errors")]))
        XCTAssertEqual(rotors.oldDisplayText, "Headings")
        XCTAssertEqual(rotors.newDisplayText, "Headings, Errors")

        let customContent = try XCTUnwrap(singleChange(
            property: .customContent,
            old: makeElement(
                label: "File",
                traits: [.staticText],
                customContent: [HeistCustomContent(label: "Size", value: "2.4 MB", isImportant: false)]
            ),
            new: makeElement(
                label: "File",
                traits: [.staticText],
                customContent: [
                    HeistCustomContent(label: "Size", value: "3.1 MB", isImportant: false),
                    HeistCustomContent(label: "State", value: "Featured", isImportant: true),
                ]
            )
        ))
        XCTAssertEqual(customContent.oldDisplayText, "Size: 2.4 MB")
        XCTAssertEqual(customContent.newDisplayText, "Size: 3.1 MB; State: Featured")
    }

    func testTypedDiffRendersFrameAndActivationPoint() throws {
        let frame = try XCTUnwrap(singleChange(
            property: .frame,
            old: makeElement(label: "Box", traits: [.staticText], frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50),
            new: makeElement(label: "Box", traits: [.staticText], frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)
        ))
        XCTAssertEqual(frame.oldValue, .frame(ElementPropertyFrame(x: 0, y: 0, width: 100, height: 50)))
        XCTAssertEqual(frame.newValue, .frame(ElementPropertyFrame(x: 10, y: 20, width: 100, height: 50)))
        XCTAssertEqual(frame.oldDisplayText, "0,0,100,50")
        XCTAssertEqual(frame.newDisplayText, "10,20,100,50")

        let activationPoint = try XCTUnwrap(singleChange(
            property: .activationPoint,
            old: makeElement(
                label: "Button",
                traits: [.button],
                activationPointX: 50,
                activationPointY: 25
            ),
            new: makeElement(
                label: "Button",
                traits: [.button],
                activationPointX: 75,
                activationPointY: 40
            )
        ))
        XCTAssertEqual(activationPoint.oldValue, .activationPoint(ElementPropertyPoint(x: 50, y: 25)))
        XCTAssertEqual(activationPoint.newValue, .activationPoint(ElementPropertyPoint(x: 75, y: 40)))
        XCTAssertEqual(activationPoint.oldDisplayText, "50,25")
        XCTAssertEqual(activationPoint.newDisplayText, "75,40")
    }

    private func makeInterface() -> Interface {
        makeInterface(label: "Menu")
    }

    private func makeInterface(label: String) -> Interface {
        makeTestInterface(elements: [
            makeElement(label: label, traits: [.header]),
            makeElement(label: "Total", value: "$5.00", traits: [.staticText]),
        ])
    }

    private func makeContainer() -> AccessibilityContainer {
        makeTestAccessibilityContainer()
    }

    private func makeElement(
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointX: Double? = nil,
        activationPointY: Double? = nil,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

    private func singleChange(
        property: ElementProperty,
        old: HeistElement,
        new: HeistElement
    ) -> PropertyChange? {
        projectElementStateChange(old: old, new: new)?
            .changes
            .first { $0.property == property }
    }

    private func assertDeltaDerivesFromCaptureEdge(
        _ delta: AccessibilityTrace.Delta,
        trace: AccessibilityTrace,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let edge = try XCTUnwrap(delta.testCaptureEdge, "Delta did not carry capture edge", file: file, line: line)
        let before = try XCTUnwrap(trace.capture(ref: edge.before), "Trace did not contain before ref", file: file, line: line)
        let after = try XCTUnwrap(trace.capture(ref: edge.after), "Trace did not contain after ref", file: file, line: line)

        XCTAssertEqual(edge.before.hash, before.hash, file: file, line: line)
        XCTAssertEqual(edge.after.hash, after.hash, file: file, line: line)
        XCTAssertEqual(delta, AccessibilityTrace.Delta.between(before, after), file: file, line: line)
    }

    private func captureDelta(
        before beforeInterface: Interface,
        after afterInterface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AccessibilityTrace.Delta {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash
        )
        let delta = AccessibilityTrace.Delta.between(before, after)
        XCTAssertNotNil(delta.testCaptureEdge, file: file, line: line)
        return delta
    }

}

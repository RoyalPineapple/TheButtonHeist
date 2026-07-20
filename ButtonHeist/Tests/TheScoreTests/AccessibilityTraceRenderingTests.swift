import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

final class AccessibilityTraceRenderingTests: AccessibilityTraceDiffTestCase {
    func testCaptureChainMetadataDoesNotAffectDiff() throws {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface, parentHash: nil)
        let after = AccessibilityTrace.Capture(sequence: 99, interface: interface, parentHash: "sha256:parent")

        XCTAssertTrue(AccessibilityTrace.ChangeFact.between(before, after).isEmpty)
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() throws {
        let before = makeElement(label: "Item", traits: [.staticText])
        let after = makeElement(label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    func testDiffPairingKeyUsesTypedIdentityTraitSet() throws {
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
            old: makeElement(label: "Row", traits: [.button], actions: [.activate, .custom("Share")]),
            new: makeElement(label: "Row", traits: [.button], actions: [.custom("Share"), .activate, .activate])
        ))
        XCTAssertEqual(
            ElementPropertyValue.actions([.custom("Share"), .activate]),
            ElementPropertyValue.actions([.activate, .custom("Share"), .activate])
        )

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
            old: makeElement(
                label: "Box",
                traits: [.staticText],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 50
            ),
            new: makeElement(
                label: "Box",
                traits: [.staticText],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 50
            )
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
                activationPointEvidence: .explicit(ScreenPoint(x: 50, y: 25))
            ),
            new: makeElement(
                label: "Button",
                traits: [.button],
                activationPointEvidence: .explicit(ScreenPoint(x: 75, y: 40))
            )
        ))
        XCTAssertEqual(activationPoint.oldValue, .activationPoint(ElementPropertyPoint(x: 50, y: 25)))
        XCTAssertEqual(activationPoint.newValue, .activationPoint(ElementPropertyPoint(x: 75, y: 40)))
        XCTAssertEqual(activationPoint.oldDisplayText, "50,25")
        XCTAssertEqual(activationPoint.newDisplayText, "75,40")
    }
}

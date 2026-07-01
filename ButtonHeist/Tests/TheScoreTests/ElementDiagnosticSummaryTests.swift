import XCTest
import ThePlans
@testable import TheScore

final class ElementDiagnosticSummaryTests: XCTestCase {
    func testActionCapabilityProfilePreservesElementDiagnosticShape() {
        let summary = ElementDiagnosticSummary(
            label: "Checkout",
            identifier: "checkout_button",
            value: "Ready",
            traits: [.button],
            actions: [.activate, .custom("Delete")],
            liveObjectState: "deallocated"
        )

        XCTAssertEqual(
            summary.rendered(using: .actionCapability(includeLiveState: true)),
            #"element label="Checkout" identifier="checkout_button" value="Ready" traits=[button] actions=[activate, Delete] liveObject=deallocated"#
        )
    }

    func testTargetCandidateProfilePreservesAvailabilityShape() {
        let summary = ElementDiagnosticSummary(
            label: "Save",
            identifier: "save1",
            value: "draft",
            availability: .offscreen(isReachable: false)
        )

        XCTAssertEqual(
            summary.rendered(using: .targetCandidate),
            #""Save" id=save1 value=draft (offscreen, unreachable)"#
        )
    }

    func testActivationAffordanceEvidenceProfilePreservesWarningShape() {
        let summary = ElementDiagnosticSummary(
            label: "Checkout",
            identifier: "checkout_button",
            traits: [.staticText],
            actions: [.activate]
        )

        XCTAssertEqual(
            summary.rendered(using: .activationAffordanceEvidence),
            #"label="Checkout" identifier="checkout_button" traits=[staticText] actions=[activate]"#
        )
    }

    func testContainerCandidateProfilePreservesResolutionShape() {
        let summary = ElementDiagnosticSummary(
            label: "Actions",
            identifier: "primary",
            value: "Main"
        )

        XCTAssertEqual(
            summary.rendered(using: .containerCandidate(type: "semanticGroup", isModalBoundary: true)),
            #"type=semanticGroup identifier="primary" label="Actions" value="Main" modal=true"#
        )
    }

    func testCompactStashProfilePreservesKnownElementShape() {
        let summary = ElementDiagnosticSummary(
            label: "Save",
            identifier: "save1",
            value: "draft",
            traits: [.button, .selected],
            availability: .visible
        )

        XCTAssertEqual(
            summary.rendered(using: .compactStash),
            #"label="Save" id="save1" value="draft" [button,selected] (visible)"#
        )
    }

    func testFailureInterfaceProfilePreservesDumpShape() {
        let element = HeistElement(
            description: "Title",
            label: "Title",
            value: "Ready",
            identifier: "title",
            hint: "Tap to open",
            traits: [.staticText],
            frameX: 1,
            frameY: 2,
            frameWidth: 100,
            frameHeight: 44,
            activationPointX: 51,
            activationPointY: 24,
            rotors: [HeistRotor(name: "Errors")],
            actions: [.activate]
        )

        let summary = ElementDiagnosticSummary(element: element)

        XCTAssertEqual(
            summary.rendered(using: .failureInterface(displayIndex: 0, includeGeometry: true)),
            #"[0] "Title":"Ready" staticText {activate} [Errors] hint="Tap to open" id="title" frame=(1,2,100,44) activation=(51,24)"#
        )
    }
}

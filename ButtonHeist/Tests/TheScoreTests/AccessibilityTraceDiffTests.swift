import XCTest
@testable import TheScore

final class AccessibilityTraceDiffTests: XCTestCase {

    func testElementDiffIsSingleElementHierarchyDiff() {
        let before = makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])
        let after = makeElement(heistId: "total", label: "Total", value: "$7.00", traits: [.staticText])

        XCTAssertEqual(
            ElementEdits.between(before, after),
            ElementEdits.between([InterfaceNode.element(before)], [InterfaceNode.element(after)])
        )
        XCTAssertEqual(
            AccessibilityTrace.Delta.between(before, after),
            AccessibilityTrace.Delta.between([InterfaceNode.element(before)], [InterfaceNode.element(after)])
        )
    }

    func testNodeDiffIsTreeDiff() {
        let before = InterfaceNode.container(makeContainer(stableId: "section"), children: [
            .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
        ])
        let after = InterfaceNode.container(makeContainer(stableId: "section"), children: [
            .element(makeElement(heistId: "title", label: "Checkout", traits: [.header])),
        ])

        XCTAssertEqual(ElementEdits.between(before, after), ElementEdits.between([before], [after]))
        XCTAssertEqual(AccessibilityTrace.Delta.between(before, after), AccessibilityTrace.Delta.between([before], [after]))
    }

    func testTreeInterfaceAndCaptureDiffsShareTheSameEdits() {
        let beforeTree: [InterfaceNode] = [
            .container(makeContainer(stableId: "main"), children: [
                .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
                .element(makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])),
            ]),
        ]
        let afterTree: [InterfaceNode] = [
            .container(makeContainer(stableId: "main"), children: [
                .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
                .element(makeElement(heistId: "total", label: "Total", value: "$7.00", traits: [.staticText])),
            ]),
        ]
        let beforeInterface = Interface(timestamp: Date(timeIntervalSince1970: 1), tree: beforeTree)
        let afterInterface = Interface(timestamp: Date(timeIntervalSince1970: 2), tree: afterTree)
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: beforeCapture.hash)

        XCTAssertEqual(ElementEdits.between(beforeTree, afterTree), ElementEdits.between(beforeInterface, afterInterface))
        XCTAssertEqual(
            AccessibilityTrace.Delta.between(beforeTree, afterTree),
            AccessibilityTrace.Delta.between(beforeInterface, afterInterface)
        )
        XCTAssertEqual(
            AccessibilityTrace.Delta.between(beforeInterface, afterInterface),
            AccessibilityTrace.Delta.between(beforeCapture, afterCapture)
        )
    }

    func testCaptureContextOnlyDiffsAsElementsChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: "search", keyboardVisible: true)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(focusedElementId: "total", keyboardVisible: false)
        )

        guard case .elementsChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertEqual(payload.elementCount, interface.elements.count)
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

    func testCaptureChainMetadataDoesNotAffectDiff() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface, parentHash: nil)
        let after = AccessibilityTrace.Capture(sequence: 99, interface: interface, parentHash: "sha256:parent")

        XCTAssertEqual(
            AccessibilityTrace.Delta.between(before, after),
            .noChange(AccessibilityTrace.NoChange(elementCount: interface.elements.count))
        )
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() {
        let before = makeElement(heistId: "first", label: "Item", traits: [.staticText])
        let after = makeElement(heistId: "second", label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    private func makeInterface() -> Interface {
        Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [
            .element(makeElement(heistId: "search", label: "Search", traits: [.searchField])),
            .element(makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])),
        ])
    }

    private func makeContainer(stableId: String) -> ContainerInfo {
        ContainerInfo(
            type: .semanticGroup(label: nil, value: nil, identifier: nil),
            stableId: stableId,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 100
        )
    }

    private func makeElement(
        heistId: String,
        label: String,
        value: String? = nil,
        traits: [HeistTrait]
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: value,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }
}

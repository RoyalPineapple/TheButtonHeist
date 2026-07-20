import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

final class AccessibilityTraceElementDiffTests: AccessibilityTraceDiffTestCase {
    func testElementDiffIsSingleElementHierarchyDiff() throws {
        let before = makeElement(label: "Total", value: "$5.00", traits: [.staticText])
        let after = makeElement(label: "Total", value: "$7.00", traits: [.staticText])
        let beforeInterface = makeTestInterface(elements: [before])
        let afterInterface = makeTestInterface(elements: [after])

        XCTAssertEqual(
            ElementEdits.between(before, after),
            ElementEdits.between(beforeInterface, afterInterface)
        )
        let facts = captureFacts(before: beforeInterface, after: afterInterface)
        XCTAssertEqual(facts.testElementEdits, ElementEdits.between(before, after))
    }

    func testNodeDiffIsTreeDiff() throws {
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

        let facts = captureFacts(before: before, after: after)
        guard let fact = facts.single, case .elementsChanged(let elements) = fact else {
            return XCTFail("Expected one elementsChanged fact")
        }
        XCTAssertEqual(elements.disappeared.compactMap(\.elementLabel), ["Menu"])
        XCTAssertEqual(elements.appeared.compactMap(\.elementLabel), ["Checkout"])
    }

    func testFunctionalElementMoveDoesNotReportRemoveInsertChurn() throws {
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

        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(facts.isEmpty)
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: before)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: after)
        let digest = AccessibilityTrace.InteractionDigest(between: beforeCapture, and: afterCapture)
        XCTAssertEqual(digest.nodeCountBefore, 3)
        XCTAssertEqual(digest.nodeCountAfter, 3)
        XCTAssertFalse(digest.nodeCountChanged)
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

        let facts = captureFacts(before: before, after: after)

        let digest = try XCTUnwrap(facts.testInteractionDigest)
        XCTAssertEqual(digest.nodeCountBefore, 2)
        XCTAssertEqual(digest.nodeCountAfter, 2)
        XCTAssertFalse(digest.nodeCountChanged)
        XCTAssertTrue(digest.elementSetChanged)
        XCTAssertEqual(facts.testDisappearedLabels, ["Charge $0.00"])
        XCTAssertEqual(facts.testAppearedLabels, ["Review sale 1 item"])
    }

    func testTraceIdentityPairsElementAcrossLabelAndIdentifierChanges() throws {
        let beforeElement = makeElement(
            label: "Charge $0.00",
            value: "ready",
            identifier: "FooterButton.Charge",
            traits: [.button]
        )
        let afterElement = makeElement(
            label: "Review sale 1 item",
            value: "done",
            identifier: "FooterButton.ReviewSale",
            traits: [.button]
        )
        let before = makeTraceIdentityInterface([
            (element: makeElement(label: "Bagel", traits: [.button]), identity: "bagel"),
            (element: beforeElement, identity: "footer-action"),
        ])
        let after = makeTraceIdentityInterface([
            (element: makeElement(label: "Bagel", traits: [.button]), identity: "bagel"),
            (element: afterElement, identity: "footer-action"),
        ])

        let edits = ElementEdits.between(before, after)
        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(edits.added.isEmpty)
        XCTAssertTrue(edits.removed.isEmpty)
        let update = try XCTUnwrap(edits.updated.single)
        XCTAssertEqual(update.before.label, "Charge $0.00")
        XCTAssertEqual(update.after.label, "Review sale 1 item")
        XCTAssertEqual(update.changes.map(\.property), [.label, .identifier, .value])
        XCTAssertEqual(facts.testElementEdits, edits)
        XCTAssertFalse(try XCTUnwrap(facts.testInteractionDigest).elementSetChanged)
    }

    func testTraceIdentityReportsLabelOnlyChangeAsElementUpdate() throws {
        let beforeElement = makeElement(label: "Total", traits: [.staticText])
        let afterElement = makeElement(label: "Total $12.00", traits: [.staticText])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "total-label"),
        ])
        let after = makeTraceIdentityInterface([
            (element: afterElement, identity: "total-label"),
        ])

        let edits = ElementEdits.between(before, after)
        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(edits.added.isEmpty)
        XCTAssertTrue(edits.removed.isEmpty)
        let update = try XCTUnwrap(edits.updated.single)
        XCTAssertEqual(update.changes.map(\.property), [.label])
        XCTAssertEqual(update.changes.first?.oldValue, .text("Total"))
        XCTAssertEqual(update.changes.first?.newValue, .text("Total $12.00"))
        XCTAssertEqual(facts.map(\.kind), [.elementsChanged])
    }

    func testDifferentTraceIdentitiesDoNotFallBackToContentPairing() throws {
        let beforeElement = makeElement(label: "Continue", value: "ready", traits: [.button])
        let afterElement = makeElement(label: "Continue", value: "done", traits: [.button])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "before-action"),
        ])
        let after = makeTraceIdentityInterface([
            (element: afterElement, identity: "after-action"),
        ])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.updated.isEmpty)
        XCTAssertEqual(edits.removed, [beforeElement])
        XCTAssertEqual(edits.added, [afterElement])
    }

    func testTraceIdentityPresenceMismatchDoesNotPair() throws {
        let beforeElement = makeElement(label: "Continue", value: "ready", traits: [.button])
        let afterElement = makeElement(label: "Continue", value: "done", traits: [.button])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "action"),
        ])
        let after = makeTestInterface(elements: [afterElement])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.updated.isEmpty)
        XCTAssertEqual(edits.removed, [beforeElement])
        XCTAssertEqual(edits.added, [afterElement])
    }

    func testTraceIdentityDoesNotEncodeInPublicInterfaceJSON() throws {
        let interface = makeTraceIdentityInterface([
            (element: makeElement(label: "Continue", traits: [.button]), identity: "private-action-id"),
        ])

        let data = try JSONEncoder().encode(interface)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(Interface.self, from: data)

        XCTAssertFalse(json.contains("traceIdentity"))
        XCTAssertFalse(json.contains("private-action-id"))
        XCTAssertEqual(decoded, interface)
        XCTAssertNil(decoded.projectedElementRecords.single?.traceIdentity)
    }
}

#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension WireConverterTests {
    // MARK: - Delta: Identical Snapshots

    func testIdenticalSnapshotsReturnNoChange() throws {
        let elements = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let delta = compareInterfaces(
            before: elements, after: elements, afterTree: []
        )
        XCTAssertTrue(delta.edits.isEmpty)
        XCTAssertEqual(delta.after.projectedElements.count, 1)
        XCTAssertNil(delta.edits.addedOptional)
        XCTAssertNil(delta.edits.removedOptional)
        XCTAssertNil(delta.edits.updatedOptional)
    }

    func testEmptySnapshotsReturnNoChange() throws {
        let empty: [InterfaceTree.Element] = []
        let delta = compareInterfaces(
            before: empty, after: empty, afterTree: []
        )
        XCTAssertTrue(delta.edits.isEmpty)
        XCTAssertEqual(delta.after.projectedElements.count, 0)
    }

    // MARK: - Delta: Element Added

    func testElementAddedProducesElementsChanged() throws {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let added = makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button])
        let after = before + [added]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.addedOptional?.count, 1)
        XCTAssertEqual(delta.edits.addedOptional?.first?.label, "Cancel")
        XCTAssertNil(delta.edits.removedOptional)
    }

    // MARK: - Delta: Element Removed

    func testElementRemovedProducesElementsChanged() throws {
        let before = [
            makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button]),
            makeScreenElement(heistId: "button_cancel", label: "Cancel", traits: [.button]),
        ]
        let after = [before[0]]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.removedOptional, ["Cancel"])
        XCTAssertNil(delta.edits.addedOptional)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.updatedOptional?.count, 1)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(change?.oldDisplayText, "50%")
        XCTAssertEqual(change?.newDisplayText, "75%")
    }

    func testTraitsChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(change?.oldDisplayText, "button")
        XCTAssertEqual(change?.newDisplayText, "button, selected")
    }

    func testHintChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(change?.oldDisplayText, "Tap to continue")
        XCTAssertEqual(change?.newDisplayText, "Tap to go back")
    }

    func testActionsChangeProducesUpdate() throws {
        // Same identity (label/identifier/identity traits unchanged) so the
        // elements pair; toggling interactivity flips the `.activate` action,
        // producing an `.actions` update rather than a remove+add.
        let before = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: true)]
        let after = [makeScreenElement(heistId: "slider", label: "Row", respondsToUserInteraction: false)]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertNotNil(delta.edits.updatedOptional)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .actions)
    }

    func testFrameChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(change?.oldDisplayText, "0,0,100,50")
        XCTAssertEqual(change?.newDisplayText, "10,20,100,50")
    }

    func testActivationPointChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 50, y: 25))]
        let after = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 75, y: 40))]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let change = delta.edits.updatedOptional?.first?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(change?.oldDisplayText, "50,25")
        XCTAssertEqual(change?.newDisplayText, "75,40")
    }

    func testMultiplePropertyChangesOnSameElement() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeScreenElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertEqual(delta.edits.updatedOptional?.first?.changes.count, 2)
        let properties = delta.edits.updatedOptional?.first?.changes.map(\.property)
        XCTAssertTrue(properties?.contains(.value) == true)
        XCTAssertTrue(properties?.contains(.hint) == true)
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() throws {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.removedOptional, ["OK"])
        XCTAssertEqual(delta.edits.addedOptional?.first?.label, "Done")
        XCTAssertNil(delta.edits.updatedOptional)
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

        let delta = compareInterfaces(
            before: [first, second],
            after: [second, first],
            beforeTree: beforeTree,
            afterTree: afterTree
        )
        XCTAssertTrue(delta.edits.isEmpty)
    }

    func testMovedIdenticalElementWithSiblingReorderReportsFrameUpdate() throws {
        // Same content (label + identity trait `.button`), only the frame and
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

        let delta = compareInterfaces(
            before: [beforeElement, other],
            after: [other, afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertNil(delta.edits.addedOptional)
        XCTAssertNil(delta.edits.removedOptional)
        XCTAssertEqual(delta.edits.updatedOptional?.count, 1)
        let update = delta.edits.updatedOptional?.first
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

        let delta = compareInterfaces(
            before: [beforeElement, other],
            after: [other, afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertNil(delta.edits.addedOptional)
        XCTAssertNil(delta.edits.removedOptional)
        let update = delta.edits.updatedOptional?.first { $0.after.label == "Favorite" }
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

        let delta = compareInterfaces(
            before: [beforeElement],
            after: [afterElement],
            beforeTree: beforeTree,
            afterTree: afterTree
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertNil(delta.edits.addedOptional)
        XCTAssertNil(delta.edits.removedOptional)
        XCTAssertEqual(delta.edits.updatedOptional?.count, 1)
        let update = delta.edits.updatedOptional?.first
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

        let delta = compareInterfaces(
            before: [first, second],
            after: [first],
            beforeTree: beforeTree,
            afterTree: afterTree
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.removedOptional, ["Second"])
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

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.updatedOptional?.count, 2)
        XCTAssertNil(delta.edits.addedOptional)
        XCTAssertNil(delta.edits.removedOptional)
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

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.updatedOptional?.count, 1)
        XCTAssertEqual(delta.edits.removedOptional?.count, 2)
    }

    // MARK: - Delta: Empty Diff Coerced to noChange

    func testNoDifferencesCoercedToNoChange() throws {
        let treeElement = makeScreenElement(heistId: "btn", label: "OK", traits: [.button])

        let delta = compareInterfaces(
            before: [treeElement], after: [treeElement], afterTree: []
        )
        XCTAssertTrue(delta.edits.isEmpty)
    }

}

#endif

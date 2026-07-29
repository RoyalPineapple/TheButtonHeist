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
        XCTAssertTrue(delta.edits.added.isEmpty)
        XCTAssertTrue(delta.edits.removed.isEmpty)
        XCTAssertTrue(delta.edits.updated.isEmpty)
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
        XCTAssertEqual(delta.edits.added.count, 1)
        XCTAssertEqual(delta.edits.added.first?.semantics.assertable.label, "Cancel")
        XCTAssertTrue(delta.edits.removed.isEmpty)
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
        XCTAssertEqual(delta.edits.removed.count, 1)
        XCTAssertEqual(delta.edits.removed.first?.semantics.assertable.label, "Cancel")
        XCTAssertTrue(delta.edits.added.isEmpty)
    }

    // MARK: - Delta: Property Changes

    func testValueChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%")]
        let after = [makeScreenElement(heistId: "slider", value: "75%")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.updated.count, 1)
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .value)
        XCTAssertEqual(update?.before.semantics.assertable.value, "50%")
        XCTAssertEqual(update?.after.semantics.assertable.value, "75%")
    }

    func testTraitsChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", traits: [.button])]
        let after = [makeScreenElement(heistId: "btn", traits: [.button, .selected])]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .traits)
        XCTAssertEqual(update?.before.semantics.assertable.traits, [.button])
        XCTAssertEqual(update?.after.semantics.assertable.traits, [.button, .selected])
    }

    func testHintChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", hint: "Tap to continue")]
        let after = [makeScreenElement(heistId: "btn", hint: "Tap to go back")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .hint)
        XCTAssertEqual(update?.before.semantics.assertable.hint, "Tap to continue")
        XCTAssertEqual(update?.after.semantics.assertable.hint, "Tap to go back")
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
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .actions)
        XCTAssertEqual(update?.before.semantics.assertable.actions, [.activate])
        XCTAssertEqual(update?.after.semantics.assertable.actions, [])
    }

    func testFrameChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "box", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 50)]
        let after = [makeScreenElement(heistId: "box", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 50)]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .frame)
        XCTAssertEqual(update?.before.geometry.screen, TheVault.onscreenSpace(for: before[0].element))
        XCTAssertEqual(update?.after.geometry.screen, TheVault.onscreenSpace(for: after[0].element))
    }

    func testActivationPointChangeProducesUpdate() throws {
        let before = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 50, y: 25))]
        let after = [makeScreenElement(heistId: "btn", activationPoint: CGPoint(x: 75, y: 40))]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        let update = delta.edits.updated.first
        let change = update?.changes.first
        XCTAssertEqual(change?.property, .activationPoint)
        XCTAssertEqual(update?.before.geometry.screen, TheVault.onscreenSpace(for: before[0].element))
        XCTAssertEqual(update?.after.geometry.screen, TheVault.onscreenSpace(for: after[0].element))
    }

    func testMultiplePropertyChangesOnSameElement() throws {
        let before = [makeScreenElement(heistId: "slider", value: "50%", hint: "Volume")]
        let after = [makeScreenElement(heistId: "slider", value: "75%", hint: "Music Volume")]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        let update = delta.edits.updated.first
        XCTAssertEqual(update?.changes.count, 2)
        XCTAssertEqual(update?.before.semantics.assertable.value, "50%")
        XCTAssertEqual(update?.after.semantics.assertable.value, "75%")
        XCTAssertEqual(update?.before.semantics.assertable.hint, "Volume")
        XCTAssertEqual(update?.after.semantics.assertable.hint, "Music Volume")
        XCTAssertTrue(update?.changes.contains { $0.property == .value } == true)
        XCTAssertTrue(update?.changes.contains { $0.property == .hint } == true)
    }

    // MARK: - Delta: Label Change = Add + Remove

    func testLabelChangeProducesAddAndRemove() throws {
        let before = [makeScreenElement(heistId: "button_ok", label: "OK", traits: [.button])]
        let after = [makeScreenElement(heistId: "button_done", label: "Done", traits: [.button])]

        let delta = compareInterfaces(
            before: before, after: after, afterTree: []
        )
        XCTAssertFalse(delta.edits.isEmpty)
        XCTAssertEqual(delta.edits.removed.first?.semantics.assertable.label, "OK")
        XCTAssertEqual(delta.edits.added.first?.semantics.assertable.label, "Done")
        XCTAssertTrue(delta.edits.updated.isEmpty)
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
        XCTAssertTrue(delta.edits.added.isEmpty)
        XCTAssertTrue(delta.edits.removed.isEmpty)
        XCTAssertEqual(delta.edits.updated.count, 1)
        let update = delta.edits.updated.first
        XCTAssertEqual(update?.after.semantics.assertable.label, "Telescope, Far Light, 3:32")
        XCTAssertEqual(update?.before.geometry.screen, TheVault.onscreenSpace(for: beforeElement.element))
        XCTAssertEqual(update?.after.geometry.screen, TheVault.onscreenSpace(for: afterElement.element))
        XCTAssertEqual(update?.before.semantics.semanticHash, update?.after.semantics.semanticHash)
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
        XCTAssertTrue(delta.edits.added.isEmpty)
        XCTAssertTrue(delta.edits.removed.isEmpty)
        let update = delta.edits.updated.first {
            $0.after.semantics.assertable.label == "Favorite"
        }
        XCTAssertNotNil(update)
        XCTAssertEqual(update?.before.semantics.assertable.value, "0")
        XCTAssertEqual(update?.after.semantics.assertable.value, "1")
        XCTAssertEqual(update?.before.semantics.assertable.traits, [.button])
        XCTAssertEqual(update?.after.semantics.assertable.traits, [.button, .selected])
        XCTAssertEqual(update?.before.geometry.screen, TheVault.onscreenSpace(for: beforeElement.element))
        XCTAssertEqual(update?.after.geometry.screen, TheVault.onscreenSpace(for: afterElement.element))
        XCTAssertNotEqual(update?.before.semantics.semanticHash, update?.after.semantics.semanticHash)
        XCTAssertTrue(update?.changes.contains { $0.property == .value } == true)
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
        XCTAssertTrue(delta.edits.added.isEmpty)
        XCTAssertTrue(delta.edits.removed.isEmpty)
        XCTAssertEqual(delta.edits.updated.count, 1)
        let update = delta.edits.updated.first
        XCTAssertEqual(update?.after.semantics.assertable.label, "Telescope, Far Light, 3:32")
        XCTAssertEqual(update?.before.geometry.screen, TheVault.onscreenSpace(for: beforeElement.element))
        XCTAssertEqual(update?.after.geometry.screen, TheVault.onscreenSpace(for: afterElement.element))
        XCTAssertEqual(update?.before.semantics.semanticHash, update?.after.semantics.semanticHash)
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
        XCTAssertEqual(delta.edits.removed.count, 1)
        XCTAssertEqual(delta.edits.removed.first?.semantics.assertable.label, "Second")
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
        XCTAssertEqual(delta.edits.updated.count, 2)
        XCTAssertEqual(delta.edits.updated.map(\.before.semantics.assertable.value), ["A", "B"])
        XCTAssertEqual(delta.edits.updated.map(\.after.semantics.assertable.value), ["X", "Y"])
        XCTAssertTrue(delta.edits.added.isEmpty)
        XCTAssertTrue(delta.edits.removed.isEmpty)
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
        XCTAssertEqual(delta.edits.updated.count, 1)
        XCTAssertEqual(delta.edits.updated.first?.before.semantics.assertable.value, "A")
        XCTAssertEqual(delta.edits.updated.first?.after.semantics.assertable.value, "X")
        XCTAssertEqual(delta.edits.removed.map(\.semantics.assertable.value), ["B", "C"])
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

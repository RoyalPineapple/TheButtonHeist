import XCTest
@testable import ButtonHeist
import TheScore

final class NetDeltaAccumulatorTests: XCTestCase {

    func testAddUpdateRemoveNetsToNoDelta() {
        let element = makeElement(heistId: "item", label: "Item", value: nil)
        let deltas: [InterfaceDelta] = [
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(added: [element]))),
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(updated: [
                ElementUpdate(
                    heistId: "item",
                    changes: [PropertyChange(property: .value, old: nil, new: "On")]
                ),
            ]))),
            .elementsChanged(.init(elementCount: 0, edits: ElementEdits(removed: ["item"]))),
        ]

        XCTAssertNil(NetDeltaAccumulator.merge(deltas: deltas))
    }

    func testUpdatesToNetAddedElementFoldIntoAddedElement() throws {
        let element = makeElement(heistId: "item", label: "Old", value: nil)
        let deltas: [InterfaceDelta] = [
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(added: [element]))),
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "item", changes: [
                    PropertyChange(property: .label, old: "Old", new: "New"),
                    PropertyChange(property: .value, old: nil, new: "42"),
                ]),
            ]))),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        guard case .elementsChanged(let payload) = merged else {
            return XCTFail("Expected .elementsChanged, got \(merged)")
        }
        XCTAssertEqual(payload.edits.added.first?.label, "New")
        XCTAssertEqual(payload.edits.added.first?.value, "42")
        XCTAssertTrue(payload.edits.updated.isEmpty)
    }

    func testPartiallyAppliedUpdatesToNetAddedElementOnlyRecordUnappliedChanges() throws {
        let element = makeElement(heistId: "item", label: "Old", value: nil, actions: [.activate])
        let deltas: [InterfaceDelta] = [
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(added: [element]))),
            .elementsChanged(.init(elementCount: 1, edits: ElementEdits(updated: [
                ElementUpdate(heistId: "item", changes: [
                    PropertyChange(property: .label, old: "Old", new: "New"),
                    PropertyChange(property: .actions, old: "activate", new: "activate, magic"),
                ]),
            ]))),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        guard case .elementsChanged(let payload) = merged else {
            return XCTFail("Expected .elementsChanged, got \(merged)")
        }
        XCTAssertEqual(payload.edits.added.first?.label, "New")
        XCTAssertEqual(payload.edits.updated.first?.changes.map(\.property), [.actions])
    }

    func testTransientNoChangeDeltaIsPreserved() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading", value: nil)
        let delta: InterfaceDelta = .noChange(.init(elementCount: 3, transient: [spinner]))

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: [delta]))

        guard case .noChange(let payload) = merged else {
            return XCTFail("Expected .noChange, got \(merged)")
        }
        XCTAssertEqual(payload.elementCount, 3)
        XCTAssertEqual(payload.transient.map(\.heistId), ["spinner"])
    }

    func testTransientsSurviveElementMerge() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading", value: nil)
        let done = makeElement(heistId: "done", label: "Done", value: nil)
        let deltas: [InterfaceDelta] = [
            .noChange(.init(elementCount: 1, transient: [spinner])),
            .elementsChanged(.init(elementCount: 2, edits: ElementEdits(added: [done]))),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        guard case .elementsChanged(let payload) = merged else {
            return XCTFail("Expected .elementsChanged, got \(merged)")
        }
        XCTAssertEqual(payload.edits.added.map(\.heistId), ["done"])
        XCTAssertEqual(payload.transient.map(\.heistId), ["spinner"])
    }

    private func makeElement(
        heistId: String,
        label: String,
        value: String?,
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: value,
            identifier: nil,
            traits: [.button],
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: actions
        )
    }
}

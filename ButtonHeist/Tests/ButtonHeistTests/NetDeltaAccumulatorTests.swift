import XCTest
@testable import ButtonHeist
import TheScore

final class NetDeltaAccumulatorTests: XCTestCase {

    func testAddUpdateRemoveNetsToNoDelta() {
        let element = makeElement(heistId: "item", label: "Item", value: nil)
        let deltas = [
            InterfaceDelta(kind: .elementsChanged, elementCount: 1, added: [element]),
            InterfaceDelta(
                kind: .elementsChanged,
                elementCount: 1,
                updated: [
                    ElementUpdate(
                        heistId: "item",
                        changes: [PropertyChange(property: .value, old: nil, new: "On")]
                    ),
                ]
            ),
            InterfaceDelta(kind: .elementsChanged, elementCount: 0, removed: ["item"]),
        ]

        XCTAssertNil(NetDeltaAccumulator.merge(deltas: deltas))
    }

    func testUpdatesToNetAddedElementFoldIntoAddedElement() throws {
        let element = makeElement(heistId: "item", label: "Old", value: nil)
        let deltas = [
            InterfaceDelta(kind: .elementsChanged, elementCount: 1, added: [element]),
            InterfaceDelta(
                kind: .elementsChanged,
                elementCount: 1,
                updated: [
                    ElementUpdate(heistId: "item", changes: [
                        PropertyChange(property: .label, old: "Old", new: "New"),
                        PropertyChange(property: .value, old: nil, new: "42"),
                    ]),
                ]
            ),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        XCTAssertEqual(merged.kind, .elementsChanged)
        XCTAssertEqual(merged.added?.first?.label, "New")
        XCTAssertEqual(merged.added?.first?.value, "42")
        XCTAssertNil(merged.updated)
    }

    func testPartiallyAppliedUpdatesToNetAddedElementOnlyRecordUnappliedChanges() throws {
        let element = makeElement(heistId: "item", label: "Old", value: nil, actions: [.activate])
        let deltas = [
            InterfaceDelta(kind: .elementsChanged, elementCount: 1, added: [element]),
            InterfaceDelta(
                kind: .elementsChanged,
                elementCount: 1,
                updated: [
                    ElementUpdate(heistId: "item", changes: [
                        PropertyChange(property: .label, old: "Old", new: "New"),
                        PropertyChange(property: .actions, old: "activate", new: "activate, magic"),
                    ]),
                ]
            ),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        XCTAssertEqual(merged.added?.first?.label, "New")
        XCTAssertEqual(merged.updated?.first?.changes.map(\.property), [.actions])
    }

    func testTransientNoChangeDeltaIsPreserved() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading", value: nil)
        let delta = InterfaceDelta(kind: .noChange, elementCount: 3, transient: [spinner])

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: [delta]))

        XCTAssertEqual(merged.kind, .noChange)
        XCTAssertEqual(merged.elementCount, 3)
        XCTAssertEqual(merged.transient?.map(\.heistId), ["spinner"])
    }

    func testTransientsSurviveElementMerge() throws {
        let spinner = makeElement(heistId: "spinner", label: "Loading", value: nil)
        let done = makeElement(heistId: "done", label: "Done", value: nil)
        let deltas = [
            InterfaceDelta(kind: .noChange, elementCount: 1, transient: [spinner]),
            InterfaceDelta(kind: .elementsChanged, elementCount: 2, added: [done]),
        ]

        let merged = try XCTUnwrap(NetDeltaAccumulator.merge(deltas: deltas))

        XCTAssertEqual(merged.kind, .elementsChanged)
        XCTAssertEqual(merged.added?.map(\.heistId), ["done"])
        XCTAssertEqual(merged.transient?.map(\.heistId), ["spinner"])
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

import XCTest
@testable import TheScore

final class AccessibilityChangeJournalTests: XCTestCase {

    func testElementsChangedDeltaBuildsCompactReceipt() throws {
        let added = makeElement(heistId: "save", label: "Save")
        let transient = makeElement(heistId: "spinner", label: "Loading")
        let delta = InterfaceDelta.elementsChanged(.init(
            elementCount: 6,
            edits: ElementEdits(
                added: [added],
                removed: ["old"],
                updated: [ElementUpdate(
                    heistId: "counter",
                    changes: [
                        PropertyChange(property: .value, old: "1", new: "2"),
                        PropertyChange(property: .label, old: "Count", new: "Total"),
                    ]
                )]
            ),
            transient: [transient]
        ))

        let journal = AccessibilityChangeJournal(backgroundDelta: delta, sequence: 12)
        let change = try XCTUnwrap(journal.changes.first)

        XCTAssertEqual(change.sequence, 12)
        XCTAssertEqual(change.kind, .elementsChanged)
        XCTAssertEqual(change.summary, "elements changed (6 elements; +1 -1 ~1 transient1)")
        XCTAssertEqual(change.omittedCount, nil)
        XCTAssertEqual(change.samples, [
            AccessibilityChangeSample(heistId: "save", summary: "added button \"Save\""),
            AccessibilityChangeSample(heistId: "old", summary: "removed old"),
            AccessibilityChangeSample(heistId: "counter", summary: "updated label,value"),
            AccessibilityChangeSample(heistId: "spinner", summary: "transient button \"Loading\""),
        ])
    }

    func testReceiptSamplesAreBounded() throws {
        let delta = InterfaceDelta.elementsChanged(.init(
            elementCount: 10,
            edits: ElementEdits(removed: ["one", "two", "three", "four", "five", "six"])
        ))

        let change = try XCTUnwrap(AccessibilityChangeJournal(backgroundDelta: delta).changes.first)

        XCTAssertEqual(change.samples.count, 5)
        XCTAssertEqual(change.omittedCount, 1)
        XCTAssertEqual(change.samples.map(\.heistId), ["one", "two", "three", "four", "five"])
    }

    func testScreenChangedDoesNotStoreNewInterfaceAsSamples() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [
            .element(makeElement(heistId: "title", label: "Settings", traits: [.header])),
            .element(makeElement(heistId: "save", label: "Save")),
        ])
        let delta = InterfaceDelta.screenChanged(.init(elementCount: 2, newInterface: interface))

        let change = try XCTUnwrap(AccessibilityChangeJournal(backgroundDelta: delta).changes.first)

        XCTAssertEqual(change.kind, .screenChanged)
        XCTAssertEqual(change.summary, "screen changed (Settings - 1 button; 2 elements)")
        XCTAssertTrue(change.samples.isEmpty)
    }

    private func makeElement(
        heistId: String,
        label: String,
        traits: [HeistTrait] = [.button]
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label,
            label: label,
            value: nil,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: [.activate]
        )
    }
}

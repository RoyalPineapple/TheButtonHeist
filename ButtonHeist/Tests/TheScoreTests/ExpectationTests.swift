import ButtonHeistTestSupport
import Testing
import ThePlans
@testable import TheScore

@Suite struct ExpectationTests {
    @Test func `events advance expectations one at a time deterministically`() throws {
        let predicates = [
            try resolved(.elementsChanged([
                .appeared(.label("Checkout")),
            ])),
        ]
        let events: [Observation.Event] = [
            .elementsChanged(snapshot([])),
            .elementsChanged(snapshot(["Checkout"])),
        ]
        let first = Expectation(predicates)
        let second = Expectation(predicates)

        let firstPrefix = first.evaluating(events[0])
        let secondPrefix = second.evaluating(events[0])
        #expect(firstPrefix.result != .satisfied)
        #expect(secondPrefix == firstPrefix)

        let firstComplete = firstPrefix.evaluating(events[1])
        let secondComplete = secondPrefix.evaluating(events[1])
        #expect(firstComplete.result == .satisfied)
        #expect(secondComplete == firstComplete)
    }

    @Test func `authored order requires later same-lane predicates to be seen after earlier predicates`() throws {
        let predicates = [
            try resolved(.exists(.label("First"))),
            try resolved(.exists(.label("Second"))),
        ]
        let events: [Observation.Event] = [
            .elementsChanged(snapshot(["Second"])),
            .elementsChanged(snapshot(["First"])),
            .elementsChanged(snapshot(["Second"])),
        ]

        #expect(Expectation(predicates, events: Array(events.dropLast())).result != .satisfied)
        #expect(Expectation(predicates, events: events).result == .satisfied)
    }

    @Test func `events can answer later predicates in independent lanes`() throws {
        let predicates = [
            try resolved(.notification("Saved")),
            try resolved(.exists(.label("Present"))),
        ]
        let events: [Observation.Event] = [
            .elementsChanged(snapshot(["Present"])),
            .notification(try notification(text: "Saved")),
        ]

        #expect(Expectation(predicates, events: [events[0]]).result != .satisfied)
        #expect(Expectation(predicates, events: events).result == .satisfied)
    }

    @Test func `baseline initializes current presence without publishing an event`() throws {
        let expectation = Expectation([
            try resolved(.exists(.label("Ready"))),
            try resolved(.missing(.label("Loading"))),
        ], baseline: snapshot(["Ready"]))

        #expect(expectation.result == .satisfied)
    }

    @Test func `baseline initializes the before leg of an appearance`() throws {
        let expectation = Expectation([
            try resolved(.elementsChanged([
                .appeared(.label("Checkout")),
            ])),
        ], baseline: snapshot([])).evaluating(
            .elementsChanged(snapshot(["Checkout"]))
        )

        #expect(expectation.result == .satisfied)
    }

    @Test func `one event cannot satisfy both legs of an update`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        let before = Expectation([predicate]).evaluating(
            .elementsChanged(snapshot(label: "Total", value: "$1"))
        )
        let after = before.evaluating(
            .elementsChanged(snapshot(label: "Total", value: "$2"))
        )

        #expect(before.result != .satisfied)
        #expect(after.result == .satisfied)
    }

    @Test func `no change matches only a no-change event`() {
        let predicate = ObservationPredicate.noChange
        let afterElements = Expectation([predicate]).evaluating(
            .elementsChanged(snapshot(["Ready"]))
        )
        let afterScreen = afterElements.evaluating(
            .screenChanged(ScreenFacts(idAfter: "Checkout"))
        )
        let afterNoChange = afterScreen.evaluating(.noChange)

        #expect(afterElements.result == .waiting(predicate.description))
        #expect(afterScreen.result == .waiting(predicate.description))
        #expect(afterNoChange.result == .satisfied)
    }

    @Test func `empty expectation is complete before and after events`() {
        let expectation = Expectation()

        #expect(expectation.result == .satisfied)
        #expect(expectation.evaluating(
            .elementsChanged(snapshot(["Anything"]))
        ).result == .satisfied)
        #expect(expectation.evaluating(.noChange).result == .satisfied)
    }

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> ObservationPredicate {
        try predicate.resolve(in: .empty)
    }

    private func snapshot(_ labels: [String]) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(elements: labels.map {
                makeTestHeistElement(description: $0, label: $0)
            }),
            context: .empty
        )
    }

    private func snapshot(
        label: String,
        value: String
    ) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(elements: [
                makeTestHeistElement(label: label, value: value),
            ]),
            context: .empty
        )
    }

    private func notification(
        text: String
    ) throws -> Observation.Notification {
        try #require(Observation.Notification(text: text, element: nil))
    }
}

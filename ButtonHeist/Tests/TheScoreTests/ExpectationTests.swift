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
        var first = Expectation(predicates)
        var second = Expectation(predicates)

        #expect(first.evaluate(events[0]) == .waiting(
            predicates[0].description
        ))
        #expect(second.evaluate(events[0]) == first.result)
        #expect(first.evaluate(events[1]) == .satisfied)
        #expect(second.evaluate(events[1]) == first.result)
    }

    @Test func `authored order requires later same-lane predicates to be seen after earlier predicates`() throws {
        let predicates = [
            try resolved(.exists(.label("First"))),
            try resolved(.exists(.label("Second"))),
        ]
        var expectation = Expectation(predicates)

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Second"]))
        ) != .satisfied)
        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["First"]))
        ) != .satisfied)
        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Second"]))
        ) == .satisfied)
    }

    @Test func `events can answer later predicates in independent lanes`() throws {
        let predicates = [
            try resolved(.notification("Saved")),
            try resolved(.exists(.label("Present"))),
        ]
        var expectation = Expectation(predicates)

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Present"]))
        ) != .satisfied)
        #expect(expectation.evaluate(
            .notification(try notification(text: "Saved"))
        ) == .satisfied)
    }

    @Test func `baseline initializes current presence without publishing an event`() throws {
        let expectation = Expectation([
            try resolved(.exists(.label("Ready"))),
            try resolved(.missing(.label("Loading"))),
        ], baseline: snapshot(["Ready"]))

        #expect(expectation.result == .satisfied)
    }

    @Test func `baseline initializes the before leg of an appearance`() throws {
        var expectation = Expectation([
            try resolved(.elementsChanged([
                .appeared(.label("Checkout")),
            ])),
        ], baseline: snapshot([]))

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Checkout"]))
        ) == .satisfied)
    }

    @Test func `one event cannot satisfy both legs of an update`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(label: "Total", value: "$1"))
        ) == .waiting(predicate.description))
        #expect(expectation.evaluate(
            .elementsChanged(snapshot(label: "Total", value: "$2"))
        ) == .satisfied)
    }

    @Test func `no change matches only an authored no-change event`() throws {
        let predicate = try resolved(.noChange)
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Ready"]))
        ) == .waiting(predicate.description))
        #expect(expectation.evaluate(
            .screenChanged(ScreenFacts(idAfter: "Checkout"))
        ) == .waiting(predicate.description))
        #expect(expectation.evaluate(.noChange) == .satisfied)
    }

    @Test func `empty expectation is complete before and after events`() {
        var expectation = Expectation()

        #expect(expectation.result == .satisfied)
        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Anything"]))
        ) == .satisfied)
        #expect(expectation.evaluate(.noChange) == .satisfied)
    }

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> Observation.Event.Predicate {
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

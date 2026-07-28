import ButtonHeistTestSupport
import Testing
import ThePlans
@testable import TheScore

@Suite struct ObservationFactFoldTests {
    @Test func `same authored events produce the same result at every prefix`() throws {
        let predicates = [
            try resolved(.exists(.label("Pay"))),
            try resolved(.screenChanged("Checkout")),
        ]
        let events: [Observation.Event] = [
            .elementsChanged(snapshot(["Cart"])),
            .elementsChanged(snapshot(["Pay"])),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .noChange,
        ]
        var first = Expectation(predicates)
        var second = Expectation(predicates)

        for event in events {
            #expect(first.evaluate(event) == second.evaluate(event))
        }
        #expect(first.result == .satisfied)
        #expect(second.result == .satisfied)
    }

    @Test func `a consumed prefix does not alter a fresh replay`() throws {
        let predicates = [try resolved(.exists(.label("Pay")))]
        var prefix = Expectation(predicates)
        var replay = Expectation(predicates)

        #expect(prefix.evaluate(
            .elementsChanged(snapshot(["Cart"]))
        ) != .satisfied)
        #expect(replay.evaluate(
            .elementsChanged(snapshot(["Cart"]))
        ) == prefix.result)
        #expect(replay.evaluate(
            .elementsChanged(snapshot(["Pay"]))
        ) == .satisfied)
    }

    @Test func `screen replacement is authored as departure boundary arrival`() {
        let events = screenReplacementEvents(
            arriving: snapshot(["Checkout"])
        )

        guard case .elementsChanged(let departure) = events[0],
              case .screenChanged(let screen) = events[1],
              case .elementsChanged(let arrival) = events[2]
        else {
            Issue.record("Expected departure, screen boundary, and arrival")
            return
        }
        #expect(departure.interface.projectedElements.isEmpty)
        #expect(screen == ScreenFacts(idAfter: "Checkout"))
        #expect(arrival == snapshot(["Checkout"]))
    }

    @Test func `appearance consumes departure then arrival across a screen boundary`() throws {
        let predicate = try resolved(.elementsChanged([
            .appeared(.label("Checkout")),
        ]))
        let events = screenReplacementEvents(
            arriving: snapshot(["Checkout"])
        )
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(events[0]) == .waiting(predicate.description))
        #expect(expectation.evaluate(events[1]) == .waiting(predicate.description))
        #expect(expectation.evaluate(events[2]) == .satisfied)
    }

    @Test func `disappearance consumes presence then departure across a screen boundary`() throws {
        let predicate = try resolved(.elementsChanged([
            .disappeared(.label("Library")),
        ]))
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Library"]))
        ) == .waiting(predicate.description))
        #expect(expectation.evaluate(
            .screenChanged(ScreenFacts(idAfter: "Checkout"))
        ) == .waiting(predicate.description))
        #expect(expectation.evaluate(
            .elementsChanged(snapshot([]))
        ) == .satisfied)
    }

    @Test func `no-change event is retained in authored order without answering other lanes`() throws {
        let predicates = [
            try resolved(.noChange),
            try resolved(.notification("Saved")),
        ]
        var expectation = Expectation(predicates)

        #expect(expectation.evaluate(
            .notification(try #require(
                Observation.Notification(text: "Saved", element: nil)
            ))
        ) != .satisfied)
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

    private func screenReplacementEvents(
        arriving: Observation.Snapshot
    ) -> [Observation.Event] {
        [
            .elementsChanged(.empty(timestamp: arriving.interface.timestamp)),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(arriving),
        ]
    }
}

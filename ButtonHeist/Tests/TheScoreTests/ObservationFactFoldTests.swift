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
            first = first.evaluating(event)
            second = second.evaluating(event)
            #expect(first == second)
        }
        #expect(first.result == .satisfied)
        #expect(second.result == .satisfied)
    }

    @Test func `a consumed prefix does not alter a fresh replay`() throws {
        let predicates = [try resolved(.exists(.label("Pay")))]
        let cart = Observation.Event.elementsChanged(snapshot(["Cart"]))
        let pay = Observation.Event.elementsChanged(snapshot(["Pay"]))
        let prefix = Expectation(predicates).evaluating(cart)
        let replayPrefix = Expectation(predicates).evaluating(cart)
        let replay = replayPrefix.evaluating(pay)

        #expect(prefix.result != .satisfied)
        #expect(replayPrefix == prefix)
        #expect(replay.result == .satisfied)
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
        #expect(Expectation([predicate], events: [events[0]]).result != .satisfied)
        #expect(Expectation(
            [predicate],
            events: Array(events.dropLast())
        ).result != .satisfied)
        #expect(Expectation([predicate], events: events).result == .satisfied)
    }

    @Test func `disappearance consumes presence then departure across a screen boundary`() throws {
        let predicate = try resolved(.elementsChanged([
            .disappeared(.label("Library")),
        ]))
        let events: [Observation.Event] = [
            .elementsChanged(snapshot(["Library"])),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot([])),
        ]

        #expect(Expectation([predicate], events: [events[0]]).result != .satisfied)
        #expect(Expectation(
            [predicate],
            events: Array(events.dropLast())
        ).result != .satisfied)
        #expect(Expectation([predicate], events: events).result == .satisfied)
    }

    @Test func `no-change event is retained in authored order without answering other lanes`() throws {
        let predicates: [ObservationPredicate] = [
            .noChange,
            try resolved(.notification("Saved")),
        ]
        let notification = Observation.Event.notification(try #require(
            Observation.Notification(text: "Saved", element: nil)
        ))
        let beforeNoChange = Expectation(predicates).evaluating(notification)
        let complete = beforeNoChange.evaluating(.noChange)

        #expect(beforeNoChange.result != .satisfied)
        #expect(complete.result == .satisfied)
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

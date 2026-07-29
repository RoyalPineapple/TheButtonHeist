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

    @Test func `fold preserves identity and composition`() throws {
        let predicates = [try resolved(.exists(.label("Pay")))]
        let cart = Observation.Event.elementsChanged(snapshot(["Cart"]))
        let pay = Observation.Event.elementsChanged(snapshot(["Pay"]))
        let initial = Expectation(predicates)
        let allAtOnce = [cart, pay].reduce(initial) { $0.evaluating($1) }
        let prefix = [cart].reduce(initial) { $0.evaluating($1) }
        let composed = [pay].reduce(prefix) { $0.evaluating($1) }

        #expect([Observation.Event]().reduce(initial) { $0.evaluating($1) } == initial)
        #expect(prefix.result != .satisfied)
        #expect(composed == allAtOnce)
        #expect(composed.result == .satisfied)
    }

    @Test func `screen replacement is authored as boundary then actual state`() {
        let events = screenReplacementEvents(
            arriving: snapshot(["Checkout"])
        )

        guard case .screenChanged(let screen) = events[0],
              case .elementsChanged(let arrival) = events[1]
        else {
            Issue.record("Expected screen boundary and actual arrival")
            return
        }
        #expect(screen == ScreenFacts(idAfter: "Checkout"))
        #expect(arrival == snapshot(["Checkout"]))
    }

    @Test func `replacement reintroduces matching new-generation targets`() throws {
        let predicate = try resolved(.elementsChanged([
            .appeared(.label("Checkout")),
        ]))
        let events = screenReplacementEvents(
            arriving: snapshot(["Checkout"])
        )
        let expectation = Expectation(
            [predicate],
            baseline: snapshot(["Checkout"])
        )
        let afterBoundary = expectation.evaluating(events[0])

        #expect(afterBoundary.result != .satisfied)
        #expect(afterBoundary.evaluating(events[1]).result == .satisfied)
    }

    @Test func `replacement removes matching old-generation targets`() throws {
        let predicate = try resolved(.elementsChanged([
            .disappeared(.label("Library")),
        ]))
        let events: [Observation.Event] = [
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot(["Library"])),
        ]
        let expectation = Expectation(
            [predicate],
            baseline: snapshot(["Library"])
        )

        #expect(expectation.result != .satisfied)
        #expect(expectation.evaluating(events[0]).result == .satisfied)
        #expect(Expectation(
            [predicate],
            baseline: snapshot(["Library"]),
            events: events
        ).result == .satisfied)
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
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(arriving),
        ]
    }
}

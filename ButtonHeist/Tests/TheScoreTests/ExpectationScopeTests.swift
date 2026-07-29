import ButtonHeistTestSupport
import Testing
import ThePlans
@testable import TheScore

@Suite struct ExpectationScopeTests {
    @Test func `graph semantic projection ignores geometry`() throws {
        let expectation = Expectation([
            try resolved(.elementsChanged),
        ])
        let before = snapshot([
            makeTestHeistElement(label: "Ready", frameX: 0),
            makeTestHeistElement(label: "Pay", frameX: 100),
        ])
        let after = snapshot([
            makeTestHeistElement(label: "Ready", frameX: 800),
            makeTestHeistElement(label: "Pay", frameX: 400),
        ])

        #expect(evaluateExpectation(
            expectation,
            events: [.elementsChanged(before)]
        ) != .satisfied)
        #expect(evaluateExpectation(
            expectation,
            events: [.elementsChanged(before), .elementsChanged(after)]
        ) != .satisfied)
    }

    @Test func `graph semantic projection preserves duplicate cardinality`() throws {
        let expectation = Expectation([
            try resolved(.elementsChanged),
        ])

        let events: [Observation.Event] = [
            .elementsChanged(snapshot(["Ready"])),
            .elementsChanged(snapshot(["Ready", "Ready"])),
        ]
        #expect(evaluateExpectation(expectation, events: [events[0]]) != .satisfied)
        #expect(evaluateExpectation(expectation, events: events) == .satisfied)
    }

    @Test func `graph semantic projection compares exact element values`() throws {
        let expectation = Expectation([
            try resolved(.elementsChanged),
        ])
        let before = snapshot([
            makeTestHeistElement(
                description: "Ready",
                label: "Ready",
                respondsToUserInteraction: false
            ),
        ])
        let after = snapshot([
            makeTestHeistElement(
                description: "Ready. Button.",
                label: "Ready",
                respondsToUserInteraction: true
            ),
        ])

        #expect(evaluateExpectation(
            expectation,
            events: [.elementsChanged(before)]
        ) != .satisfied)
        #expect(evaluateExpectation(
            expectation,
            events: [.elementsChanged(before), .elementsChanged(after)]
        ) == .satisfied)
    }

    @Test func `graph semantic projection is permutation invariant`() throws {
        let expectation = Expectation([
            try resolved(.elementsChanged),
        ])
        let before = snapshot([
            makeTestHeistElement(label: "Ready"),
            makeTestHeistElement(label: "Pay"),
        ])
        let after = snapshot([
            makeTestHeistElement(label: "Pay"),
            makeTestHeistElement(label: "Ready"),
        ])

        #expect(evaluateExpectation(
            expectation,
            events: [.elementsChanged(before), .elementsChanged(after)]
        ) != .satisfied)
    }

    @Test func `target scope ignores changes outside the matched target`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        let events: [Observation.Event] = [
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$1"),
                makeTestHeistElement(label: "Status", value: "Idle"),
            ])),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$1"),
                makeTestHeistElement(label: "Status", value: "Busy"),
            ])),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$2"),
                makeTestHeistElement(label: "Status", value: "Busy"),
            ])),
        ]

        #expect(evaluateExpectation(
            Expectation([predicate]),
            events: Array(events.prefix(2))
        ) != .satisfied)
        #expect(evaluateExpectation(
            Expectation([predicate]),
            events: events
        ) == .satisfied)
    }

    @Test func `property scope ignores changes to other properties`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        let events: [Observation.Event] = [
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$1", hint: "Old"),
            ])),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$1", hint: "New"),
            ])),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$2", hint: "New"),
            ])),
        ]

        #expect(evaluateExpectation(
            Expectation([predicate]),
            events: Array(events.prefix(2))
        ) != .satisfied)
        #expect(evaluateExpectation(
            Expectation([predicate]),
            events: events
        ) == .satisfied)
    }

    @Test func `screen boundary resets an unfinished property update`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        let expectation = Expectation(
            [predicate],
            baseline: snapshot([
                makeTestHeistElement(label: "Total", value: "$1"),
            ])
        )

        let events: [Observation.Event] = [
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$2"),
            ])),
            .elementsChanged(snapshot([
                makeTestHeistElement(label: "Total", value: "$3"),
            ])),
        ]

        #expect(evaluateExpectation(
            expectation,
            events: Array(events.prefix(2))
        ) != .satisfied)
        #expect(evaluateExpectation(expectation, events: events) == .satisfied)
    }

    @Test func `container target scope does not require child elements`() throws {
        let appeared = Expectation([
            try resolved(.elementsChanged([
                .appeared(.container(.identifier("checkout"))),
            ])),
        ])
        let disappeared = Expectation([
            try resolved(.elementsChanged([
                .disappeared(.container(.identifier("checkout"))),
            ])),
        ])
        let missing = Observation.Event.elementsChanged(containerSnapshot([]))
        let exists = Observation.Event.elementsChanged(
            containerSnapshot(["checkout"])
        )

        #expect(evaluateExpectation(appeared, events: [missing]) != .satisfied)
        #expect(evaluateExpectation(appeared, events: [missing, exists]) == .satisfied)
        #expect(evaluateExpectation(disappeared, events: [exists]) != .satisfied)
        #expect(evaluateExpectation(disappeared, events: [exists, missing]) == .satisfied)
    }

    @Test func `notification text and element must match the same event`() throws {
        let predicate = try resolved(.notification(
            text: .exact("Saved"),
            element: ElementPredicate(label: "Save", value: "Done")
        ))
        let semantics = makeTestHeistElement(
            label: "Save",
            value: "Done"
        ).semantics
        let textOnly = try #require(Observation.Notification(
            text: "Saved",
            element: nil
        ))
        let elementOnly = try #require(Observation.Notification(
            text: nil,
            element: semantics
        ))
        let combined = try #require(Observation.Notification(
            text: "Saved",
            element: semantics
        ))
        let expectation = Expectation([predicate])

        #expect(evaluateExpectation(
            expectation,
            events: [.notification(textOnly), .notification(elementOnly)]
        ) != .satisfied)
        #expect(evaluateExpectation(
            expectation,
            events: [.notification(combined)]
        ) == .satisfied)
    }

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> ObservationPredicate {
        try predicate.resolve(in: .empty)
    }

    private func snapshot(_ labels: [String]) -> Observation.Snapshot {
        snapshot(labels.map {
            makeTestHeistElement(description: $0, label: $0)
        })
    }

    private func snapshot(_ elements: [HeistElement]) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(elements: elements),
            context: .empty
        )
    }

    private func containerSnapshot(
        _ identifiers: [String]
    ) -> Observation.Snapshot {
        Observation.Snapshot(
            interface: makeTestInterface(nodes: identifiers.map { identifier in
                testContainer(
                    makeTestSemanticContainer(
                        label: "Group",
                        identifier: identifier
                    ),
                    children: []
                )
            }),
            context: .empty
        )
    }
}

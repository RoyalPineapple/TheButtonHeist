import ButtonHeistTestSupport
import Testing
import ThePlans
@testable import TheScore

@Suite struct ExpectationScopeTests {
    @Test func `graph semantic hash ignores geometry`() throws {
        var expectation = Expectation([
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

        #expect(expectation.evaluate(.elementsChanged(before)) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(after)) != .satisfied)
    }

    @Test func `graph semantic hash preserves duplicate cardinality`() throws {
        var expectation = Expectation([
            try resolved(.elementsChanged),
        ])

        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Ready"]))
        ) != .satisfied)
        #expect(expectation.evaluate(
            .elementsChanged(snapshot(["Ready", "Ready"]))
        ) == .satisfied)
    }

    @Test func `graph semantic hash includes complete element semantics`() throws {
        var expectation = Expectation([
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

        #expect(expectation.evaluate(.elementsChanged(before)) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(after)) == .satisfied)
    }

    @Test func `target scope ignores changes outside the matched target`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$1"),
            makeTestHeistElement(label: "Status", value: "Idle"),
        ]))) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$1"),
            makeTestHeistElement(label: "Status", value: "Busy"),
        ]))) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$2"),
            makeTestHeistElement(label: "Status", value: "Busy"),
        ]))) == .satisfied)
    }

    @Test func `property scope ignores changes to other properties`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        var expectation = Expectation([predicate])

        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$1", hint: "Old"),
        ]))) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$1", hint: "New"),
        ]))) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$2", hint: "New"),
        ]))) == .satisfied)
    }

    @Test func `screen boundary resets an unfinished property update`() throws {
        let predicate = try resolved(.elementsChanged([
            .updated(.label("Total"), .value()),
        ]))
        var expectation = Expectation(
            [predicate],
            baseline: snapshot([
                makeTestHeistElement(label: "Total", value: "$1"),
            ])
        )

        #expect(expectation.evaluate(
            .screenChanged(ScreenFacts(idAfter: "Checkout"))
        ) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$2"),
        ]))) != .satisfied)
        #expect(expectation.evaluate(.elementsChanged(snapshot([
            makeTestHeistElement(label: "Total", value: "$3"),
        ]))) == .satisfied)
    }

    @Test func `container target scope does not require child elements`() throws {
        var appeared = Expectation([
            try resolved(.elementsChanged([
                .appeared(.container(.identifier("checkout"))),
            ])),
        ])
        var disappeared = Expectation([
            try resolved(.elementsChanged([
                .disappeared(.container(.identifier("checkout"))),
            ])),
        ])
        let missing = Observation.Event.elementsChanged(containerSnapshot([]))
        let exists = Observation.Event.elementsChanged(
            containerSnapshot(["checkout"])
        )

        #expect(appeared.evaluate(missing) != .satisfied)
        #expect(appeared.evaluate(exists) == .satisfied)
        #expect(disappeared.evaluate(exists) != .satisfied)
        #expect(disappeared.evaluate(missing) == .satisfied)
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
        var separated = Expectation([predicate])
        var together = Expectation([predicate])

        #expect(separated.evaluate(.notification(textOnly)) != .satisfied)
        #expect(separated.evaluate(.notification(elementOnly)) != .satisfied)
        #expect(together.evaluate(.notification(combined)) == .satisfied)
    }

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> Observation.Event.Predicate {
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

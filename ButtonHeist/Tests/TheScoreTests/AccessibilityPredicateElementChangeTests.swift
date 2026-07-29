import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

extension AccessibilityPredicateTests {
    func testElementsChangedRoundTrips() throws {
        let predicates: [AccessibilityPredicate] = [
            .elementsChanged,
            .elementsChanged([
                .appeared(.label("Ready")),
                .disappeared(.label("Loading")),
                .updated(
                    .label("Counter"),
                    .value(before: "3", after: "5")
                ),
            ]),
        ]

        for predicate in predicates {
            let data = try JSONEncoder().encode(predicate)
            XCTAssertEqual(
                try JSONDecoder().decode(
                    AccessibilityPredicate.self,
                    from: data
                ),
                predicate
            )
        }
    }

    func testBareElementsChangedRequiresGraphSemanticMovement() throws {
        let before = observationSnapshot(elements: [
            element(label: "Status"),
        ])
        let after = observationSnapshot(elements: [
            element(label: "Status"),
            element(label: "Detail"),
        ])
        let expectation = Expectation([
            try resolvedChange(.elementsChanged),
        ])

        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(before),
        ]).isSatisfied)
        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .elementsChanged(before),
            .elementsChanged(after),
        ]).isSatisfied)
    }

    func testUpdatedRequiresTargetAndPropertyAtDecodeBoundary() {
        let stale = Data("""
        {
          "type": "updated",
          "target": {
            "checks": [{
              "kind": "label",
              "match": {"mode": "exact", "value": "counter"}
            }]
          }
        }
        """.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(ElementAssertion.self, from: stale)
        )
    }

    func testUpdatedValueMatchesAuthoredBeforeAndAfterChecks() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "3", after: "5")
        )

        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "3"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "5"),
            ])),
        ]).isSatisfied)
        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "4"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "5"),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedUsesEveryStringMatchMode() throws {
        let changes: [ElementPropertyChange] = [
            .value(
                before: .exact("Search for tea"),
                after: .exact("John Smith")
            ),
            .value(
                before: .contains("for"),
                after: .contains("Smith")
            ),
            .value(
                before: .prefix("Search"),
                after: .prefix("John")
            ),
            .value(
                before: .suffix("tea"),
                after: .suffix("Smith")
            ),
        ]
        let events: [Observation.Event] = [
            .elementsChanged(snapshot([
                element(label: "Search", value: "Search for tea"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Search", value: "John Smith"),
            ])),
        ]

        for change in changes {
            XCTAssertTrue(
                evaluateExpectation(
                    try updateExpectation(
                        target: .label("Search"),
                        change: change
                    ),
                    events: events
                ).isSatisfied,
                "\(change)"
            )
        }
    }

    func testUpdatedIgnoresSemanticChangeOutsidePropertyScope() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "1")
        )
        let before = element(
            label: "Counter",
            value: "1",
            hint: "Old hint",
            traits: [.staticText]
        )
        let after = element(
            label: "Counter",
            value: "1",
            hint: "New hint",
            traits: [.button],
            actions: [.activate]
        )

        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([before])),
            .elementsChanged(snapshot([after])),
        ]).isSatisfied)
    }

    func testUpdatedRejectsIdenticalPropertyReadings() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "1")
        )
        let counter = element(label: "Counter", value: "1")

        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([counter])),
            .elementsChanged(snapshot([counter])),
        ]).isSatisfied)
    }

    func testUpdatedRejectsGeometryOnlyChange() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "1")
        )
        let before = element(
            label: "Counter",
            value: "1",
            frameX: 0,
            frameY: 0
        )
        let after = element(
            label: "Counter",
            value: "1",
            frameX: 200,
            frameY: 300
        )

        XCTAssertEqual(before.semantics, after.semantics)
        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([before])),
            .elementsChanged(snapshot([after])),
        ]).isSatisfied)
    }

    func testUpdatedPropertyReadingUsesDuplicateCardinality() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "1")
        )
        let counter = element(label: "Counter", value: "1")

        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([counter])),
            .elementsChanged(snapshot([counter, counter])),
        ]).isSatisfied)
    }

    func testUpdatedTraitsMatchGainAndLoss() throws {
        let gain = try updateExpectation(
            target: .label("Favorite"),
            change: .traits(
                before: .init(exclude: [.selected]),
                after: .init(include: [.selected])
            )
        )
        let loss = try updateExpectation(
            target: .label("Disabled"),
            change: .traits(
                before: .init(include: [.notEnabled]),
                after: .init(exclude: [.notEnabled])
            )
        )

        XCTAssertTrue(evaluateExpectation(gain, events: [
            .elementsChanged(snapshot([
                element(label: "Favorite", traits: [.button]),
            ])),
            .elementsChanged(snapshot([
                element(label: "Favorite", traits: [.button, .selected]),
            ])),
        ]).isSatisfied)
        XCTAssertTrue(evaluateExpectation(loss, events: [
            .elementsChanged(snapshot([
                element(label: "Disabled", traits: [.button, .notEnabled]),
            ])),
            .elementsChanged(snapshot([
                element(label: "Disabled", traits: [.button]),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedActionsUseTypedSetChecks() throws {
        let expectation = try updateExpectation(
            target: .label("Stepper"),
            change: .actions(
                before: ActionSetMatch(exclude: [.activate]),
                after: ActionSetMatch(include: [.activate])
            )
        )

        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Stepper", actions: [.increment]),
            ])),
            .elementsChanged(snapshot([
                element(
                    label: "Stepper",
                    actions: [.increment, .activate]
                ),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedCustomContentAndRotorsUseTypedSetChecks() throws {
        let customContent = HeistCustomContent(
            label: "Status",
            value: "Ready to submit",
            isImportant: true
        )
        let customExpectation = try updateExpectation(
            target: .label("Form"),
            change: .customContent(after: CustomContentMatch(
                label: .exact("Status"),
                value: .contains("Ready"),
                isImportant: true
            ))
        )
        let rotorExpectation = try updateExpectation(
            target: .label("Article"),
            change: .rotors(
                before: RotorSetMatch(exclude: [.exact("Headings")]),
                after: RotorSetMatch(include: [.contains("Head")])
            )
        )

        XCTAssertTrue(evaluateExpectation(customExpectation, events: [
            .elementsChanged(snapshot([
                element(
                    label: "Form",
                    customContent: [
                        HeistCustomContent(
                            label: "Help",
                            value: "Optional",
                            isImportant: false
                        ),
                    ]
                ),
            ])),
            .elementsChanged(snapshot([
                element(label: "Form", customContent: [customContent]),
            ])),
        ]).isSatisfied)
        XCTAssertTrue(evaluateExpectation(rotorExpectation, events: [
            .elementsChanged(snapshot([
                element(
                    label: "Article",
                    rotors: [HeistRotor(name: "Links")]
                ),
            ])),
            .elementsChanged(snapshot([
                element(
                    label: "Article",
                    rotors: [
                        HeistRotor(name: "Headings"),
                        HeistRotor(name: "Links"),
                    ]
                ),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedRequiresMatchingTargetOnBothEvents() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value()
        )

        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Total", value: "2"),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedCannotCrossScreenGeneration() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "2")
        )
        XCTAssertFalse(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "2"),
            ])),
        ]).isSatisfied)
    }

    func testUpdatedCanRestartWithinNewScreenGeneration() throws {
        let expectation = try updateExpectation(
            target: .label("Counter"),
            change: .value(before: "1", after: "2")
        )
        XCTAssertTrue(evaluateExpectation(expectation, events: [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "2"),
            ])),
        ]).isSatisfied)
    }

    func testScreenBoundaryResetBlocksLaterAuthoredPredicate() throws {
        let expectation = Expectation([
            try resolvedChange(.elementsChanged([
                .updated(
                    .label("Counter"),
                    .value(before: "1", after: "2")
                ),
            ])),
            try resolvedChange(.screenChanged("Checkout")),
        ])
        let events: [Observation.Event] = [
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .screenChanged(ScreenFacts(idAfter: "Checkout")),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "1"),
            ])),
            .elementsChanged(snapshot([
                element(label: "Counter", value: "2"),
            ])),
        ]

        XCTAssertFalse(evaluateExpectation(expectation, events: events).isSatisfied)
        XCTAssertTrue(evaluateExpectation(
            expectation,
            events: events + [.screenChanged(ScreenFacts(idAfter: "Checkout"))]
        ).isSatisfied)
    }

    private func updateExpectation(
        target: AccessibilityElementTarget,
        change: ElementPropertyChange
    ) throws -> Expectation {
        Expectation([
            try resolvedChange(.elementsChanged([
                .updated(target, change),
            ])),
        ])
    }

    private func resolvedChange(
        _ predicate: AccessibilityPredicate
    ) throws -> ObservationPredicate {
        try predicate.resolve(in: .empty)
    }

    private func snapshot(_ elements: [HeistElement]) -> Observation.Snapshot {
        observationSnapshot(elements: elements)
    }
}

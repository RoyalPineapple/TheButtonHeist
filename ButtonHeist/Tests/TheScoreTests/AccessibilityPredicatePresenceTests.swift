import AccessibilitySnapshotModel
import ButtonHeistTestSupport
import ThePlans
import XCTest
@testable import TheScore

final class AccessibilityPredicateTests: XCTestCase {
    func testPresencePredicatesRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .exists(.label("Done")),
            .missing(.label("Loading")),
            .exists(.container(.identifier("checkout-container"))),
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

    func testContainerIdentifierKeepsItsWireContract() throws {
        let predicate = AccessibilityPredicate.exists(
            .container(.identifier("checkout-container"))
        )
        let object = try JSONProbe(data: JSONEncoder().encode(predicate))
        let checks = try object.object("target")
            .object("container")
            .array("checks")

        XCTAssertEqual(try object.string("type"), "exists")
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(try checks[0].string("kind"), "identifier")
        XCTAssertEqual(
            try checks[0].object("match").string("value"),
            "checkout-container"
        )
    }

    func testExistsAndMissingReadAnElementsChangedEvent() throws {
        let event = Observation.Event.elementsChanged(
            observationSnapshot(elements: [element(label: "Ready")])
        )
        let exists = evaluateExpectation(Expectation([
            try resolved(.exists(.label("Ready"))),
        ]), events: [event])
        let missing = evaluateExpectation(Expectation([
            try resolved(.missing(.label("Loading"))),
        ]), events: [event])
        let contradicted = evaluateExpectation(Expectation([
            try resolved(.missing(.label("Ready"))),
        ]), events: [event])

        XCTAssertTrue(exists.isSatisfied)
        XCTAssertTrue(missing.isSatisfied)
        XCTAssertFalse(contradicted.isSatisfied)
        XCTAssertTrue(
            contradicted.outstandingDescription?.contains("Ready") == true
        )
    }

    func testEvidenceEvaluatesCurrentPresenceFromBaseline() throws {
        let baseline = observationSnapshot(elements: [element(label: "Ready")])
        let evidence = Observation.Evidence(
            baseline: baseline,
            current: baseline,
            events: [],
            completeness: .complete
        )

        XCTAssertTrue(
            try resolved(.exists(.label("Ready"))).evaluate(in: evidence).met
        )
        XCTAssertTrue(
            try resolved(.missing(.label("Loading"))).evaluate(in: evidence).met
        )
    }

    func testCanonicalTargetGraphAndExpectationAgree() throws {
        let subject = element(
            label: "Checkout",
            value: "Ready",
            identifier: "checkout.button",
            hint: "Opens checkout",
            traits: [.button],
            customContent: [
                HeistCustomContent(
                    label: "State",
                    value: "Ready",
                    isImportant: true
                ),
            ],
            rotors: [HeistRotor(name: "Actions")],
            actions: [.activate]
        )
        let interface = makeTestInterface(nodes: [testElement(subject)])
        let event = Observation.Event.elementsChanged(
            observationSnapshot(nodes: [testElement(subject)])
        )
        let targets: [AccessibilityTarget] = [
            .label(.contains("Check")),
            .identifier(.suffix("button")),
            .value("Ready"),
            .hint(.prefix("Opens")),
            .traits([.button]),
            .actions([.activate]),
            .customContent(
                CustomContentMatch(label: "State", value: "Ready")
            ),
            .rotors(["Actions"]),
            .exclude(.label("Cancel")),
        ]

        for target in targets {
            let graphMatched = !AccessibilityTargetMatchGraph(
                interface: interface
            ).resolve(try target.resolve(in: .empty)).isEmpty
            let expectationMatched = evaluateExpectation(Expectation([
                try resolved(.exists(target)),
            ]), events: [event]).isSatisfied

            XCTAssertTrue(graphMatched, "\(target)")
            XCTAssertEqual(expectationMatched, graphMatched, "\(target)")
        }
    }

    func testEqualElementsRemainDistinctByTreePath() throws {
        let duplicate = element(label: "Save", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(duplicate),
                testElement(duplicate),
            ]),
        ])

        let matches = AccessibilityTargetMatchGraph(interface: interface)
            .resolve(ResolvedElementPredicate.label("Save"))

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(
            matches.orderedPaths,
            [TreePath([0, 0]), TreePath([0, 1])]
        )
    }

    func testPredicateChecksIntersectAndExcludeMatchSets() throws {
        let elements = [
            element(
                label: "Save",
                identifier: "primary",
                traits: [.button],
                actions: [.activate]
            ),
            element(
                label: "Save",
                identifier: "primary",
                traits: [.staticText]
            ),
            element(
                label: "Save",
                identifier: "secondary",
                traits: [.button]
            ),
        ]
        let graph = AccessibilityTargetMatchGraph(elements: elements)
        let predicate = try ElementPredicate([
            .label("Save"),
            .identifier("primary"),
            .traits([.button]),
            .exclude(.actions([.custom("Archive")])),
        ]).resolve(in: .empty)

        let matches = graph.resolve(predicate)

        XCTAssertEqual(matches.elements, [elements[0]])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0])])
    }

    func testOrdinalSelectsFromTheNarrowedMatchSet() throws {
        let elements = [
            element(label: "Save", traits: [.button]),
            element(label: "Save", traits: [.staticText]),
            element(label: "Save", traits: [.button]),
        ]
        let target = AccessibilityTarget.predicate(
            ElementPredicate(label: "Save", traits: [.button]),
            ordinal: 1
        )
        let selected = AccessibilityTargetMatchGraph(elements: elements)
            .resolve(try target.resolve(in: .empty))

        XCTAssertEqual(selected.elements.elements, [elements[2]])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([2])])
    }

    func testWithinContainerSelectsOnlyDescendants() throws {
        let checkoutPay = element(label: "Pay", traits: [.button])
        let cartPay = element(label: "Pay", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(
                makeTestAccessibilityContainer(
                    type: .semanticGroup(label: "Checkout", value: nil)
                ),
                children: [testElement(checkoutPay)]
            ),
            testContainer(
                makeTestAccessibilityContainer(
                    type: .semanticGroup(label: "Cart", value: nil)
                ),
                children: [testElement(cartPay)]
            ),
        ])
        let target = AccessibilityTarget.within(
            container: .label("Checkout"),
            target: .label("Pay")
        )

        let selected = AccessibilityTargetMatchGraph(interface: interface)
            .resolve(try target.resolve(in: .empty))

        XCTAssertEqual(selected.elements.elements, [checkoutPay])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([0, 0])])
    }

    func testPredicateEvaluatesCanonicalObservationEvidence() throws {
        let snapshot = observationSnapshot(elements: [element(label: "Ready")])
        let evidence = Observation.Evidence(
            baseline: nil,
            current: snapshot,
            events: [.elementsChanged(snapshot)],
            completeness: .complete
        )
        let result = try resolved(.exists(.label("Ready"))).evaluate(in: evidence)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testExpectationResultRoundTrips() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .elementsChanged([
                .updated(.label("counter"), .value(after: "hello")),
            ]),
            actual: "counter remains outstanding"
        )
        let data = try JSONEncoder().encode(result)

        XCTAssertEqual(
            try JSONDecoder().decode(ExpectationResult.self, from: data),
            result
        )
    }

    private func resolved(
        _ predicate: AccessibilityPredicate
    ) throws -> Observation.Event.Predicate {
        try predicate.resolve(in: .empty)
    }
}

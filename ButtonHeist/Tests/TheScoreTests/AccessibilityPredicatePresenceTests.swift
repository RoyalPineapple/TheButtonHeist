import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

private typealias Fixture = AccessibilityPredicateTestFixture

final class AccessibilityPredicateTests: XCTestCase {

    // MARK: - Codable Round-Trip: presence

    func testPresentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.exists(.label("Done"))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.missing(.label("Loading"))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testContainerIdentifierEncodeDecode() throws {
        let predicate = AccessibilityPredicate.exists(.container(.identifier("checkout-container")))
        let data = try JSONEncoder().encode(predicate)
        let object = try JSONProbe(data: data)

        XCTAssertEqual(try object.string("type"), "exists")
        let checks = try object.object("target").object("container").array("checks")
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(try checks[0].string("kind"), "identifier")
        XCTAssertEqual(try checks[0].object("match").string("value"), "checkout-container")
        XCTAssertEqual(try JSONDecoder().decode(AccessibilityPredicate.self, from: data), predicate)
    }

    func testContainerIdentifierPredicatesMatchEveryContainerRole() throws {
        let cases: [(AccessibilityContainer.ContainerType, ContainerPredicateRoleFacts, String)] = [
            (.none, .none, "roleless-container"),
            (
                .scrollable(contentSize: AccessibilitySize(width: 320, height: 1_200)),
                .none,
                "checkout-scroll"
            ),
            (
                .semanticGroup(label: "Checkout", value: nil),
                .semanticGroup(label: "Checkout", value: nil),
                "checkout-group"
            ),
            (.list, .list, "checkout-list"),
            (.landmark, .landmark, "checkout-landmark"),
            (
                .dataTable(rowCount: 3, columnCount: 2, cells: []),
                .dataTable(rowCount: 3, columnCount: 2),
                "checkout-table"
            ),
            (.tabBar, .tabBar, "checkout-tabs"),
            (.series, .series, "checkout-series"),
        ]

        for (type, expectedRole, identifier) in cases {
            let facts = makeTestAccessibilityContainer(type: type, identifier: identifier).containerPredicateFacts

            XCTAssertEqual(facts.role, expectedRole)
            XCTAssertEqual(facts.identifier, identifier)
            XCTAssertTrue(try ContainerPredicate.identifier(identifier).resolve(in: .empty).matches(facts), "\(type)")
            XCTAssertFalse(try ContainerPredicate.identifier("other").resolve(in: .empty).matches(facts), "\(type)")
        }
    }

    func testContainerScrollablePredicateMatchesScrollFactIndependentOfRole() throws {
        let scrollableListFacts = makeTestAccessibilityContainer(
            type: .list,
            identifier: "orders-list",
            scrollableContentSize: AccessibilitySize(width: 320, height: 1200)
        ).containerPredicateFacts
        let plainListFacts = makeTestAccessibilityContainer(type: .list, identifier: "orders-list").containerPredicateFacts

        XCTAssertTrue(try ContainerPredicate.scrollable(true).resolve(in: .empty).matches(scrollableListFacts))
        XCTAssertTrue(
            try ContainerPredicate.matching(.type(.list), .scrollable(true)).resolve(in: .empty)
                .matches(scrollableListFacts)
        )
        XCTAssertFalse(try ContainerPredicate.scrollable(true).resolve(in: .empty).matches(plainListFacts))
    }

    func testParserScrollableContainerUsesOnlyScrollabilityFact() throws {
        let facts = makeTestAccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1_200))
        ).containerPredicateFacts

        XCTAssertEqual(facts.role, .none)
        XCTAssertTrue(try ContainerPredicate.type(.none).resolve(in: .empty).matches(facts))
        XCTAssertTrue(try ContainerPredicate.scrollable(true).resolve(in: .empty).matches(facts))
    }

    func testContainerActionPredicateMatchesCustomActionsIndependentOfRole() throws {
        let actions = [AccessibilityElement.CustomAction(name: "Archive")]
        let rolelessFacts = makeTestAccessibilityContainer(type: .none, customActions: actions).containerPredicateFacts
        let listFacts = makeTestAccessibilityContainer(type: .list, customActions: actions).containerPredicateFacts
        let plainFacts = makeTestAccessibilityContainer(type: .list).containerPredicateFacts

        XCTAssertEqual(rolelessFacts.actions, [.custom("Archive")])
        let requiredActions = ContainerPredicateActions(.custom("Archive"))
        XCTAssertTrue(try ContainerPredicate.actions(requiredActions).resolve(in: .empty).matches(rolelessFacts))
        XCTAssertTrue(
            try ContainerPredicate.matching(.type(.list), .actions(requiredActions)).resolve(in: .empty)
                .matches(listFacts)
        )
        XCTAssertFalse(try ContainerPredicate.actions(requiredActions).resolve(in: .empty).matches(plainFacts))
    }

    // MARK: - Presence Evaluation

    func testPresentMatchesAnyValueFour() throws {
        let elements = [Fixture.element(label: "Counter", value: "4")]
        let predicate = AccessibilityPredicate.exists(.value("4"))
        XCTAssertTrue(
            try predicate.resolve(in: .empty).validate(
                against: Fixture.result(success: true, trace: currentTrace(elements), completeness: .incomplete)
            ).met
        )
    }

    func testStateEvaluationReturnsPredicateLocalResult() throws {
        let predicate = AccessibilityPredicate.exists(.label("Ready"))
        let result = try predicate.resolve(in: .empty).evaluate(in: Fixture.evidence(currentTrace([
            Fixture.element(label: "Ready"),
        ])))

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
    }

    func testContainerLabelMatchesCurrentInterfaceWithoutTransition() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil), identifier: nil
            ), children: [
                testElement(Fixture.element(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate.exists(.container(.label("Checkout")))

        let result = try predicate.resolve(in: .empty).evaluate(in: Fixture.evidence(AccessibilityTrace(interface: interface)))

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
    }

    func testContainerLabelFailureReportsMissingContainer() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(Fixture.element(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate.exists(.container(.label("Checkout")))

        let result = try predicate.resolve(in: .empty).evaluate(in: Fixture.evidence(AccessibilityTrace(interface: interface)))

        XCTAssertFalse(result.met)
        XCTAssertTrue(result.actual?.contains("Checkout") == true)
    }

    func testContainerExistsAndMissingEvaluateAgainstCurrentInterface() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil),
                identifier: "checkout"
            ), children: []),
        ])
        let action = Fixture.result(success: true, trace: AccessibilityTrace(interface: interface), completeness: .incomplete)

        XCTAssertTrue(
            try AccessibilityPredicate.exists(.container(.identifier("checkout")))
                .resolve(in: .empty)
                .validate(against: action).met
        )
        XCTAssertTrue(
            try AccessibilityPredicate.missing(.container(.identifier("account")))
                .resolve(in: .empty)
                .validate(against: action).met
        )
        XCTAssertFalse(
            try AccessibilityPredicate.missing(.container(.identifier("checkout")))
                .resolve(in: .empty)
                .validate(against: action).met
        )
    }

    func testPresentNarrowsByIdentifierAndValue() throws {
        let elements = [
            Fixture.element(label: "Counter", value: "4", identifier: "slider"),
            Fixture.element(label: "Other", value: "4", identifier: "knob"),
        ]
        let matching = AccessibilityPredicate.exists(.element(.identifier("slider"), .value("4")))
        let missing = AccessibilityPredicate.exists(.element(.identifier("slider"), .value("5")))
        let action = Fixture.result(success: true, trace: currentTrace(elements), completeness: .incomplete)
        XCTAssertTrue(try matching.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try missing.resolve(in: .empty).validate(against: action).met)
    }

    func testAbsentTrueOnlyWhenNoneMatch() throws {
        let elements = [Fixture.element(label: "Ready")]
        let action = Fixture.result(success: true, trace: currentTrace(elements), completeness: .incomplete)
        XCTAssertTrue(try AccessibilityPredicate.missing(.label("Loading")).resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try AccessibilityPredicate.missing(.label("Ready")).resolve(in: .empty).validate(against: action).met)
    }

    func testAccessibilityTargetMatchGraphKeepsEqualInterfaceElementsDistinctByTreePath() throws {
        let duplicate = Fixture.element(label: "Save", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(duplicate),
                testElement(duplicate),
            ]),
        ])

        let matches = AccessibilityTargetMatchGraph(interface: interface)
            .resolve(ElementPredicate.label("Save"))

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.orderedPaths, [TreePath([0, 0]), TreePath([0, 1])])
    }

    func testPredicateResolutionIntersectsCheckMatchSets() throws {
        let elements = [
            Fixture.element(label: "Save", identifier: "primary", traits: [.button]),
            Fixture.element(label: "Save", identifier: "primary", traits: [.staticText]),
            Fixture.element(label: "Save", identifier: "secondary", traits: [.button]),
            Fixture.element(label: "Cancel", identifier: "primary", traits: [.button]),
        ]

        let graph = AccessibilityTargetMatchGraph(elements: elements)
        let predicate = try ElementPredicateTemplate(
            label: "Save",
            identifier: "primary",
            traits: [.button]
        ).resolve(in: .empty)
        let matches = graph.resolve(predicate)
        let expected = graph.resolve(ElementPredicate.label("Save"))
            .intersection(graph.resolve(ElementPredicate.identifier("primary")))
            .intersection(graph.resolve(ElementPredicate.traits([.button])))

        XCTAssertEqual(matches.elements, [elements[0]])
        XCTAssertEqual(matches, expected)
        XCTAssertEqual(matches.orderedPaths, [TreePath([0])])
    }

    func testPredicateResolutionSubtractsExcludedMatchSet() throws {
        let elements = [
            Fixture.element(label: "Coke", traits: [.staticText], actions: [.activate, .custom("Modify")]),
            Fixture.element(label: "Coke", traits: [.staticText], actions: [.custom("Sub")]),
            Fixture.element(label: "Coke", traits: [.staticText], actions: []),
            Fixture.element(label: "Sprite", traits: [.staticText], actions: [.custom("Sub")]),
        ]
        let predicate = try ElementPredicateTemplate([
            .label("Coke"),
            .exclude(.actions([.custom("Sub")])),
        ]).resolve(in: .empty)

        let matches = AccessibilityTargetMatchGraph(elements: elements).resolve(predicate)

        XCTAssertEqual(matches.elements, [elements[0], elements[2]])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0]), TreePath([2])])
    }

    func testElementMatchSetUnionUsesPathIdentityAndTraversalOrder() throws {
        let elements = [
            Fixture.element(label: "Save"),
            Fixture.element(label: "Other"),
            Fixture.element(label: "Cancel"),
        ]
        let graph = AccessibilityTargetMatchGraph(elements: elements)
        let cancelMatches = graph.resolve(ElementPredicate.label("Cancel"))
        let saveMatches = graph.resolve(ElementPredicate.label("Save"))

        XCTAssertEqual(cancelMatches.union(saveMatches).orderedPaths, [TreePath([0]), TreePath([2])])
    }

    func testAccessibilityTargetMatchGraphPreservesTraversalOrderFromMatches() throws {
        let later = AccessibilityTargetElementMatch(
            path: TreePath([9]),
            traversalOrder: 9,
            parentContainerPath: nil,
            element: Fixture.element(label: "Row", actions: [.activate])
        )
        let earlier = AccessibilityTargetElementMatch(
            path: TreePath([1]),
            traversalOrder: 1,
            parentContainerPath: nil,
            element: Fixture.element(label: "Row", actions: [.activate])
        )
        let graph = AccessibilityTargetMatchGraph(
            AccessibilityTargetMatchInput(elements: [later, earlier], containers: [])
        )

        let matches = graph.resolve(ElementPredicate.label("Row"))

        XCTAssertEqual(matches.orderedPaths, [TreePath([1]), TreePath([9])])
    }

    func testTargetOrdinalSelectsFromNarrowedMatchSet() throws {
        let elements = [
            Fixture.element(label: "Save", traits: [.button]),
            Fixture.element(label: "Save", traits: [.staticText]),
            Fixture.element(label: "Save", traits: [.button]),
        ]
        let graph = AccessibilityTargetMatchGraph(elements: elements)

        let authored = AccessibilityTarget.predicate(
            ElementPredicateTemplate(label: "Save", traits: [.button]),
            ordinal: 1
        )
        let selected = graph.resolve(try authored.resolve(in: .empty))

        XCTAssertEqual(selected.elements.elements, [elements[2]])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([2])])
        let predicate = AccessibilityPredicate.exists(
            .predicate(ElementPredicateTemplate(label: "Save", traits: [.button]), ordinal: 1)
        )
        XCTAssertTrue(
            try predicate.resolve(in: .empty).validate(
                against: Fixture.result(success: true, trace: currentTrace(elements), completeness: .incomplete)
            ).met
        )
    }

    func testTargetWithinContainerSelectsOnlyDescendants() throws {
        let pay = Fixture.element(label: "Pay", traits: [.button])
        let otherPay = Fixture.element(label: "Pay", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil), identifier: nil
            ), children: [
                testElement(pay),
            ]),
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Cart", value: nil), identifier: nil
            ), children: [
                testElement(otherPay),
            ]),
        ])

        let authored = AccessibilityTarget.within(container: .label("Checkout"), target: .label("Pay"))
        let selected = AccessibilityTargetMatchGraph(interface: interface)
            .resolve(try authored.resolve(in: .empty))

        XCTAssertEqual(selected.elements.elements, [pay])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([0, 0])])
    }

    func testStatePredicateRequiresObservedTraceForActionResultValidation() throws {
        let action = ActionResult.success(method: .activate)
        let result = try AccessibilityPredicate.missing(.label("Loading")).resolve(in: .empty).validate(against: action)

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .changed(.elements([
                .updated(.label("counter"), .value(after: "hello")),
            ])),
            actual: "counter: value: world → hell"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testExpectationResultWithNilPredicateEncodeDecode() throws {
        let result = ExpectationResult(met: true, predicate: nil, actual: "delivered")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testExpectationResultRoundTrip() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .changed(.screen()),
            actual: "noChange"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    private func currentTrace(_ elements: [HeistElement]) -> AccessibilityTrace {
        AccessibilityTrace(interface: makeTestInterface(elements: elements))
    }

}

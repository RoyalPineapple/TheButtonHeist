import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

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

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements())
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
        let elements = [makeElement(label: "Counter", value: "4")]
        let predicate = AccessibilityPredicate.exists(.value("4"))
        XCTAssertTrue(
            try predicate.resolve(in: .empty).validate(
                against: makeResult(success: true, trace: currentTrace(elements), completeness: .incomplete)
            ).met
        )
    }

    func testStateEvaluationReturnsPredicateLocalResult() throws {
        let predicate = AccessibilityPredicate.exists(.label("Ready"))
        let result = try predicate.resolve(in: .empty).evaluate(in: makeEvidence(currentTrace([makeElement(label: "Ready")])))

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
    }

    func testContainerLabelMatchesCurrentInterfaceWithoutTransition() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil), identifier: nil
            ), children: [
                testElement(makeElement(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate.exists(.container(.label("Checkout")))

        let result = try predicate.resolve(in: .empty).evaluate(in: makeEvidence(AccessibilityTrace(interface: interface)))

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
    }

    func testContainerLabelFailureReportsMissingContainer() throws {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(makeElement(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate.exists(.container(.label("Checkout")))

        let result = try predicate.resolve(in: .empty).evaluate(in: makeEvidence(AccessibilityTrace(interface: interface)))

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
        let action = makeResult(success: true, trace: AccessibilityTrace(interface: interface), completeness: .incomplete)

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
            makeElement(label: "Counter", value: "4", identifier: "slider"),
            makeElement(label: "Other", value: "4", identifier: "knob"),
        ]
        let matching = AccessibilityPredicate.exists(.element(.identifier("slider"), .value("4")))
        let missing = AccessibilityPredicate.exists(.element(.identifier("slider"), .value("5")))
        let action = makeResult(success: true, trace: currentTrace(elements), completeness: .incomplete)
        XCTAssertTrue(try matching.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try missing.resolve(in: .empty).validate(against: action).met)
    }

    func testAbsentTrueOnlyWhenNoneMatch() throws {
        let elements = [makeElement(label: "Ready")]
        let action = makeResult(success: true, trace: currentTrace(elements), completeness: .incomplete)
        XCTAssertTrue(try AccessibilityPredicate.missing(.label("Loading")).resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try AccessibilityPredicate.missing(.label("Ready")).resolve(in: .empty).validate(against: action).met)
    }

    func testAccessibilityTargetMatchGraphKeepsEqualInterfaceElementsDistinctByTreePath() throws {
        let duplicate = makeElement(label: "Save", traits: [.button])
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
            makeElement(label: "Save", identifier: "primary", traits: [.button]),
            makeElement(label: "Save", identifier: "primary", traits: [.staticText]),
            makeElement(label: "Save", identifier: "secondary", traits: [.button]),
            makeElement(label: "Cancel", identifier: "primary", traits: [.button]),
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
            makeElement(label: "Coke", traits: [.staticText], actions: [.activate, .custom("Modify")]),
            makeElement(label: "Coke", traits: [.staticText], actions: [.custom("Sub")]),
            makeElement(label: "Coke", traits: [.staticText], actions: []),
            makeElement(label: "Sprite", traits: [.staticText], actions: [.custom("Sub")]),
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
            makeElement(label: "Save"),
            makeElement(label: "Other"),
            makeElement(label: "Cancel"),
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
            element: makeElement(label: "Row", actions: [.activate])
        )
        let earlier = AccessibilityTargetElementMatch(
            path: TreePath([1]),
            traversalOrder: 1,
            parentContainerPath: nil,
            element: makeElement(label: "Row", actions: [.activate])
        )
        let graph = AccessibilityTargetMatchGraph(
            AccessibilityTargetMatchInput(elements: [later, earlier], containers: [])
        )

        let matches = graph.resolve(ElementPredicate.label("Row"))

        XCTAssertEqual(matches.orderedPaths, [TreePath([1]), TreePath([9])])
    }

    func testTargetOrdinalSelectsFromNarrowedMatchSet() throws {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
            makeElement(label: "Save", traits: [.staticText]),
            makeElement(label: "Save", traits: [.button]),
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
                against: makeResult(success: true, trace: currentTrace(elements), completeness: .incomplete)
            ).met
        )
    }

    func testTargetWithinContainerSelectsOnlyDescendants() throws {
        let pay = makeElement(label: "Pay", traits: [.button])
        let otherPay = makeElement(label: "Pay", traits: [.button])
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

    // MARK: - Validation: screen changed

    func testScreenChangedMetWhenTraceChangesScreen() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = makeResult(success: true, trace: .screenChangedForTests(replacementInterface: interface), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenTraceOnlyChangesElements() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWithoutTrace() throws {
        let action = makeResult(success: true)
        let result = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testScreenChangedUsesTraceEndpointProjection() throws {
        let before = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let after = makeTestInterface(elements: [
            HeistElement(
                description: "Settings",
                label: "Settings",
                value: nil,
                identifier: nil,
                traits: [.header],
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            ),
        ])
        let first = AccessibilityTrace.Capture(
            sequence: 1,
            interface: before,
            context: AccessibilityTrace.Context(screenId: "home")
        )
        let last = AccessibilityTrace.Capture(
            sequence: 2,
            interface: after,
            parentHash: first.hash,
            context: AccessibilityTrace.Context(screenId: "settings"),
            transition: screenChangedTransition()
        )
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    AccessibilityTrace(captures: [first, last]),
                    completeness: .incomplete
                ))

        )

        let outcome = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertNil(outcome.actual)
    }

    func testScreenAssertionsUseCurrentReplacementInterface() throws {
        let trace = screenTrace(
            before: makeTestInterface(elements: [makeElement(label: "Home")]),
            after: makeTestInterface(elements: [makeElement(label: "Settings")])
        )
        let predicate = AccessibilityPredicate.changed(.screen([
            .exists(.label("Settings")),
            .missing(.label("Home")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: makeResult(success: true, trace: trace, completeness: .incomplete)).met)
    }

    func testScreenDepartureAndArrivalSatisfyElementLifecycleAssertions() throws {
        let trace = screenTrace(
            before: makeTestInterface(elements: [makeElement(label: "Home")]),
            after: makeTestInterface(elements: [makeElement(label: "Settings")])
        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .disappeared(.label("Home")),
            .appeared(.label("Settings")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: makeResult(success: true, trace: trace, completeness: .incomplete)).met)
    }

    func testIdenticalTargetCanDisappearAndReappearAcrossScreenBoundary() throws {
        let shared = makeElement(label: "Continue", traits: [.button])
        let trace = screenTrace(
            before: makeTestInterface(elements: [shared]),
            after: makeTestInterface(elements: [shared])
        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .disappeared(.label("Continue")),
            .appeared(.label("Continue")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: makeResult(success: true, trace: trace, completeness: .incomplete)).met)
    }

    func testUpdatedOnlyMatchesSameScreenElementFacts() throws {
        let before = makeTestInterface(elements: [makeElement(label: "Count", value: "1")])
        let after = makeTestInterface(elements: [makeElement(label: "Count", value: "2")])
        let sameScreen = AccessibilityTrace(first: before).appending(after)
        let screenBoundary = screenTrace(before: before, after: after)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Count"), .value(before: "1", after: "2")),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: makeResult(success: true, trace: sameScreen, completeness: .incomplete)).met)
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: makeResult(success: true, trace: screenBoundary, completeness: .incomplete)).met)
    }

    func testNotificationOnlyFactSatisfiesGenericElementsChange() throws {
        let interface = makeTestInterface(elements: [makeElement(label: "Status")])
        let notification = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .none,
            associatedElement: .none
        )
        let trace = AccessibilityTrace(first: interface).appending(
            interface,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [notification])
        )

        XCTAssertTrue(
            try AccessibilityPredicate.changed(.elements())
                .resolve(in: .empty)
                .validate(against: makeResult(success: true, trace: trace, completeness: .incomplete)).met
        )
    }

    func testNoChangeRequiresCompleteFactFreeWindow() throws {
        let interface = makeTestInterface(elements: [makeElement(label: "Ready")])
        let factFreeTrace = AccessibilityTrace(first: interface).appending(interface)
        let changed = AccessibilityTrace(first: interface).appending(
            makeTestInterface(elements: [makeElement(label: "Done")])
        )
        let predicate = AccessibilityPredicate.noChange

        let incompleteResult = try predicate.resolve(in: .empty).validate(against: makeResult(
            success: true,
            trace: factFreeTrace,
            completeness: .incomplete
        ))
        XCTAssertFalse(incompleteResult.met)
        XCTAssertEqual(incompleteResult.actual, "observation history incomplete")
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: makeResult(
            success: true,
            trace: factFreeTrace,
            completeness: .complete
        )).met)
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: makeResult(
            success: true,
            trace: changed,
            completeness: .complete
        )).met)

        let explicitlyIncomplete = ActionResult.success(
            method: .syntheticTap,
                observation: .settledTrace(
                    traceEvidence(factFreeTrace, completeness: .incomplete),
                    .settled(duration: 0)
                )

        )
        let explicitlyIncompleteResult = try predicate.resolve(in: .empty).validate(against: explicitlyIncomplete)
        XCTAssertFalse(explicitlyIncompleteResult.met)
        XCTAssertEqual(explicitlyIncompleteResult.actual, "observation history incomplete")
    }

    func testActionResultValidationUsesAccumulatedTraceEvidence() throws {
        let baseline = makeTestInterface(elements: [
            makeElement(label: "Counter", value: "0"),
        ])
        let updated = makeTestInterface(elements: [
            makeElement(label: "Counter", value: "1"),
        ])
        let final = makeTestInterface(elements: [
            makeElement(label: "Counter", value: "0"),
        ])
        let trace = AccessibilityTrace(first: baseline)
            .appending(updated)
            .appending(final)

        XCTAssertEqual(trace.changeFacts.map(\.kind), [.elementsChanged, .elementsChanged])

        let action = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(trace, completeness: .incomplete))

        )
        let changePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(before: "0", after: "1")),
        ]))

        XCTAssertTrue(try changePredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try AccessibilityPredicate.noChange.resolve(in: .empty).validate(against: action).met)
    }

    func testScreenChangedRequiresTraceEndpointEdge() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    AccessibilityTrace(interface: Interface(
                        timestamp: Date(timeIntervalSince1970: 0),
                        tree: []
                    )),
                    completeness: .incomplete
                ))

        )

        let outcome = try AccessibilityPredicate.changed(.screen()).resolve(in: .empty).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noChange")
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenTraceChangesElements() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenTraceHasNoChange() throws {
        let action = makeResult(success: true, trace: .noChangeForTests(elementCount: 5), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedMetForScreenDepartureAndArrivalFacts() throws {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = makeResult(success: true, trace: .screenChangedForTests(replacementInterface: interface), completeness: .incomplete)
        let result = try AccessibilityPredicate.changed(.elements()).resolve(in: .empty).validate(against: action)
        XCTAssertTrue(result.met)
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(before: "3", after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedRequiresTargetAndPropertyAtEncodeBoundary() throws {
        let stale = Data(#"{"type":"updated","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"counter"}}]}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ChangeDeclaration.ElementAssertion.self, from: stale)
        )
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedPassReportsObservedPropertyProof() throws {
        let trace = try makeUpdateTrace(label: "Quantity", property: .value, old: "2", new: "3")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Quantity"), .value(before: "2", after: "3")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testElementUpdatedDoesNotPassWhenCurrentValueAlreadyMatchedWithoutChangeEvidence() throws {
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Quantity"), .value(before: "3", after: "3")),
        ]))
        let trace = AccessibilityTrace.noChangeForTests(elementCount: 1)
        let result = try predicate.resolve(in: .empty).evaluate(in: makeEvidence(trace))

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementUpdatedNotMetWhenNoMatch() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            try makeUpdate(label: "Other", property: .value, old: "1", new: "5"),
            try makeUpdate(label: "Counter", property: .value, old: "3", new: "5"),
        ]))
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() throws {
        let trace = try makeUpdateTrace(label: "Other", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(before: "3", after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForOldAndNewValues() throws {
        let trace = try makeUpdateTrace(label: "cart", property: .value, old: "cart: empty", new: "3 items")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("cart"), .value(before: .prefix("cart:"), after: .suffix("items"))),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForEveryModeAcrossBeforeAndAfter() throws {
        let trace = try makeUpdateTrace(
            label: "Search Field",
            property: .value,
            old: "Search for tea",
            new: "John Smith"
        )
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let changes: [ElementPropertyChange] = [
            .value(before: .exact("Search for tea"), after: .exact("John Smith")),
            .value(before: .contains("for"), after: .contains("Smith")),
            .value(before: .prefix("Search"), after: .prefix("John")),
            .value(before: .suffix("tea"), after: .suffix("Smith")),
        ]

        for change in changes {
            let predicate = AccessibilityPredicate.changed(.elements([
                .updated(.label("Search Field"), change),
            ]))
            XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
        }
    }

    func testElementUpdatedMatchesTraitGainAndLossAcrossBeforeAndAfter() throws {
        let gained = try makeTraitUpdate(label: "Favorites", beforeTraits: [.button], afterTraits: [.button, .selected])
        let lost = try makeTraitUpdate(label: "Disabled", beforeTraits: [.button, .notEnabled], afterTraits: [.button])
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(elementCount: 2, edits: ElementEdits(updated: [gained, lost])),
            completeness: .incomplete
        )

        let selectedGain = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Favorites"),
                .traits(before: .init(exclude: [.selected]), after: .init(include: [.selected]))
            ),
        ]))
        let enabledLoss = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Disabled"),
                .traits(before: .init(include: [.notEnabled]), after: .init(exclude: [.notEnabled]))
            ),
        ]))

        XCTAssertTrue(try selectedGain.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try enabledLoss.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedActionChecker() throws {
        let update = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Stepper", actions: [.increment]),
            new: makeElement(label: "Stepper", actions: [.increment, .activate])
        ))
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(elementCount: 1, edits: ElementEdits(updated: [update])),
            completeness: .incomplete
        )

        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Stepper"),
                .actions(
                    before: ActionSetMatch(exclude: Set<ElementAction>([.activate])),
                    after: ActionSetMatch(include: Set<ElementAction>([.activate]))
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(.label("Stepper"), .actions(after: ActionSetMatch(exclude: [.activate]))),
        ]))

        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedGeometryCheckers() throws {
        let frameUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Card", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44),
            new: makeElement(label: "Card", frameX: 12, frameY: 20, frameWidth: 120, frameHeight: 44)
        ))
        let pointUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Knob", activationPointEvidence: .explicit(ScreenPoint(x: 10, y: 12))),
            new: makeElement(label: "Knob", activationPointEvidence: .explicit(ScreenPoint(x: 42, y: 64)))
        ))
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(
                elementCount: 2,
                edits: ElementEdits(updated: [frameUpdate, pointUpdate])
            ),
            completeness: .incomplete
        )

        let framePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 12, y: 20, width: 120, height: 44))),
        ]))
        let pointPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Knob"), .activationPoint(after: ElementPointMatch(x: 42, y: 64))),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 13))),
        ]))

        XCTAssertTrue(try framePredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try pointPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedCustomContentAndRotorCheckers() throws {
        let customContent = HeistCustomContent(label: "Status", value: "Ready to submit", isImportant: true)
        let customUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Form", customContent: [HeistCustomContent(label: "Help", value: "Optional", isImportant: false)]),
            new: makeElement(label: "Form", customContent: [customContent])
        ))
        let rotorUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Article", rotors: [HeistRotor(name: "Links")]),
            new: makeElement(label: "Article", rotors: [HeistRotor(name: "Headings"), HeistRotor(name: "Links")])
        ))
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(
                elementCount: 2,
                edits: ElementEdits(updated: [customUpdate, rotorUpdate])
            ),
            completeness: .incomplete
        )

        let customPredicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch.exact("Status"),
                    value: StringMatch.contains("Ready"),
                    isImportant: true
                ))
            ),
        ]))
        let rotorPredicate = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Article"),
                .rotors(
                    before: RotorSetMatch(exclude: [StringMatch.exact("Headings")]),
                    after: RotorSetMatch(include: [StringMatch.contains("Head")])
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch.exact("Status"),
                    isImportant: false
                ))
            ),
        ]))

        XCTAssertTrue(try customPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertTrue(try rotorPredicate.resolve(in: .empty).validate(against: action).met)
        XCTAssertFalse(try mismatch.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedRejectsBeforeAfterWithoutPropertyAtDecodeBoundary() throws {
        let json = Data("""
        {
          "type": "changed",
          "scope": "elements",
          "assertions": [
            {
              "type": "updated",
              "target": {"checks":[{"kind":"label","match":{"mode":"exact","value":"Card"}}]},
              "after": { "x": 1 }
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "property")
            XCTAssertTrue(context.debugDescription.contains("before/after require property"))
        }
    }

    func testElementUpdatedRejectsStringCheckersForNonTextPropertiesAtDecodeBoundary() throws {
        let cases = [
            ("traits", "Unknown trait set match field"),
            ("actions", "Unknown action set match field"),
            ("frame", "Unknown frame match field"),
            ("activationPoint", "Unknown activation point match field"),
            ("customContent", "Unknown custom content match field"),
            ("rotors", "Unknown rotor set match field"),
        ]
        for (property, expectedMessage) in cases {
            assertAccessibilityPredicateDecodeFails(
                """
                {
                  "type": "changed",
                  "scope": "elements",
                  "assertions": [
                    {
                      "type": "updated",
                      "target": {"checks":[{"kind":"label","match":{"mode":"exact","value":"Subject"}}]},
                      "property": "\(property)",
                      "after": { "mode": "exact", "value": "activate" }
                    }
                  ]
                }
                """,
                contains: expectedMessage,
                "\(property) accepted a string-match-shaped update checker"
            )
        }
    }

    func testElementUpdatedRejectsElementMatcherFieldsInsideTypedCheckerObjects() throws {
        let cases = [
            ("traits", #"Unknown trait set match field "label""#),
            ("frame", #"Unknown frame match field "label""#),
        ]
        for (property, expectedMessage) in cases {
            assertAccessibilityPredicateDecodeFails(
                """
                {
                  "type": "changed",
                  "scope": "elements",
                  "assertions": [
                    {
                      "type": "updated",
                      "target": {"checks":[{"kind":"label","match":{"mode":"exact","value":"Subject"}}]},
                      "property": "\(property)",
                      "after": {
                        "label": { "mode": "exact", "value": "Save" }
                      }
                    }
                  ]
                }
                """,
                contains: expectedMessage,
                "\(property) accepted an element-matcher field inside its checker object"
            )
        }
    }

    func testElementUpdatedRejectsUnknownNestedCheckerKeysAtDecodeBoundary() throws {
        assertAccessibilityPredicateDecodeFails(
            """
            {
              "type": "changed",
              "scope": "elements",
              "assertions": [
                {
                  "type": "updated",
                  "target": {"checks":[{"kind":"label","match":{"mode":"exact","value":"Card"}}]},
                  "property": "frame",
                  "after": { "x": 1, "unexpected": true }
                }
              ]
            }
            """,
            contains: #"Unknown frame match field "unexpected""#
        )
    }

    func testElementUpdatedWithPropertyOnlyMetWhenTargetUpdates() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "a", new: "b")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value()),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedNotMetWithoutTrace() throws {
        let action = makeResult(success: true)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits())
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no matching element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() throws {
        let trace = try makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = try predicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 10, edits: ElementEdits(updated: [
            try makeUpdate(label: "label", property: .value, old: "A", new: "B"),
            try makeUpdate(label: "counter", property: .value, old: "3", new: "5"),
        ]))
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() throws {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(
                before: makeElement(label: "Toggle", traits: [.button]),
                after: makeElement(label: "Toggle", value: "5", traits: [.button, .selected]),
                changes: [
                    try XCTUnwrap(PropertyChange.traits(old: [.button], new: [.button, .selected])),
                    try XCTUnwrap(PropertyChange.value(old: "3", new: "5")),
                ]
            ),
        ]))
        let action = makeResult(success: true, trace: trace, completeness: .incomplete)
        let traitsPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .traits()),
        ]))
        let traitsResult = try traitsPredicate.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valuePredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .value(after: "5")),
        ]))
        let valueResult = try valuePredicate.resolve(in: .empty).validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintPredicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("Toggle"), .hint()),
        ]))
        let hintResult = try hintPredicate.resolve(in: .empty).validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "btn_1", property: .value, old: "OFF", new: "ON"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("btn_1"), .value(before: "OFF", after: "ON")),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testElementUpdatedPropertyOnly() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "any", property: .value, old: "A", new: "B"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(elementCount: 5, edits: ElementEdits()),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        let outcome = try predicate.resolve(in: .empty).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no matching element updates")
    }

    func testElementUpdatedPropertyMismatch() throws {
        let result = ActionResult.success(
            method: .activate,
                observation: .trace(traceEvidence(
                    .elementsChangedForTests(
                        elementCount: 5,
                        edits: ElementEdits(updated: [
                            try makeUpdate(label: "btn_1", property: .hint, old: "A", new: "B"),
                        ])
                    ),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.changed(.elements([
            .updated(.label("btn_1"), .value()),
        ]))
        XCTAssertFalse(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    // MARK: - final state predicates

    func testPresentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.exists(.element(.label("New Task"), traits: [.staticText]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testPresentMetAgainstFinalInterface() throws {
        let newElement = makeElement(label: "No receipt", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.exists(.label("No receipt"))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testPresentNotMetAgainstFinalInterfaceWhenAbsent() throws {
        let otherElement = makeElement(label: "New sale", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.exists(.label("No receipt"))
        let outcome = try predicate.resolve(in: .empty).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("No receipt") == true)
    }

    func testAbsentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.missing(.element(.label("Old Item"), traits: [.button]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentMetAgainstFinalInterface() throws {
        let newElement = makeElement(label: "Done", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.missing(.label("Recording payment"))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testAbsentNotMetAgainstFinalInterfaceWhenStillPresent() throws {
        let sameElement = makeElement(label: "Header", traits: [.header])
        let replacementInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.missing(.label("Header"))
        let outcome = try predicate.resolve(in: .empty).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("Header") == true)
    }

    // MARK: - Round-trip across cases

    func testAccessibilityPredicateRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .exists(.label("Done")),
            .missing(.label("Loading")),
            .changed(.screen()),
            .changed(.elements()),
            .changed(.elements([
                .updated(.label("btn"), .value(before: "A", after: "B")),
            ])),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for predicate in predicates {
            let data = try encoder.encode(predicate)
            let decoded = try decoder.decode(AccessibilityPredicate.self, from: data)
            XCTAssertEqual(decoded, predicate)
        }
    }

    // MARK: - Decode Errors

    func testDecodeRejectsUnknownType() throws {
        let json = Data(#"{"type": "rainbow"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected .dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("rainbow"))
        }
    }

    func testDecodeRejectsMissingType() throws {
        let json = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json))
    }

    func testRemovedElementTransitionPredicatesRejectAtCodableBoundary() throws {
        let json = Data(#"{"type":"appeared","element":{"label":"Save"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("appeared"), "\(error)")
        }
    }

    func testRemovedAllStateRejectsAtCodableBoundary() throws {
        let json = Data(#"{"type":"all","states":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("all"), "\(error)")
        }
    }

    func testRemovedCombinedChangeScopeRejectsAtCodableBoundary() throws {
        let json = Data(#"{"type":"change","scopes":[{"type":"all","scopes":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("change"), "\(error)")
        }
    }

    func testRemovedNestedChangeScopeRejectsAtCodableBoundary() throws {
        let json = Data(#"{"type":"change","scopes":[{"type":"change"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("change"), "\(error)")
        }
    }

    // MARK: - Helpers

    private func assertAccessibilityPredicateDecodeFails(
        _ json: String,
        contains expectedMessage: String,
        _ failureMessage: String = "Expected decode to fail",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityPredicate.self, from: Data(json.utf8)),
            failureMessage,
            file: file,
            line: line
        ) { error in
            let message = decodingFailureMessage(error)
            XCTAssertTrue(
                message.contains(expectedMessage),
                "Expected error containing \(expectedMessage), got \(message)",
                file: file,
                line: line
            )
        }
    }

    private func decodingFailureMessage(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context),
             DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context):
            return context.debugDescription
        default:
            return String(describing: error)
        }
    }

    private func makeElement(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointEvidence: ActivationPointEvidence? = nil,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        makeTestHeistElement(
            description: label ?? "",
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointEvidence: activationPointEvidence,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

    private func makeUpdateTrace(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        elementCount: Int = 5
    ) throws -> AccessibilityTrace {
        .elementsChangedForTests(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                try makeUpdate(label: label, property: property, old: old, new: new),
            ])
        )
    }

    private func makeUpdate(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait] = [],
        afterTraits: [HeistTrait] = []
    ) throws -> ElementUpdate {
        ElementUpdate(
            before: makeElementForUpdate(label: label, property: property, value: old, traits: beforeTraits),
            after: makeElementForUpdate(label: label, property: property, value: new, traits: afterTraits),
            changes: [try propertyChange(
                property: property,
                old: old,
                new: new,
                beforeTraits: beforeTraits,
                afterTraits: afterTraits
            )]
        )
    }

    private func makeTraitUpdate(
        label: String,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) throws -> ElementUpdate {
        ElementUpdate(
            before: makeElement(label: label, traits: beforeTraits),
            after: makeElement(label: label, traits: afterTraits),
            changes: [
                try XCTUnwrap(PropertyChange.traits(old: beforeTraits, new: afterTraits)),
            ]
        )
    }

    private func propertyChange(
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) throws -> PropertyChange {
        switch property {
        case .label:
            return try XCTUnwrap(PropertyChange.label(old: old, new: new))
        case .identifier:
            return try XCTUnwrap(PropertyChange.identifier(old: old, new: new))
        case .value:
            return try XCTUnwrap(PropertyChange.value(old: old, new: new))
        case .hint:
            return try XCTUnwrap(PropertyChange.hint(old: old, new: new))
        case .traits:
            return try XCTUnwrap(PropertyChange.traits(old: beforeTraits, new: afterTraits))
        case .actions, .frame, .activationPoint, .customContent, .rotors:
            fatalError("Unsupported test property \(property)")
        }
    }

    private func makeElementForUpdate(
        label: String,
        property: ElementProperty,
        value: String?,
        traits: [HeistTrait]
    ) -> HeistElement {
        switch property {
        case .label:
            return makeElement(label: value ?? label, traits: traits)
        case .identifier:
            return makeElement(label: label, identifier: value, traits: traits)
        case .value:
            return makeElement(label: label, value: value, traits: traits)
        case .traits:
            return makeElement(label: label, traits: traits)
        case .hint:
            return makeElement(label: label, hint: value, traits: traits)
        default:
            return makeElement(label: label, value: value, traits: traits)
        }
    }

    private func makeResult(
        success: Bool,
        message: String? = nil
    ) -> ActionResult {
        makeResult(success: success, message: message, observation: .none)
    }

    private func makeResult(
        success: Bool,
        message: String? = nil,
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> ActionResult {
        makeResult(
            success: success,
            message: message,
            observation: .trace(traceEvidence(trace, completeness: completeness))
        )
    }

    private func makeResult(
        success: Bool,
        message: String?,
        observation: ActionResultObservationEvidence
    ) -> ActionResult {
        if success {
            return ActionResult.success(
                method: .syntheticTap,
                message: message,
                observation: observation
            )
        }
        return ActionResult.failure(
            method: .syntheticTap,
            errorKind: .actionFailed,
            message: message,
            observation: observation
        )
    }

    private func traceEvidence(
        _ trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(trace: trace, completeness: completeness) else {
            preconditionFailure("test trace evidence requires a current capture")
        }
        return evidence
    }

    private func currentTrace(_ elements: [HeistElement]) -> AccessibilityTrace {
        AccessibilityTrace(interface: makeTestInterface(elements: elements))
    }

    private func screenTrace(before: Interface, after: Interface) -> AccessibilityTrace {
        AccessibilityTrace(
            capture: AccessibilityTrace.Capture(
                sequence: 1,
                interface: before,
                context: AccessibilityTrace.Context(screenId: "before")
            )
        ).appending(
            after,
            context: AccessibilityTrace.Context(screenId: "after"),
            transition: screenChangedTransition()
        )
    }

    private func screenChangedTransition() -> AccessibilityTrace.Transition {
        AccessibilityTrace.Transition(accessibilityNotifications: [
            AccessibilityNotificationEvidence(
                sequence: 1,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 1),
                notificationData: .none,
                associatedElement: .none
            ),
        ])
    }

    private func makeEvidence(_ trace: AccessibilityTrace) -> AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(trace: trace, completeness: .complete) else {
            preconditionFailure("test trace requires at least one capture")
        }
        return evidence
    }
}

import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

final class AccessibilityPredicateTests: XCTestCase {

    // MARK: - Codable Round-Trip: presence

    func testPresentEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.missing(.label("Loading"))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testContainerSemanticIdentifierEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.container(.identifier("checkout-container")))
        let data = try JSONEncoder().encode(predicate)
        let object = try JSONProbe(data: data)

        XCTAssertEqual(try object.string("type"), "exists")
        let checks = try object.object("target").object("container").array("checks")
        XCTAssertEqual(checks.count, 1)
        XCTAssertEqual(try checks[0].string("kind"), "semantic")
        let semantic = try checks[0].object("semantic")
        XCTAssertEqual(try semantic.string("kind"), "identifier")
        XCTAssertEqual(try semantic.object("match").string("value"), "checkout-container")
        XCTAssertEqual(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data), predicate)
    }

    func testContainerIdentifierPredicatesMatchEveryContainerRole() {
        let cases: [(AccessibilityContainer.ContainerType, String)] = [
            (.none, "roleless-container"),
            (.semanticGroup(label: "Checkout", value: nil), "checkout-group"),
            (.list, "checkout-list"),
            (.landmark, "checkout-landmark"),
            (.dataTable(rowCount: 3, columnCount: 2, cells: []), "checkout-table"),
            (.tabBar, "checkout-tabs"),
        ]

        for (type, identifier) in cases {
            let facts = makeTestAccessibilityContainer(type: type, identifier: identifier).containerPredicateFacts

            XCTAssertEqual(facts.identifier, identifier)
            XCTAssertTrue(ContainerPredicate.identifier(identifier).matches(facts), "\(type)")
            XCTAssertFalse(ContainerPredicate.identifier("other").matches(facts), "\(type)")
        }
    }

    func testContainerScrollablePredicateMatchesScrollFactIndependentOfRole() {
        let scrollableListFacts = makeTestAccessibilityContainer(
            type: .list,
            identifier: "orders-list",
            scrollableContentSize: AccessibilitySize(width: 320, height: 1200)
        ).containerPredicateFacts
        let plainListFacts = makeTestAccessibilityContainer(type: .list, identifier: "orders-list").containerPredicateFacts

        XCTAssertTrue(ContainerPredicate.scrollable.matches(scrollableListFacts))
        XCTAssertTrue(ContainerPredicate.matching(.type(.list), .scrollable(true)).matches(scrollableListFacts))
        XCTAssertFalse(ContainerPredicate.scrollable.matches(plainListFacts))
    }

    func testParserScrollableContainerPreservesDistinctPublicKind() {
        let facts = makeTestAccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(width: 320, height: 1_200))
        ).containerPredicateFacts

        XCTAssertEqual(facts.type, AccessibilityContainerKind.scrollable)
        XCTAssertTrue(ContainerPredicate.type(.scrollable).matches(facts))
        XCTAssertFalse(ContainerPredicate.none.matches(facts))
    }

    func testContainerActionPredicateMatchesCustomActionsIndependentOfRole() {
        let actions = [AccessibilityElement.CustomAction(name: "Archive")]
        let rolelessFacts = makeTestAccessibilityContainer(type: .none, customActions: actions).containerPredicateFacts
        let listFacts = makeTestAccessibilityContainer(type: .list, customActions: actions).containerPredicateFacts
        let plainFacts = makeTestAccessibilityContainer(type: .list).containerPredicateFacts

        XCTAssertEqual(rolelessFacts.actions, [.custom("Archive")])
        XCTAssertTrue(ContainerPredicate.actions([.custom("Archive")]).matches(rolelessFacts))
        XCTAssertTrue(ContainerPredicate.matching(.type(.list), .actions([.custom("Archive")])).matches(listFacts))
        XCTAssertFalse(ContainerPredicate.actions([.custom("Archive")]).matches(plainFacts))
    }

    // MARK: - Presence Evaluation

    func testPresentMatchesAnyValueFour() {
        let elements = [makeElement(label: "Counter", value: "4")]
        let predicate = AccessibilityPredicate<RootContext>.exists(.value("4"))
        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: currentTrace(elements))).met)
    }

    func testStateEvaluationReturnsNamedResult() {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Ready"))
        let result = predicate.evaluate(in: makeEvidence(currentTrace([makeElement(label: "Ready")])))

        XCTAssertEqual(result, ExpectationResult(met: true, predicate: predicate))
    }

    func testContainerLabelMatchesCurrentInterfaceWithoutTransition() {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil), identifier: nil
            ), children: [
                testElement(makeElement(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate<RootContext>.exists(.container(.label("Checkout")))

        let result = predicate.evaluate(in: makeEvidence(AccessibilityTrace(interface: interface)))

        XCTAssertEqual(result, ExpectationResult(met: true, predicate: predicate))
    }

    func testContainerLabelFailureReportsMissingContainer() {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(makeElement(label: "Pay", traits: [.button])),
            ]),
        ])
        let predicate = AccessibilityPredicate<RootContext>.exists(.container(.label("Checkout")))

        let result = predicate.evaluate(in: makeEvidence(AccessibilityTrace(interface: interface)))

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.predicate, predicate)
        XCTAssertTrue(result.actual?.contains("Checkout") == true)
    }

    func testContainerExistsAndMissingEvaluateAgainstCurrentInterface() {
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(
                type: .semanticGroup(label: "Checkout", value: nil),
                identifier: "checkout"
            ), children: []),
        ])
        let action = makeResult(success: true, trace: AccessibilityTrace(interface: interface))

        XCTAssertTrue(
            AccessibilityPredicate<RootContext>.exists(.container(.identifier("checkout")))
                .validate(against: action).met
        )
        XCTAssertTrue(
            AccessibilityPredicate<RootContext>.missing(.container(.identifier("account")))
                .validate(against: action).met
        )
        XCTAssertFalse(
            AccessibilityPredicate<RootContext>.missing(.container(.identifier("checkout")))
                .validate(against: action).met
        )
    }

    func testPresentNarrowsByIdentifierAndValue() {
        let elements = [
            makeElement(label: "Counter", value: "4", identifier: "slider"),
            makeElement(label: "Other", value: "4", identifier: "knob"),
        ]
        let matching = AccessibilityPredicate<RootContext>.exists(.element(.identifier("slider"), .value("4")))
        let missing = AccessibilityPredicate<RootContext>.exists(.element(.identifier("slider"), .value("5")))
        let action = makeResult(success: true, trace: currentTrace(elements))
        XCTAssertTrue(matching.validate(against: action).met)
        XCTAssertFalse(missing.validate(against: action).met)
    }

    func testAbsentTrueOnlyWhenNoneMatch() {
        let elements = [makeElement(label: "Ready")]
        let action = makeResult(success: true, trace: currentTrace(elements))
        XCTAssertTrue(AccessibilityPredicate<RootContext>.missing(.label("Loading")).validate(against: action).met)
        XCTAssertFalse(AccessibilityPredicate<RootContext>.missing(.label("Ready")).validate(against: action).met)
    }

    func testElementMatchGraphKeepsEqualInterfaceElementsDistinctByTreePath() {
        let duplicate = makeElement(label: "Save", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(duplicate),
                testElement(duplicate),
            ]),
        ])

        let matches = ElementMatchGraph(interface: interface)
            .resolve(ElementPredicate(label: "Save"))

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.orderedPaths, [TreePath([0, 0]), TreePath([0, 1])])
    }

    func testPredicateResolutionIntersectsCheckMatchSets() {
        let elements = [
            makeElement(label: "Save", identifier: "primary", traits: [.button]),
            makeElement(label: "Save", identifier: "primary", traits: [.staticText]),
            makeElement(label: "Save", identifier: "secondary", traits: [.button]),
            makeElement(label: "Cancel", identifier: "primary", traits: [.button]),
        ]

        let graph = ElementMatchGraph(elements: elements)
        let matches = graph.resolve(ElementPredicate(label: "Save", identifier: "primary", traits: [.button]))
        let expected = graph.resolve(ElementPredicate(label: "Save"))
            .intersection(graph.resolve(ElementPredicate(identifier: "primary")))
            .intersection(graph.resolve(ElementPredicate(traits: [.button])))

        XCTAssertEqual(matches.elements, [elements[0]])
        XCTAssertEqual(matches, expected)
        XCTAssertEqual(matches.orderedPaths, [TreePath([0])])
    }

    func testPredicateResolutionSubtractsExcludedMatchSet() {
        let elements = [
            makeElement(label: "Coke", traits: [.staticText], actions: [.activate, .custom("Modify")]),
            makeElement(label: "Coke", traits: [.staticText], actions: [.custom("Sub")]),
            makeElement(label: "Coke", traits: [.staticText], actions: []),
            makeElement(label: "Sprite", traits: [.staticText], actions: [.custom("Sub")]),
        ]
        let predicate = ElementPredicate([
            .label("Coke"),
            .exclude(.actions([.custom("Sub")])),
        ])

        let matches = ElementMatchGraph(elements: elements).resolve(predicate)

        XCTAssertEqual(matches.elements, [elements[0], elements[2]])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0]), TreePath([2])])
    }

    func testElementMatchSetUnionUsesPathIdentityAndTraversalOrder() {
        let elements = [
            makeElement(label: "Save"),
            makeElement(label: "Other"),
            makeElement(label: "Cancel"),
        ]
        let graph = ElementMatchGraph(elements: elements)
        let cancelMatches = graph.resolve(ElementPredicate(label: "Cancel"))
        let saveMatches = graph.resolve(ElementPredicate(label: "Save"))

        XCTAssertEqual(cancelMatches.union(saveMatches).orderedPaths, [TreePath([0]), TreePath([2])])
    }

    func testElementMatchGraphPreservesTraversalOrderFromMatches() {
        let later = ElementMatch(
            path: TreePath([9]),
            traversalOrder: 9,
            element: makeElement(label: "Row", actions: [.activate])
        )
        let earlier = ElementMatch(
            path: TreePath([1]),
            traversalOrder: 1,
            element: makeElement(label: "Row", actions: [.activate])
        )
        let graph = ElementMatchGraph(ElementMatchSet([later, earlier]))

        let matches = graph.resolve(ElementPredicate(label: "Row"))

        XCTAssertEqual(matches.orderedPaths, [TreePath([1]), TreePath([9])])
    }

    func testTargetOrdinalSelectsFromNarrowedMatchSet() {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
            makeElement(label: "Save", traits: [.staticText]),
            makeElement(label: "Save", traits: [.button]),
        ]
        let graph = ElementMatchGraph(elements: elements)

        let selected = graph.resolve(.predicate(ElementPredicateTemplate(label: "Save", traits: [.button]), ordinal: 1))

        XCTAssertEqual(selected.elements.elements, [elements[2]])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([2])])
        let predicate = AccessibilityPredicate<RootContext>.exists(
            .predicate(ElementPredicateTemplate(label: "Save", traits: [.button]), ordinal: 1)
        )
        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: currentTrace(elements))).met)
    }

    func testTargetWithinContainerSelectsOnlyDescendants() {
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

        let selected = ElementMatchGraph(interface: interface)
            .resolve(.within(container: .label("Checkout"), target: .label("Pay")))

        XCTAssertEqual(selected.elements.elements, [pay])
        XCTAssertEqual(selected.elements.orderedPaths, [TreePath([0, 0])])
    }

    func testStatePredicateRequiresObservedTraceForActionResultValidation() {
        let action = ActionResult.success(method: .activate)
        let result = AccessibilityPredicate<RootContext>.missing(.label("Loading")).validate(against: action)

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

    func testScreenChangedMetWhenTraceChangesScreen() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = makeResult(success: true, trace: .screenChangedForTests(replacementInterface: interface))
        let result = AccessibilityPredicate<RootContext>.changed(.screen()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenTraceOnlyChangesElements() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = makeResult(success: true, trace: trace)
        let result = AccessibilityPredicate<RootContext>.changed(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWithoutTrace() {
        let action = makeResult(success: true)
        let result = AccessibilityPredicate<RootContext>.changed(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testScreenChangedUsesTraceEndpointProjection() {
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
            context: AccessibilityTrace.Context(screenId: "settings")
        )
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(
                accessibilityTrace: AccessibilityTrace(captures: [first, last])
            )
        )

        let outcome = AccessibilityPredicate<RootContext>.changed(.screen()).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertNil(outcome.actual)
    }

    func testScreenAssertionsUseCurrentReplacementInterface() {
        let trace = screenTrace(
            before: makeTestInterface(elements: [makeElement(label: "Home")]),
            after: makeTestInterface(elements: [makeElement(label: "Settings")])
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen([
            .exists(.label("Settings")),
            .missing(.label("Home")),
        ]))

        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: trace)).met)
    }

    func testScreenDepartureAndArrivalSatisfyElementLifecycleAssertions() {
        let trace = screenTrace(
            before: makeTestInterface(elements: [makeElement(label: "Home")]),
            after: makeTestInterface(elements: [makeElement(label: "Settings")])
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .disappeared(.label("Home")),
            .appeared(.label("Settings")),
        ]))

        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: trace)).met)
    }

    func testIdenticalTargetCanDisappearAndReappearAcrossScreenBoundary() {
        let shared = makeElement(label: "Continue", traits: [.button])
        let trace = screenTrace(
            before: makeTestInterface(elements: [shared]),
            after: makeTestInterface(elements: [shared])
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .disappeared(.label("Continue")),
            .appeared(.label("Continue")),
        ]))

        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: trace)).met)
    }

    func testUpdatedOnlyMatchesSameScreenElementFacts() {
        let before = makeTestInterface(elements: [makeElement(label: "Count", value: "1")])
        let after = makeTestInterface(elements: [makeElement(label: "Count", value: "2")])
        let sameScreen = AccessibilityTrace(first: before).appending(after)
        let screenBoundary = screenTrace(before: before, after: after)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Count"), .value(before: "1", after: "2")),
        ]))

        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: sameScreen)).met)
        XCTAssertFalse(predicate.validate(against: makeResult(success: true, trace: screenBoundary)).met)
    }

    func testNotificationOnlyFactSatisfiesGenericElementsChange() {
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
            AccessibilityPredicate<RootContext>.changed(.elements())
                .validate(against: makeResult(success: true, trace: trace)).met
        )
    }

    func testNoChangeRequiresCompleteFactFreeWindow() {
        let interface = makeTestInterface(elements: [makeElement(label: "Ready")])
        let incomplete = AccessibilityTrace(interface: interface)
        let complete = AccessibilityTrace(first: interface).appending(interface)
        let changed = AccessibilityTrace(first: interface).appending(
            makeTestInterface(elements: [makeElement(label: "Done")])
        )
        let predicate = AccessibilityPredicate<RootContext>.noChange

        let incompleteResult = predicate.validate(against: makeResult(success: true, trace: incomplete))
        XCTAssertFalse(incompleteResult.met)
        XCTAssertEqual(incompleteResult.actual, "observation history incomplete")
        XCTAssertTrue(predicate.validate(against: makeResult(success: true, trace: complete)).met)
        XCTAssertFalse(predicate.validate(against: makeResult(success: true, trace: changed)).met)

        let explicitlyIncomplete = ActionResult.success(
            method: .syntheticTap,
            evidence: ActionResultEvidence(
                accessibilityTrace: complete,
                settlement: .timedOut(durationMs: 0)
            )
        )
        let explicitlyIncompleteResult = predicate.validate(against: explicitlyIncomplete)
        XCTAssertFalse(explicitlyIncompleteResult.met)
        XCTAssertEqual(explicitlyIncompleteResult.actual, "observation history incomplete")
    }

    func testActionResultValidationUsesAccumulatedTraceEvidence() {
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
            evidence: ActionResultEvidence(accessibilityTrace: trace)
        )
        let changePredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Counter"), .value(before: "0", after: "1")),
        ]))

        XCTAssertTrue(changePredicate.validate(against: action).met)
        XCTAssertFalse(AccessibilityPredicate<RootContext>.noChange.validate(against: action).met)
    }

    func testScreenChangedRequiresTraceEndpointEdge() {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(
                accessibilityTrace: AccessibilityTrace(interface: Interface(
                    timestamp: Date(timeIntervalSince1970: 0),
                    tree: []
                ))
            )
        )

        let outcome = AccessibilityPredicate<RootContext>.changed(.screen()).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noChange")
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenTraceChangesElements() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "0", new: "1")
        let action = makeResult(success: true, trace: trace)
        let result = AccessibilityPredicate<RootContext>.changed(.elements()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenTraceHasNoChange() {
        let action = makeResult(success: true, trace: .noChangeForTests(elementCount: 5))
        let result = AccessibilityPredicate<RootContext>.changed(.elements()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedMetForScreenDepartureAndArrivalFacts() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let action = makeResult(success: true, trace: .screenChangedForTests(replacementInterface: interface))
        let result = AccessibilityPredicate<RootContext>.changed(.elements()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Counter"), .value(before: "3", after: "5")),
        ]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedRequiresTargetAndPropertyAtEncodeBoundary() throws {
        let stale = Data(#"{"type":"updated","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":"counter"}}]}}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityPredicate<ElementsAssertionContext>.self, from: stale)
        )
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedPassReportsObservedPropertyProof() {
        let trace = makeUpdateTrace(label: "Quantity", property: .value, old: "2", new: "3")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Quantity"), .value(before: "2", after: "3")),
        ]))
        let result = predicate.validate(against: action)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testElementUpdatedDoesNotPassWhenCurrentValueAlreadyMatchedWithoutChangeEvidence() {
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Quantity"), .value(before: "3", after: "3")),
        ]))
        let trace = AccessibilityTrace.noChangeForTests(elementCount: 1)
        let result = predicate.evaluate(in: makeEvidence(trace))

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementUpdatedNotMetWhenNoMatch() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            makeUpdate(label: "Other", property: .value, old: "1", new: "5"),
            makeUpdate(label: "Counter", property: .value, old: "3", new: "5"),
        ]))
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() {
        let trace = makeUpdateTrace(label: "Other", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Counter"), .value(after: "5")),
        ]))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(before: "3", after: "5")),
        ]))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForOldAndNewValues() {
        let trace = makeUpdateTrace(label: "cart", property: .value, old: "cart: empty", new: "3 items")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("cart"), .value(before: .prefix("cart:"), after: .suffix("items"))),
        ]))

        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForEveryModeAcrossBeforeAndAfter() {
        let trace = makeUpdateTrace(label: "Search Field", property: .value, old: "Search for tea", new: "John Smith")
        let action = makeResult(success: true, trace: trace)
        let changes: [AnyPropertyChangeExpr] = [
            .value(before: .exact("Search for tea"), after: .exact("John Smith")),
            .value(before: .contains("for"), after: .contains("Smith")),
            .value(before: .prefix("Search"), after: .prefix("John")),
            .value(before: .suffix("tea"), after: .suffix("Smith")),
        ]

        for change in changes {
            let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
                .updated(.label("Search Field"), change),
            ]))
            XCTAssertTrue(predicate.validate(against: action).met)
        }
    }

    func testElementUpdatedMatchesTraitGainAndLossAcrossBeforeAndAfter() {
        let gained = makeTraitUpdate(label: "Favorites", beforeTraits: [.button], afterTraits: [.button, .selected])
        let lost = makeTraitUpdate(label: "Disabled", beforeTraits: [.button, .notEnabled], afterTraits: [.button])
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(elementCount: 2, edits: ElementEdits(updated: [gained, lost]))
        )

        let selectedGain = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Favorites"),
                .traits(before: .init(exclude: [.selected]), after: .init(include: [.selected]))
            ),
        ]))
        let enabledLoss = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Disabled"),
                .traits(before: .init(include: [.notEnabled]), after: .init(exclude: [.notEnabled]))
            ),
        ]))

        XCTAssertTrue(selectedGain.validate(against: action).met)
        XCTAssertTrue(enabledLoss.validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedActionChecker() throws {
        let update = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Stepper", actions: [.increment]),
            new: makeElement(label: "Stepper", actions: [.increment, .activate])
        ))
        let action = makeResult(
            success: true,
            trace: .elementsChangedForTests(elementCount: 1, edits: ElementEdits(updated: [update]))
        )

        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Stepper"),
                .actions(
                    before: ActionSetMatch(exclude: Set<ElementAction>([.activate])),
                    after: ActionSetMatch(include: Set<ElementAction>([.activate]))
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Stepper"), .actions(after: ActionSetMatch(exclude: [.activate]))),
        ]))

        XCTAssertTrue(predicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
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
            )
        )

        let framePredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 12, y: 20, width: 120, height: 44))),
        ]))
        let pointPredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Knob"), .activationPoint(after: ElementPointMatch(x: 42, y: 64))),
        ]))
        let mismatch = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Card"), .frame(after: ElementFrameMatch(x: 13))),
        ]))

        XCTAssertTrue(framePredicate.validate(against: action).met)
        XCTAssertTrue(pointPredicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
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
            )
        )

        let customPredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch<StringExpr>.exact("Status"),
                    value: StringMatch<StringExpr>.contains("Ready"),
                    isImportant: true
                ))
            ),
        ]))
        let rotorPredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Article"),
                .rotors(
                    before: RotorSetMatch(exclude: [StringMatch<StringExpr>.exact("Headings")]),
                    after: RotorSetMatch(include: [StringMatch<StringExpr>.contains("Head")])
                )
            ),
        ]))
        let mismatch = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Form"),
                .customContent(after: CustomContentMatch(
                    label: StringMatch<StringExpr>.exact("Status"),
                    isImportant: false
                ))
            ),
        ]))

        XCTAssertTrue(customPredicate.validate(against: action).met)
        XCTAssertTrue(rotorPredicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
    }

    func testElementUpdatedRejectsBeforeAfterWithoutPropertyAtDecodeBoundary() {
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

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "property")
            XCTAssertTrue(context.debugDescription.contains("before/after require property"))
        }
    }

    func testElementUpdatedRejectsStringCheckersForNonTextPropertiesAtDecodeBoundary() {
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

    func testElementUpdatedRejectsElementMatcherFieldsInsideTypedCheckerObjects() {
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

    func testElementUpdatedRejectsUnknownNestedCheckerKeysAtDecodeBoundary() {
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

    func testElementUpdatedWithPropertyOnlyMetWhenTargetUpdates() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "a", new: "b")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value()),
        ]))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWithoutTrace() {
        let action = makeResult(success: true)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits())
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no matching element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() {
        let trace = makeUpdateTrace(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 10, edits: ElementEdits(updated: [
            makeUpdate(label: "label", property: .value, old: "A", new: "B"),
            makeUpdate(label: "counter", property: .value, old: "3", new: "5"),
        ]))
        let action = makeResult(success: true, trace: trace)
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("counter"), .value(after: "5")),
        ]))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() {
        let trace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(
                before: makeElement(label: "Toggle", traits: [.button]),
                after: makeElement(label: "Toggle", value: "5", traits: [.button, .selected]),
                changes: [
                    .traits(old: [.button], new: [.button, .selected]),
                    .value(old: "3", new: "5"),
                ]
            ),
        ]))
        let action = makeResult(success: true, trace: trace)
        let traitsResult = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Toggle"), .traits()),
        ]))
            .validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valueResult = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Toggle"), .value(after: "5")),
        ]))
            .validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintResult = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Toggle"), .hint()),
        ]))
            .validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(accessibilityTrace: .elementsChangedForTests(
                elementCount: 5,
                edits: ElementEdits(updated: [
                    makeUpdate(label: "btn_1", property: .value, old: "OFF", new: "ON"),
                ])
            ))
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("btn_1"), .value(before: "OFF", after: "ON")),
        ]))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementUpdatedPropertyOnly() {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(accessibilityTrace: .elementsChangedForTests(
                elementCount: 5,
                edits: ElementEdits(updated: [
                    makeUpdate(label: "any", property: .value, old: "A", new: "B"),
                ])
            ))
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(
                accessibilityTrace: .elementsChangedForTests(elementCount: 5, edits: ElementEdits())
            )
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("any"), .value()),
        ]))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no matching element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult.success(
            method: .activate,
            evidence: ActionResultEvidence(accessibilityTrace: .elementsChangedForTests(
                elementCount: 5,
                edits: ElementEdits(updated: [
                    makeUpdate(label: "btn_1", property: .hint, old: "A", new: "B"),
                ])
            ))
        )
        let predicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("btn_1"), .value()),
        ]))
        XCTAssertFalse(predicate.validate(against: result).met)
    }

    // MARK: - final state predicates

    func testPresentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate<RootContext>.exists(.element(.label("New Task"), traits: [.staticText]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testPresentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "No receipt", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
            evidence: ActionResultEvidence(
                accessibilityTrace: .screenChangedForTests(replacementInterface: replacementInterface)
            )
        )
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("No receipt"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testPresentNotMetAgainstFinalInterfaceWhenAbsent() {
        let otherElement = makeElement(label: "New sale", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
            evidence: ActionResultEvidence(
                accessibilityTrace: .screenChangedForTests(replacementInterface: replacementInterface)
            )
        )
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("No receipt"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("No receipt") == true)
    }

    func testAbsentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate<RootContext>.missing(.element(.label("Old Item"), traits: [.button]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "Done", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
            evidence: ActionResultEvidence(
                accessibilityTrace: .screenChangedForTests(replacementInterface: replacementInterface)
            )
        )
        let predicate = AccessibilityPredicate<RootContext>.missing(.label("Recording payment"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testAbsentNotMetAgainstFinalInterfaceWhenStillPresent() {
        let sameElement = makeElement(label: "Header", traits: [.header])
        let replacementInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult.success(
            method: .wait,
            evidence: ActionResultEvidence(
                accessibilityTrace: .screenChangedForTests(replacementInterface: replacementInterface)
            )
        )
        let predicate = AccessibilityPredicate<RootContext>.missing(.label("Header"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertTrue(outcome.actual?.contains("Header") == true)
    }

    // MARK: - Round-trip across cases

    func testAccessibilityPredicateRoundTrip() throws {
        let predicates: [AccessibilityPredicate<RootContext>] = [
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
            let decoded = try decoder.decode(AccessibilityPredicate<RootContext>.self, from: data)
            XCTAssertEqual(decoded, predicate)
        }
    }

    // MARK: - Decode Errors

    func testDecodeRejectsUnknownType() {
        let json = Data(#"{"type": "rainbow"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected .dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("rainbow"))
        }
    }

    func testDecodeRejectsMissingType() {
        let json = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json))
    }

    func testRemovedElementTransitionPredicatesRejectAtCodableBoundary() {
        let json = Data(#"{"type":"appeared","element":{"label":"Save"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("appeared"), "\(error)")
        }
    }

    func testRemovedAllStateRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"all","states":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("all"), "\(error)")
        }
    }

    func testRemovedCombinedChangeScopeRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"change","scopes":[{"type":"all","scopes":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("change"), "\(error)")
        }
    }

    func testRemovedNestedChangeScopeRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"change","scopes":[{"type":"change"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: json)) { error in
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
            try JSONDecoder().decode(AccessibilityPredicate<RootContext>.self, from: Data(json.utf8)),
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
        activationPointEvidence: ActivationPointEvidence = .unavailable,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
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
    ) -> AccessibilityTrace {
        .elementsChangedForTests(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                makeUpdate(label: label, property: property, old: old, new: new),
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
    ) -> ElementUpdate {
        ElementUpdate(
            before: makeElementForUpdate(label: label, property: property, value: old, traits: beforeTraits),
            after: makeElementForUpdate(label: label, property: property, value: new, traits: afterTraits),
            changes: [propertyChange(
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
    ) -> ElementUpdate {
        ElementUpdate(
            before: makeElement(label: label, traits: beforeTraits),
            after: makeElement(label: label, traits: afterTraits),
            changes: [
                .traits(old: beforeTraits, new: afterTraits),
            ]
        )
    }

    private func propertyChange(
        property: ElementProperty,
        old: String?,
        new: String?,
        beforeTraits: [HeistTrait],
        afterTraits: [HeistTrait]
    ) -> PropertyChange {
        switch property {
        case .label:
            return .label(old: old, new: new)
        case .identifier:
            return .identifier(old: old, new: new)
        case .value:
            return .value(old: old, new: new)
        case .hint:
            return .hint(old: old, new: new)
        case .traits:
            return .traits(old: beforeTraits, new: afterTraits)
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
        message: String? = nil,
        trace: AccessibilityTrace? = nil
    ) -> ActionResult {
        if success {
            return ActionResult.success(
                method: .syntheticTap,
                message: message,
                evidence: ActionResultEvidence(accessibilityTrace: trace)
            )
        }
        return ActionResult.failure(
            method: .syntheticTap,
            errorKind: .actionFailed,
            message: message,
            evidence: ActionResultEvidence(accessibilityTrace: trace)
        )
    }

    private func currentTrace(_ elements: [HeistElement]) -> AccessibilityTrace {
        AccessibilityTrace(interface: makeTestInterface(elements: elements))
    }

    private func screenTrace(before: Interface, after: Interface) -> AccessibilityTrace {
        AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(
                sequence: 1,
                interface: before,
                context: AccessibilityTrace.Context(screenId: "before")
            ),
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: after,
                context: AccessibilityTrace.Context(screenId: "after")
            ),
        ])
    }

    private func makeEvidence(_ trace: AccessibilityTrace) -> PredicateEvaluationEvidence {
        guard let evidence = PredicateEvaluationEvidence(trace: trace, isComplete: true) else {
            preconditionFailure("test trace requires at least one capture")
        }
        return evidence
    }
}

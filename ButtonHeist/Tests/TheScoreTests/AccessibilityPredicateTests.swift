import XCTest
import ThePlans
@testable import TheScore

final class AccessibilityPredicateTests: XCTestCase {

    // MARK: - Codable Round-Trip: presence

    func testPresentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentEncodeDecode() throws {
        let predicate = AccessibilityPredicate.state(.missing(ElementPredicate(label: "Loading")))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testScreenChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.screen())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementsChangedEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements())
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Presence Evaluation

    func testPresentMatchesAnyValueFour() {
        let elements = [makeElement(label: "Counter", value: "4")]
        XCTAssertTrue(AccessibilityPredicate.State.exists(ElementPredicate(value: "4")).evaluatePresence(in: elements))
    }

    func testStateEvaluationReturnsNamedResult() {
        let result: PredicateEvaluationResult = AccessibilityPredicate.State
            .exists(ElementPredicate(label: "Ready"))
            .evaluate(in: [makeElement(label: "Ready")])

        XCTAssertEqual(result, PredicateEvaluationResult(met: true))
    }

    func testPresentNarrowsByIdentifierAndValue() {
        let elements = [
            makeElement(label: "Counter", value: "4", identifier: "slider"),
            makeElement(label: "Other", value: "4", identifier: "knob"),
        ]
        XCTAssertTrue(AccessibilityPredicate.State.exists(ElementPredicate(identifier: "slider", value: "4")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.exists(ElementPredicate(identifier: "slider", value: "5")).evaluatePresence(in: elements))
    }

    func testAbsentTrueOnlyWhenNoneMatch() {
        let elements = [makeElement(label: "Ready")]
        XCTAssertTrue(AccessibilityPredicate.State.missing(ElementPredicate(label: "Loading")).evaluatePresence(in: elements))
        XCTAssertFalse(AccessibilityPredicate.State.missing(ElementPredicate(label: "Ready")).evaluatePresence(in: elements))
    }

    func testElementMatchSetKeepsEqualInterfaceElementsDistinctByTreePath() {
        let duplicate = makeElement(label: "Save", traits: [.button])
        let interface = makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(duplicate),
                testElement(duplicate),
            ]),
        ])

        let matches = ElementMatchSet(interface: interface)
            .matching(ElementPredicate(label: "Save"))

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

        let matches = ElementMatchSet(elements: elements).matching(ElementPredicate(
            label: "Save",
            identifier: "primary",
            traits: [.button]
        ))

        XCTAssertEqual(matches.elements, [elements[0]])
        XCTAssertEqual(matches.orderedPaths, [TreePath([0])])
    }

    func testElementMatchSetUnionUsesPathIdentityAndTraversalOrder() {
        let elements = [
            makeElement(label: "Save"),
            makeElement(label: "Other"),
            makeElement(label: "Cancel"),
        ]
        let allMatches = ElementMatchSet(elements: elements)
        let cancelMatches = allMatches.matching(ElementPredicate(label: "Cancel"))
        let saveMatches = allMatches.matching(ElementPredicate(label: "Save"))

        XCTAssertEqual(cancelMatches.union(saveMatches).orderedPaths, [TreePath([0]), TreePath([2])])
    }

    func testTargetOrdinalSelectsFromNarrowedMatchSet() {
        let elements = [
            makeElement(label: "Save", traits: [.button]),
            makeElement(label: "Save", traits: [.staticText]),
            makeElement(label: "Save", traits: [.button]),
        ]
        let matches = ElementMatchSet(elements: elements)

        let selected = matches.matching(.predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 1))

        XCTAssertEqual(selected.elements, [elements[2]])
        XCTAssertEqual(selected.orderedPaths, [TreePath([2])])
        XCTAssertTrue(AccessibilityPredicate.State.existsTarget(
            .predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 1)
        ).evaluate(in: matches).met)
    }

    func testStatePredicateRequiresObservedTraceForActionResultValidation() {
        let action = ActionResult(success: true, method: .activate)
        let result = AccessibilityPredicate.state(.missing(ElementPredicate(label: "Loading"))).validate(against: action)

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    // MARK: - ExpectationResult Codable Round-Trip

    func testExpectationResultEncodeDecode() throws {
        let result = ExpectationResult(
            met: false,
            predicate: .change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "hello"))))),
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
            predicate: .change(.screen()),
            actual: "noChange"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExpectationResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    // MARK: - Validation: screen changed

    func testScreenChangedMetWhenDeltaIsScreenChanged() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testScreenChangedNotMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "elementsChanged")
    }

    func testScreenChangedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let result = AccessibilityPredicate.change(.screen()).validate(against: action)
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
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: AccessibilityTrace(captures: [first, last])
        )

        let outcome = AccessibilityPredicate.change(.screen()).validate(against: result)

        XCTAssertTrue(outcome.met)
        XCTAssertEqual(outcome.actual, "screenChanged")
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

        guard case .noChange? = trace.endpointDelta else {
            return XCTFail("Expected no-change endpoint delta, got \(String(describing: trace.endpointDelta))")
        }

        let action = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: trace
        )
        let changePredicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: ElementPredicate(label: "Counter"),
            change: .value(before: "0", after: "1")
        ))))

        XCTAssertTrue(changePredicate.validate(against: action).met)
        XCTAssertFalse(AccessibilityPredicate.noChange.validate(against: action).met)
    }

    func testScreenChangedRequiresTraceEndpointEdge() {
        let result = ActionResult(
            success: true,
            method: .activate,
            accessibilityTrace: AccessibilityTrace(interface: Interface(
                timestamp: Date(timeIntervalSince1970: 0),
                tree: []
            ))
        )

        let outcome = AccessibilityPredicate.change(.screen()).validate(against: result)

        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "noTrace")
    }

    // MARK: - Validation: elements changed (superset rule)

    func testElementsChangedMetWhenDeltaIsElementsChanged() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits()))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertTrue(result.met)
    }

    func testElementsChangedNotMetWhenDeltaIsNoChange() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 5))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementsChangedNotMetWhenScreenChanged() {
        let interface = Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        let delta: AccessibilityTrace.Delta = .screenChanged(.init(elementCount: 5, newInterface: interface))
        let action = makeResult(success: true, delta: delta)
        let result = AccessibilityPredicate.change(.elements()).validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "screenChanged")
    }

    // MARK: - Codable: element updated

    func testElementUpdatedToOnlyEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedAllFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(before: "3", after: "5")
        ))))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testElementUpdatedNoFieldsEncodeDecode() throws {
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(.any)))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    // MARK: - Validation: element updated

    func testElementUpdatedMetWhenNewValueMatches() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedPassReportsObservedPropertyProof() {
        let delta = makeUpdateDelta(label: "Quantity", property: .value, old: "2", new: "3")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Quantity"),
            change: .value(before: "2", after: "3")
        ))))
        let result = predicate.validate(against: action)

        XCTAssertTrue(result.met)
        XCTAssertNil(result.actual)
    }

    func testElementUpdatedDoesNotPassWhenCurrentValueAlreadyMatchedWithoutDeltaEvidence() {
        let delta: AccessibilityTrace.Delta = .noChange(.init(elementCount: 1))
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Quantity"),
            change: .value(before: "3", after: "3")
        ))))
        let result = predicate.evaluate(
            currentElements: [makeElement(label: "Quantity", value: "3")],
            delta: delta
        )

        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "noChange")
    }

    func testElementUpdatedNotMetWhenNoMatch() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenElementPredicateAndNewValueMatch() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            makeUpdate(label: "Other", property: .value, old: "1", new: "5"),
            makeUpdate(label: "Counter", property: .value, old: "3", new: "5"),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(after: "5")
        ))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenElementPredicateDoesNotMatch() {
        let delta = makeUpdateDelta(label: "Other", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Counter"),
            change: .value(after: "5")
        ))))
        XCTAssertFalse(predicate.validate(against: action).met)
    }

    func testElementUpdatedMetWhenOldAndNewValueMatch() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "5")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(before: "3", after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForOldAndNewValues() {
        let delta = makeUpdateDelta(label: "cart", property: .value, old: "cart: empty", new: "3 items")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .value(before: .prefix("cart:"), after: .suffix("items"))
        ))))

        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedUsesConfiguredStringMatchForEveryModeAcrossBeforeAndAfter() {
        let delta = makeUpdateDelta(label: "Search Field", property: .value, old: "Search for tea", new: "John Smith")
        let action = makeResult(success: true, delta: delta)
        let predicates = [
            ElementUpdatePredicate(change: .value(before: .exact("Search for tea"), after: .exact("John Smith"))),
            ElementUpdatePredicate(change: .value(before: .contains("for"), after: .contains("Smith"))),
            ElementUpdatePredicate(change: .value(before: .prefix("Search"), after: .prefix("John"))),
            ElementUpdatePredicate(change: .value(before: .suffix("tea"), after: .suffix("Smith"))),
        ]

        for update in predicates {
            XCTAssertTrue(AccessibilityPredicate.change(.elements(.updatedElement(update))).validate(against: action).met)
        }
    }

    func testElementUpdatedMatchesTraitGainAndLossAcrossBeforeAndAfter() {
        let gained = makeTraitUpdate(label: "Favorites", beforeTraits: [.button], afterTraits: [.button, .selected])
        let lost = makeTraitUpdate(label: "Disabled", beforeTraits: [.button, .notEnabled], afterTraits: [.button])
        let action = makeResult(success: true, delta: .elementsChanged(.init(elementCount: 2, edits: ElementEdits(updated: [gained, lost]))))

        let selectedGain = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .traits(before: .exclude([.selected]), after: .include([.selected]))
        ))))
        let enabledLoss = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .traits(before: .include([.notEnabled]), after: .exclude([.notEnabled]))
        ))))

        XCTAssertTrue(selectedGain.validate(against: action).met)
        XCTAssertTrue(enabledLoss.validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedActionChecker() throws {
        let update = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Stepper", actions: [.increment]),
            new: makeElement(label: "Stepper", actions: [.increment, .activate]),
            includeGeometry: false
        ))
        let action = makeResult(success: true, delta: .elementsChanged(.init(elementCount: 1, edits: ElementEdits(updated: [update]))))

        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .actions(ElementPropertyChange<ActionsProperty>(
                before: ActionSetMatch.exclude(Set<ElementAction>([.activate])),
                after: ActionSetMatch.include(Set<ElementAction>([.activate]))
            ))
        ))))
        let mismatch = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .actions(ElementPropertyChange<ActionsProperty>(
                after: ActionSetMatch.exclude(Set<ElementAction>([.activate]))
            ))
        ))))

        XCTAssertTrue(predicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedGeometryCheckers() throws {
        let frameUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Card", frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44),
            new: makeElement(label: "Card", frameX: 12, frameY: 20, frameWidth: 120, frameHeight: 44)
        ))
        let pointUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Knob", activationPointX: 10, activationPointY: 12),
            new: makeElement(label: "Knob", activationPointX: 42, activationPointY: 64)
        ))
        let action = makeResult(success: true, delta: .elementsChanged(.init(
            elementCount: 2,
            edits: ElementEdits(updated: [frameUpdate, pointUpdate])
        )))

        let framePredicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .frame(ElementPropertyChange<FrameProperty>(
                after: ElementFrameMatch.exact(x: 12, y: 20, width: 120, height: 44)
            ))
        ))))
        let pointPredicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .activationPoint(ElementPropertyChange<ActivationPointProperty>(
                after: ElementPointMatch.exact(x: 42, y: 64)
            ))
        ))))
        let mismatch = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .frame(ElementPropertyChange<FrameProperty>(
                after: ElementFrameMatch.match(x: 13)
            ))
        ))))

        XCTAssertTrue(framePredicate.validate(against: action).met)
        XCTAssertTrue(pointPredicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
    }

    func testElementUpdatedMatchesTypedCustomContentAndRotorCheckers() throws {
        let customContent = HeistCustomContent(label: "Status", value: "Ready to submit", isImportant: true)
        let customUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Form", customContent: [HeistCustomContent(label: "Help", value: "Optional", isImportant: false)]),
            new: makeElement(label: "Form", customContent: [customContent]),
            includeGeometry: false
        ))
        let rotorUpdate = try XCTUnwrap(projectElementStateChange(
            old: makeElement(label: "Article", rotors: [HeistRotor(name: "Links")]),
            new: makeElement(label: "Article", rotors: [HeistRotor(name: "Headings"), HeistRotor(name: "Links")]),
            includeGeometry: false
        ))
        let action = makeResult(success: true, delta: .elementsChanged(.init(
            elementCount: 2,
            edits: ElementEdits(updated: [customUpdate, rotorUpdate])
        )))

        let customPredicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .customContent(ElementPropertyChange<CustomContentProperty>(
                after: CustomContentMatch.match(
                    label: StringMatch<String>.exact("Status"),
                    value: StringMatch<String>.contains("Ready"),
                    isImportant: true
                )
            ))
        ))))
        let rotorPredicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .rotors(ElementPropertyChange<RotorsProperty>(
                before: RotorSetMatch.exclude([StringMatch<String>.exact("Headings")]),
                after: RotorSetMatch.include([StringMatch<String>.contains("Head")])
            ))
        ))))
        let mismatch = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .customContent(ElementPropertyChange<CustomContentProperty>(
                after: CustomContentMatch.match(
                    label: StringMatch<String>.exact("Status"),
                    isImportant: false
                )
            ))
        ))))

        XCTAssertTrue(customPredicate.validate(against: action).met)
        XCTAssertTrue(rotorPredicate.validate(against: action).met)
        XCTAssertFalse(mismatch.validate(against: action).met)
    }

    func testElementUpdatedRejectsBeforeAfterWithoutPropertyAtDecodeBoundary() {
        let json = Data("""
        {
          "type": "change",
          "scopes": [
            {
              "type": "elements",
              "assertions": [
                {
                  "type": "updated",
                  "after": { "x": 1 }
                }
              ]
            }
          ]
        }
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.codingPath.last?.stringValue, "property")
            XCTAssertEqual(context.debugDescription, "updated predicate before/after require property")
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
                  "type": "change",
                  "scopes": [
                    {
                      "type": "elements",
                      "assertions": [
                        {
                          "type": "updated",
                          "property": "\(property)",
                          "after": { "mode": "exact", "value": "activate" }
                        }
                      ]
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
                  "type": "change",
                  "scopes": [
                    {
                      "type": "elements",
                      "assertions": [
                        {
                          "type": "updated",
                          "property": "\(property)",
                          "after": {
                            "label": { "mode": "exact", "value": "Save" }
                          }
                        }
                      ]
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
              "type": "change",
              "scopes": [
                {
                  "type": "elements",
                  "assertions": [
                    {
                      "type": "updated",
                      "property": "frame",
                      "after": { "x": 1, "unexpected": true }
                    }
                  ]
                }
              ]
            }
            """,
            contains: #"Unknown frame match field "unexpected""#
        )
    }

    func testElementUpdatedNoFiltersMetWhenAnyUpdatesExist() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "a", new: "b")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(.any)))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedNotMetWhenNoDelta() {
        let action = makeResult(success: true)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no observed accessibility trace")
    }

    func testElementUpdatedNotMetWhenEmptyUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "no element updates")
    }

    func testElementUpdatedDiagnosticOnMiss() {
        let delta = makeUpdateDelta(label: "counter", property: .value, old: "3", new: "4")
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        let result = predicate.validate(against: action)
        XCTAssertFalse(result.met)
        XCTAssertEqual(result.actual, "counter: value: 3 → 4")
    }

    func testElementUpdatedMatchesAnyAmongMultipleUpdates() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 10, edits: ElementEdits(updated: [
            makeUpdate(label: "label", property: .value, old: "A", new: "B"),
            makeUpdate(label: "counter", property: .value, old: "3", new: "5"),
        ])))
        let action = makeResult(success: true, delta: delta)
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value(after: "5")))))
        XCTAssertTrue(predicate.validate(against: action).met)
    }

    func testElementUpdatedWithPropertyFilter() {
        let delta: AccessibilityTrace.Delta = .elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
            ElementUpdate(
                before: makeElement(label: "Toggle", traits: [.button]),
                after: makeElement(label: "Toggle", value: "5", traits: [.button, .selected]),
                changes: [
                    .traits(old: [.button], new: [.button, .selected]),
                    .value(old: "3", new: "5"),
                ]
            ),
        ])))
        let action = makeResult(success: true, delta: delta)
        let element = ElementPredicate(label: "Toggle")
        let traitsResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(element: element, change: .traits()))))
            .validate(against: action)
        XCTAssertTrue(traitsResult.met)
        let valueResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: element,
            change: .value(after: "5")
        ))))
            .validate(against: action)
        XCTAssertTrue(valueResult.met)
        let hintResult = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(element: element, change: .hint()))))
            .validate(against: action)
        XCTAssertFalse(hintResult.met)
    }

    func testElementUpdatedAllFieldsMatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "btn_1", property: .value, old: "OFF", new: "ON"),
            ]))))
        )
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            change: .value(before: "OFF", after: "ON")
        ))))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testElementUpdatedNoFilters() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "any", property: .value, old: "A", new: "B"),
            ]))))
        )
        XCTAssertTrue(AccessibilityPredicate.change(.elements(.updatedElement(.any))).validate(against: result).met)
    }

    func testElementUpdatedNoUpdatesInResult() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits())))
        )
        let outcome = AccessibilityPredicate.change(.elements(.updatedElement(.any))).validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, "no element updates")
    }

    func testElementUpdatedPropertyMismatch() {
        let result = ActionResult(
            success: true, method: .activate,
            accessibilityTrace: .projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits(updated: [
                makeUpdate(label: "btn_1", property: .hint, old: "A", new: "B"),
            ]))))
        )
        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(change: .value()))))
        XCTAssertFalse(predicate.validate(against: result).met)
    }

    // MARK: - final state predicates

    func testPresentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "New Task", traits: [.staticText]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testPresentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "No receipt", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "No receipt"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testPresentNotMetAgainstFinalInterfaceWhenAbsent() {
        let otherElement = makeElement(label: "New sale", traits: [.button])
        let newInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.exists(ElementPredicate(label: "No receipt"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, #"no element matches predicate(label="No receipt")"#)
    }

    func testAbsentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Old Item", traits: [.button]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testAbsentMetAgainstFinalInterface() {
        let newElement = makeElement(label: "Done", traits: [.button])
        let newInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Recording payment"))
        XCTAssertTrue(predicate.validate(against: result).met)
    }

    func testAbsentNotMetAgainstFinalInterfaceWhenStillPresent() {
        let sameElement = makeElement(label: "Header", traits: [.header])
        let newInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult(
            success: true, method: .wait,
            accessibilityTrace: .projectingForTests(.screenChanged(.init(elementCount: 1, newInterface: newInterface)))
        )
        let predicate = AccessibilityPredicate.missing(ElementPredicate(label: "Header"))
        let outcome = predicate.validate(against: result)
        XCTAssertFalse(outcome.met)
        XCTAssertEqual(outcome.actual, #"still present: predicate(label="Header")"#)
    }

    // MARK: - Round-trip across cases

    func testAccessibilityPredicateRoundTrip() throws {
        let predicates: [AccessibilityPredicate] = [
            .state(.exists(ElementPredicate(label: "Done"))),
            .state(.missing(ElementPredicate(label: "Loading"))),
            .change(.screen()),
            .change(.elements()),
            .change(.elements(.updatedElement(ElementUpdatePredicate(
                element: .label("btn"),
                change: .value(before: "A", after: "B")
            )))),
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

    func testDecodeRejectsUnknownType() {
        let json = Data(#"{"type": "rainbow"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                XCTFail("Expected .dataCorrupted, got \(error)")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("rainbow"))
        }
    }

    func testDecodeRejectsMissingType() {
        let json = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json))
    }

    func testRemovedElementTransitionPredicatesRejectAtCodableBoundary() {
        let json = Data(#"{"type":"appeared","element":{"label":"Save"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("appeared"), "\(error)")
        }
    }

    func testEmptyAllStateRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"all","states":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("all predicate requires at least one child state"), "\(error)")
        }
    }

    func testEmptyAllChangeScopeRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"change","scopes":[{"type":"all","scopes":[]}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("all change scope requires at least one child scope"), "\(error)")
        }
    }

    func testNestedAnyChangeScopeRejectsAtCodableBoundary() {
        let json = Data(#"{"type":"change","scopes":[{"type":"change"}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityPredicate.self, from: json)) { error in
            XCTAssertTrue("\(error)".contains("Unknown change scope type"), "\(error)")
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
        activationPointX: Double? = nil,
        activationPointY: Double? = nil,
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
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

    private func makeUpdateDelta(
        label: String,
        property: ElementProperty,
        old: String?,
        new: String?,
        elementCount: Int = 5
    ) -> AccessibilityTrace.Delta {
        .elementsChanged(.init(
            elementCount: elementCount,
            edits: ElementEdits(updated: [
                makeUpdate(label: label, property: property, old: old, new: new),
            ])
        ))
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
        value: String? = nil,
        delta: AccessibilityTrace.Delta? = nil
    ) -> ActionResult {
        ActionResult(
            success: success,
            method: .syntheticTap,
            message: message,
            payload: value.map { .value($0) },
            accessibilityTrace: delta.map(AccessibilityTrace.projectingForTests)
        )
    }
}

import ButtonHeistTestSupport
import AccessibilitySnapshotModel
import XCTest
import ThePlans
@testable import TheScore

extension AccessibilityPredicateTests {

    // MARK: - Update Decode Rejection

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

    // MARK: - final state predicates

    func testPresentCodableRoundTrip() throws {
        let predicate = AccessibilityPredicate.exists(.element(.label("New Task"), traits: [.staticText]))
        let data = try JSONEncoder().encode(predicate)
        let decoded = try JSONDecoder().decode(AccessibilityPredicate.self, from: data)
        XCTAssertEqual(decoded, predicate)
    }

    func testPresentMetAgainstFinalInterface() throws {
        let newElement = element(label: "No receipt", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            payload: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.exists(.label("No receipt"))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testPresentNotMetAgainstFinalInterfaceWhenAbsent() throws {
        let otherElement = element(label: "New sale", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [otherElement], timestamp: Date())
        let result = ActionResult.success(
            payload: .wait,
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
        let newElement = element(label: "Done", traits: [.button])
        let replacementInterface = makeTestInterface(elements: [newElement], timestamp: Date())
        let result = ActionResult.success(
            payload: .wait,
                observation: .trace(traceEvidence(
                    .screenChangedForTests(replacementInterface: replacementInterface),
                    completeness: .incomplete
                ))

        )
        let predicate = AccessibilityPredicate.missing(.label("Recording payment"))
        XCTAssertTrue(try predicate.resolve(in: .empty).validate(against: result).met)
    }

    func testAbsentNotMetAgainstFinalInterfaceWhenStillPresent() throws {
        let sameElement = element(label: "Header", traits: [.header])
        let replacementInterface = makeTestInterface(elements: [sameElement], timestamp: Date())
        let result = ActionResult.success(
            payload: .wait,
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

}

import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import ThePlans
@_spi(ButtonHeistInternals) import TheScore

final class StringMatchCommandSchemaContractTests: XCTestCase {

    func testCommandArgumentEnvelopeDecodesStringMatchPayload() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.label.rawValue: stringMatchValue(mode: "contains", value: "Pay"),
        ])

        let match = try XCTUnwrap(try envelope.schemaStringMatch(.label))
        XCTAssertEqual(match, .contains("Pay"))
    }

    @ButtonHeistActor
    func testElementTargetAcceptsContainsStringMatchObject() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "label": stringMatchValue(mode: "contains", value: "Pay"),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [.label(.contains("Pay"))])
    }

    @ButtonHeistActor
    func testElementTargetAcceptsExactStringMatchObject() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "label": stringMatchValue(mode: "exact", value: "Pay"),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [.label(.exact("Pay"))])
    }

    @ButtonHeistActor
    func testElementTargetReportsNestedStringMatchValueMismatch() async {
        XCTAssertThrowsError(try decodedElementTarget(target: elementTargetValue([
            "label": .object([
                "mode": .string("contains"),
                "value": .int(7),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.label.value")
            XCTAssertEqual(error.observed, "integer 7")
            XCTAssertEqual(error.expected, "string")
        }
    }

    @ButtonHeistActor
    func testElementTargetReportsInvalidStringMatchModeField() async {
        XCTAssertThrowsError(try decodedElementTarget(target: elementTargetValue([
            "label": .object([
                "mode": .string("regex"),
                "value": .string("Pay"),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.label.mode")
            XCTAssertEqual(error.observed, #"string "regex""#)
            XCTAssertTrue(error.expected.contains("Cannot initialize Mode"), error.expected)
        }
    }

    @ButtonHeistActor
    func testElementTargetAcceptsStringMatchArrayForRepeatedField() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "label": .array([
                stringMatchValue(mode: "prefix", value: "foo"),
                stringMatchValue(mode: "contains", value: "bar"),
                stringMatchValue(mode: "suffix", value: "baz"),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
        ])
    }

    @ButtonHeistActor
    func testElementTargetAcceptsOrderedChecks() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                predicateCheckValue(kind: "traits", values: [.string("button")]),
                predicateCheckValue(kind: "excludeTraits", values: [.string("notEnabled")]),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .traits([.button]),
            .excludeTraits([.notEnabled]),
        ])
    }

    @ButtonHeistActor
    func testElementTargetRejectsRawStringMatcherField() async throws {
        XCTAssertThrowsError(try decodedElementTarget(target: elementTargetValue([
            "label": .string("Pay"),
        ]))) { error in
            XCTAssertTrue(
                String(describing: error).contains("StringMatch object with mode and value"),
                "Unexpected error: \(error)"
            )
        }
    }

    @ButtonHeistActor
    func testGetInterfaceAcceptsContainsStringMatchObjectInMatcherField() async throws {
        let (fence, mockConn) = makeConnectedFence()

        _ = try await fence.execute(command: .getInterface, values: [
            "label": stringMatchValue(mode: "contains", value: "Pay"),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            return XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
        }

        XCTAssertEqual(query.matcher.checks, [.label(.contains("Pay"))])
    }

    @ButtonHeistActor
    func testGetInterfaceAcceptsStringMatchArrayInMatcherField() async throws {
        let (fence, mockConn) = makeConnectedFence()

        _ = try await fence.execute(command: .getInterface, values: [
            "label": .array([
                stringMatchValue(mode: "prefix", value: "foo"),
                stringMatchValue(mode: "contains", value: "bar"),
                stringMatchValue(mode: "suffix", value: "baz"),
            ]),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            return XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
        }

        XCTAssertEqual(query.matcher.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz")),
        ])
    }

    @ButtonHeistActor
    func testGetInterfaceAcceptsOrderedChecksInMatcherField() async throws {
        let (fence, mockConn) = makeConnectedFence()

        _ = try await fence.execute(command: .getInterface, values: [
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                predicateCheckValue(kind: "traits", values: [.string("button")]),
            ]),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message else {
            return XCTFail("Expected requestInterface query, got \(String(describing: mockConn.sent.last))")
        }

        XCTAssertEqual(query.matcher.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .traits([.button]),
        ])
    }

    @ButtonHeistActor
    func testGetInterfaceReportsIndexedStringMatchValueMismatch() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                predicateCheckValue(kind: "label", match: .object([
                    "mode": .string("contains"),
                    "value": .int(7),
                ])),
            ]),
        ])

        assertError(
            response,
            contains: "schema validation failed for checks[1].match.value: observed integer 7; expected string"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsMalformedOrderedMatcherChecks() async throws {
        let (fence, _) = makeConnectedFence()

        let missingStringMatch = try await fence.execute(command: .getInterface, values: [
            "checks": .array([
                predicateCheckValue(kind: "label"),
            ]),
        ])
        assertError(
            missingStringMatch,
            contains: "schema validation failed for checks[0].match: observed missing; expected StringMatch object with mode and value"
        )

        let traitWithMatch = try await fence.execute(command: .getInterface, values: [
            "checks": .array([
                predicateCheckValue(kind: "traits", match: stringMatchValue(mode: "exact", value: "button")),
            ]),
        ])
        assertError(
            traitWithMatch,
            contains: "schema validation failed for checks[0].match: observed object; expected not present for traits checks"
        )
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsRawStringMatcherField() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "label": .string("Pay"),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("expected StringMatch object with mode and value"), message)
    }

    @ButtonHeistActor
    func testGetInterfaceAcceptsObjectStringMatchInSubtreeElement() async throws {
        let (fence, mockConn) = makeConnectedFence()

        _ = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "element": elementTargetValue([
                    "label": stringMatchValue(mode: "contains", value: "Pay"),
                ]),
            ]),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message,
              case .element(.predicate(let matcher, nil)) = query.subtree else {
            return XCTFail("Expected subtree element query, got \(String(describing: mockConn.sent.last))")
        }

        XCTAssertEqual(matcher.checks, [.label(.contains("Pay"))])
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsRawStringMatchInSubtreeElement() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": .object([
                "element": elementTargetValue([
                    "label": .string("Pay"),
                ]),
            ]),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("subtree.element.label"), message)
        XCTAssertTrue(message.contains("expected StringMatch object with mode and value"), message)
    }

    func testPredicateAcceptsStringMatchObjectInElementField() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "Pay")),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(ElementPredicate(label: .contains("Pay"))))
    }

    func testPredicateAcceptsStringMatchArrayInElementField() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "suffix", value: "baz")),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz"))
        )))
    }

    func testPredicateAcceptsOrderedChecksInElementField() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                    predicateCheckValue(kind: "traits", values: [.string("button")]),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(ElementPredicate.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .traits([.button])
        )))
    }

    func testPredicateRejectsMalformedOrderedElementChecks() throws {
        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", values: [.string("button")]),
                ]),
            ]),
        ]))) { error in
            let message = schemaMessage(error)
            XCTAssertTrue(
                message.contains("element.checks[0].values"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                message.contains("expected not present for label checks"),
                "Unexpected error: \(error)"
            )
        }

        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "excludeTraits"),
                ]),
            ]),
        ]))) { error in
            let message = schemaMessage(error)
            XCTAssertTrue(
                message.contains("element.checks[0].values"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                message.contains("expected array of trait names"),
                "Unexpected error: \(error)"
            )
        }
    }

    func testPredicateSchemaTreatsUpdateBeforeAndAfterAsElementMatcherFields() throws {
        let predicateSpec = try XCTUnwrap(TheFence.Command.wait.descriptor.parameter(named: .predicate))
        let specsByKey = Dictionary(uniqueKeysWithValues: predicateSpec.objectProperties.map { ($0.key, $0) })

        XCTAssertEqual(specsByKey["before"]?.type, .object)
        XCTAssertEqual(specsByKey["after"]?.type, .object)
        XCTAssertEqual(specsByKey["before"]?.objectProperties.map(\.key).contains("value"), true)
        XCTAssertEqual(specsByKey["after"]?.objectProperties.map(\.key).contains("traits"), true)
    }

    func testPredicateRejectsRawStringMatcherField() throws {
        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "element": elementTargetValue([
                "label": .string("Pay"),
            ]),
        ]))) { error in
            XCTAssertTrue(
                String(describing: error).contains("element.label"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                String(describing: error).contains("StringMatch object with mode and value"),
                "Unexpected error: \(error)"
            )
        }
    }

    @ButtonHeistActor
    private func decodedElementTarget(target: HeistValue) throws -> ElementTarget? {
        try TheFence.CommandArgumentEnvelope(values: ["target": target]).decodedElementTarget()
    }
}

private func assertError(
    _ response: FenceResponse,
    contains expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .error(let failure) = response else {
        return XCTFail("Expected error response", file: file, line: line)
    }
    XCTAssertTrue(
        failure.message.contains(expected),
        "Expected error containing '\(expected)', got: \(failure.message)",
        file: file,
        line: line
    )
}

private func schemaMessage(_ error: Error) -> String {
    (error as? SchemaValidationError)?.message ?? String(describing: error)
}

private func elementTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
    .object(fields)
}

private func stringMatchValue(mode: String, value: String) -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

private func predicateCheckValue(kind: String, match: HeistValue? = nil, values: [HeistValue]? = nil) -> HeistValue {
    var object: [String: HeistValue] = ["kind": .string(kind)]
    if let match { object["match"] = match }
    if let values { object["values"] = .array(values) }
    return .object(object)
}

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

    func testCommandArgumentEnvelopeDecodesIsEmptyStringMatchPayload() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.label.rawValue: stringMatchIsEmptyValue(),
        ])

        let match = try XCTUnwrap(try envelope.schemaStringMatch(.label))
        XCTAssertEqual(match, .isEmpty)
    }

    func testCommandArgumentEnvelopeRejectsUnknownStringMatchFieldAtBoundary() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.label.rawValue: .object([
                "mode": .string("exact"),
                "value": .string("Pay"),
                "caseSensitive": .bool(true),
            ]),
        ])

        XCTAssertThrowsError(try envelope.schemaStringMatch(.label)) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "label.caseSensitive")
            XCTAssertEqual(error.observed, "boolean true")
            XCTAssertTrue(error.expected.contains("Unknown StringMatch field"), error.expected)
        }
    }

    func testCommandArgumentEnvelopeRejectsInvalidStringMatchArrayItemAtBoundary() throws {
        let envelope = TheFence.CommandArgumentEnvelope(values: [
            FenceParameterKey.label.rawValue: .array([
                stringMatchValue(mode: "prefix", value: "Pay"),
                stringMatchValue(mode: "contains", value: ""),
            ]),
        ])

        XCTAssertThrowsError(try envelope.schemaStringMatches(.label)) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "label[1].value")
            XCTAssertEqual(error.observed, #"string """#)
            XCTAssertEqual(error.expected, "contains string match value must not be empty")
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetAcceptsContainsStringMatchObject() async throws {
        guard let target = try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "Pay")),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [.label(.contains("Pay"))])
    }

    @ButtonHeistActor
    func testAccessibilityTargetAcceptsIsEmptyStringMatchObject() async throws {
        guard let target = try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "value", match: stringMatchIsEmptyValue()),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [.value(.isEmpty)])
    }

    @ButtonHeistActor
    func testAccessibilityTargetAcceptsExactStringMatchObject() async throws {
        guard let target = try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Pay")),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [.label(.exact("Pay"))])
    }

    @ButtonHeistActor
    func testAccessibilityTargetReportsNestedStringMatchValueMismatch() async {
        XCTAssertThrowsError(try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: .object([
                    "mode": .string("contains"),
                    "value": .int(7),
                ])),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.checks[0].match.value")
            XCTAssertEqual(error.observed, "integer 7")
            XCTAssertEqual(error.expected, "string")
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetReportsInvalidStringMatchModeField() async {
        XCTAssertThrowsError(try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: .object([
                    "mode": .string("regex"),
                    "value": .string("Pay"),
                ])),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.checks[0].match.mode")
            XCTAssertEqual(error.observed, #"string "regex""#)
            XCTAssertTrue(error.expected.contains("Cannot initialize Mode"), error.expected)
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetRejectsUnknownStringMatchField() async {
        XCTAssertThrowsError(try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: .object([
                    "mode": .string("exact"),
                    "value": .string("Pay"),
                    "caseSensitive": .bool(true),
                ])),
            ]),
        ]))) { error in
            guard let error = error as? SchemaValidationError else {
                return XCTFail("Expected SchemaValidationError, got \(error)")
            }
            XCTAssertEqual(error.field, "target.checks[0].match.caseSensitive")
            XCTAssertEqual(error.observed, "boolean true")
            XCTAssertTrue(error.expected.contains("Unknown StringMatch field"), error.expected)
        }
    }

    @ButtonHeistActor
    func testAccessibilityTargetAcceptsRepeatedStringChecks() async throws {
        guard let target = try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "suffix", value: "baz")),
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
    func testAccessibilityTargetAcceptsOrderedChecks() async throws {
        guard let target = try decodedAccessibilityTarget(target: accessibilityTargetValue([
            "checks": .array([
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                predicateCheckValue(kind: "traits", values: [.string("button")]),
                predicateCheckValue(
                    kind: "exclude",
                    check: predicateCheckValue(kind: "traits", values: [.string("notEnabled")])
                ),
            ]),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.checks, [
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .traits([.button]),
            .exclude(.traits([.notEnabled])),
        ])
    }

    @ButtonHeistActor
    func testAccessibilityTargetRejectsFlatMatcherFields() async throws {
        let cases: [(String, HeistValue)] = [
            ("object", stringMatchValue(mode: "exact", value: "Pay")),
            ("array", .array([stringMatchValue(mode: "exact", value: "Pay")])),
            ("raw", .string("Pay")),
        ]
        for (name, value) in cases {
            XCTAssertThrowsError(try decodedAccessibilityTarget(target: accessibilityTargetValue([
                "label": value,
            ])), name) { error in
                XCTAssertTrue(String(describing: error).contains("label"), "Unexpected error: \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsFlatMatcherFields() async throws {
        let (fence, _) = makeConnectedFence()

        let cases: [(String, HeistValue)] = [
            ("object", stringMatchValue(mode: "exact", value: "Pay")),
            ("array", .array([stringMatchValue(mode: "exact", value: "Pay")])),
            ("raw", .string("Pay")),
        ]
        for (_, value) in cases {
            let response = try await fence.execute(command: .getInterface, values: ["label": value])
            assertError(response, contains: "valid get_interface parameter")
        }
    }

    @ButtonHeistActor
    func testGetInterfaceAcceptsObjectStringMatchInSubtreeElement() async throws {
        let (fence, mockConn) = makeConnectedFence()

        _ = try await fence.execute(command: .getInterface, values: [
            "subtree": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "Pay")),
                ]),
            ]),
        ])

        guard let (message, _) = mockConn.sent.last,
              case .requestInterface(let query) = message,
              case .predicate(let matcher, nil) = query.subtree else {
            return XCTFail("Expected subtree element query, got \(String(describing: mockConn.sent.last))")
        }

        XCTAssertEqual(matcher.checks, [.label(.contains("Pay"))])
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsRawStringMatchInSubtreeElement() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "subtree": accessibilityTargetValue([
                "label": .string("Pay"),
            ]),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected error response")
        }
        let message = failure.message
        XCTAssertTrue(message.contains("subtree.label"), message)
        XCTAssertTrue(message.contains("label"), message)
    }

    func testPredicateAcceptsStringMatchObjectInTarget() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "Pay")),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(.predicate(ElementPredicateTemplate(label: .contains("Pay")))))
    }

    func testPredicateAcceptsRepeatedStringChecksInTarget() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "suffix", value: "baz")),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .label(.suffix("baz"))
        )))
    }

    func testPredicateAcceptsOrderedChecksInTarget() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "prefix", value: "foo")),
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "contains", value: "bar")),
                    predicateCheckValue(kind: "traits", values: [.string("button")]),
                ]),
            ]),
        ]))

        XCTAssertEqual(predicate, .exists(.element(
            .label(.prefix("foo")),
            .label(.contains("bar")),
            .traits([.button])
        )))
    }

    func testPredicateRejectsMalformedOrderedElementChecks() throws {
        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", values: [.string("button")]),
                ]),
            ]),
        ]))) { error in
            let message = schemaMessage(error)
            XCTAssertTrue(
                message.contains("target.checks[0].values"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                message.contains("expected not present for label checks"),
                "Unexpected error: \(error)"
            )
        }

        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "exclude"),
                ]),
            ]),
        ]))) { error in
            let message = schemaMessage(error)
            XCTAssertTrue(
                message.contains("target.checks[0].check"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                message.contains("expected element predicate check object"),
                "Unexpected error: \(error)"
            )
        }
    }

    func testPredicateSchemaLeavesPropertySpecificUpdateMatchesToCanonicalDecoder() throws {
        let predicateSpec = try XCTUnwrap(TheFence.Command.wait.descriptor.parameter(named: .predicate))
        let assertions = try XCTUnwrap(
            predicateSpec.objectProperties.first { $0.key == FenceParameterKey.assertions.rawValue }
        )
        let specsByKey = Dictionary(uniqueKeysWithValues: assertions.arrayItemProperties.map { ($0.key, $0) })

        XCTAssertEqual(specsByKey["before"]?.type, .object)
        XCTAssertEqual(specsByKey["after"]?.type, .object)
        XCTAssertEqual(specsByKey["before"]?.objectProperties, [])
        XCTAssertEqual(specsByKey["after"]?.objectProperties, [])
    }

    func testPredicateSchemaUsesCanonicalRootTypesAndExposesAnnouncementMatch() throws {
        let predicateSpecs = [FenceParameterBlocks.expect, FenceParameterBlocks.predicate]

        for predicateSpec in predicateSpecs {
            let specsByKey = Dictionary(
                uniqueKeysWithValues: predicateSpec.objectProperties.map { ($0.key, $0) }
            )

            XCTAssertEqual(
                specsByKey["type"]?.enumValues,
                AccessibilityPredicate<RootContext>.wireTypeValues
            )
            XCTAssertEqual(specsByKey["match"]?.type, .stringMatch)
            XCTAssertEqual(specsByKey["match"]?.required, false)
        }
    }

    func testPredicateRejectsRawStringMatcherField() throws {
        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("exists"),
            "target": accessibilityTargetValue([
                "label": .string("Pay"),
            ]),
        ]))) { error in
            XCTAssertTrue(
                String(describing: error).contains("target.label"),
                "Unexpected error: \(error)"
            )
            XCTAssertTrue(
                String(describing: error).contains("label"),
                "Unexpected error: \(error)"
            )
        }
    }

    @ButtonHeistActor
    private func decodedAccessibilityTarget(target: HeistValue) throws -> AccessibilityTarget? {
        try TheFence.CommandArgumentEnvelope(values: ["target": target]).decodedAccessibilityTarget()
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

private func accessibilityTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
    .object(fields)
}

private func stringMatchValue(mode: String, value: String) -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

private func stringMatchIsEmptyValue() -> HeistValue {
    .object([
        "mode": .string("isEmpty"),
    ])
}

private func predicateCheckValue(
    kind: String,
    match: HeistValue? = nil,
    values: [HeistValue]? = nil,
    check: HeistValue? = nil
) -> HeistValue {
    var object: [String: HeistValue] = ["kind": .string(kind)]
    if let match { object["match"] = match }
    if let values { object["values"] = .array(values) }
    if let check { object["check"] = check }
    return .object(object)
}

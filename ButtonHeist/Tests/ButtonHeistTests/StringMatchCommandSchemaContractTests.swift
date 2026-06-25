import XCTest
@testable import ButtonHeist
@_spi(ButtonHeistInternals) import ThePlans
@_spi(ButtonHeistInternals) import TheScore

final class StringMatchCommandSchemaContractTests: XCTestCase {

    @ButtonHeistActor
    func testElementTargetAcceptsContainsStringMatchObject() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "label": stringMatchValue(mode: "contains", value: "Pay"),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.label, StringMatch<String>.contains("Pay"))
    }

    @ButtonHeistActor
    func testElementTargetAcceptsExactStringMatchObject() async throws {
        guard let target = try decodedElementTarget(target: elementTargetValue([
            "label": stringMatchValue(mode: "exact", value: "Pay"),
        ])),
              case .predicate(let matcher, _) = target else {
            return XCTFail("Expected .matcher")
        }

        XCTAssertEqual(matcher.label, StringMatch<String>.exact("Pay"))
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

        XCTAssertEqual(query.matcher.label, StringMatch<String>.contains("Pay"))
    }

    @ButtonHeistActor
    func testGetInterfaceRejectsRawStringMatcherField() async throws {
        let (fence, _) = makeConnectedFence()

        let response = try await fence.execute(command: .getInterface, values: [
            "label": .string("Pay"),
        ])

        guard case .error(let message, _) = response else {
            return XCTFail("Expected error response")
        }
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

        XCTAssertEqual(matcher.label, StringMatch<String>.contains("Pay"))
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

        guard case .error(let message, _) = response else {
            return XCTFail("Expected error response")
        }
        XCTAssertTrue(message.contains("subtree.element.label"), message)
        XCTAssertTrue(message.contains("expected StringMatch object with mode and value"), message)
    }

    func testPredicateAcceptsStringMatchObjectInElementField() throws {
        let predicate = try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("present"),
            "element": elementTargetValue([
                "label": stringMatchValue(mode: "contains", value: "Pay"),
            ]),
        ]))

        XCTAssertEqual(predicate, .present(ElementPredicate(label: .contains("Pay"))))
    }

    func testPredicateSchemaTreatsUpdateFromAndToAsStringMatchFields() throws {
        let predicateSpec = try XCTUnwrap(TheFence.Command.wait.descriptor.parameter(named: .predicate))
        let specsByKey = Dictionary(uniqueKeysWithValues: predicateSpec.objectProperties.map { ($0.key, $0) })

        XCTAssertEqual(specsByKey["from"]?.type, .stringMatch)
        XCTAssertEqual(specsByKey["to"]?.type, .stringMatch)
    }

    func testPredicateRejectsRawStringMatcherField() throws {
        XCTAssertThrowsError(try TheFence.ExpectationPayload.parseRequiredPredicate(.object([
            "type": .string("present"),
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

private func elementTargetValue(_ fields: [String: HeistValue]) -> HeistValue {
    .object(fields)
}

private func stringMatchValue(mode: String, value: String) -> HeistValue {
    .object([
        "mode": .string(mode),
        "value": .string(value),
    ])
}

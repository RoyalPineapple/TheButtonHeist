import XCTest
@_spi(ButtonHeistTooling) import ButtonHeist
import ThePlans
@testable import ButtonHeistCLIExe

final class ElementTargetOptionsTests: XCTestCase {

    func testHeistIdOptionIsNotSupported() throws {
        XCTAssertThrowsError(try TapSubcommand.parse(["--heist-id", "button_save"]))
    }

    func testPositionalTargetIsRejected() {
        XCTAssertThrowsError(try TapSubcommand.parse(["button_save"]))
    }

    func testMatcherOptionsParseToTypedPredicateTarget() throws {
        let command = try TapSubcommand.parse([
            "--identifier", "saveButton",
            "--label", "Save",
            "--traits", "button",
            "--exclude-traits", "notEnabled",
            "--ordinal", "1",
        ])

        XCTAssertEqual(
            try command.element.parsedTarget(),
            .predicate(
                ElementPredicate(
                    [
                        .label("Save"),
                        .identifier("saveButton"),
                        .traits([.button]),
                        .exclude(.traits([.notEnabled])),
                    ]
                ),
                ordinal: 1
            )
        )
    }

    func testGestureElementObjectUsesSharedCLITargetEncoder() {
        let target = ElementTarget.predicate(
            ElementPredicate(label: "Save", identifier: "saveButton", value: "1", traits: [.button])
        )
        let object = TapSubcommand.elementObject(target)
        let semanticArguments = CLIRequestBuilder.arguments(target: target)
        guard case .object(let semanticObject)? = semanticArguments.argumentValues[FenceParameterKey.target.rawValue] else {
            return XCTFail("Expected semantic target object")
        }

        XCTAssertEqual(object.heistValue, .object(semanticObject))
        XCTAssertEqual(object[.checks], .array([
            .object([
                "kind": .string("label"),
                "match": .object([
                    "mode": .string("exact"),
                    "value": .string("Save"),
                ]),
            ]),
            .object([
                "kind": .string("identifier"),
                "match": .object([
                    "mode": .string("exact"),
                    "value": .string("saveButton"),
                ]),
            ]),
            .object([
                "kind": .string("value"),
                "match": .object([
                    "mode": .string("exact"),
                    "value": .string("1"),
                ]),
            ]),
            .object([
                "kind": .string("traits"),
                "values": .array([.string("button")]),
            ]),
        ]))
    }

    func testCLIRequestObjectsAccumulateRepeatedTypedKeysBeforeWireRendering() {
        var object = CLIRequestObject()

        object.appendOneOrMany(.string("button"), for: .traits)
        object.appendOneOrMany(.string("selected"), for: .traits)

        XCTAssertEqual(object[.traits], .array([.string("button"), .string("selected")]))
        XCTAssertEqual(object.rawValues, [
            FenceParameterKey.traits.rawValue: .array([.string("button"), .string("selected")]),
        ])
    }

    func testCLIRequestParametersSetNestedObjectsThroughTypedKeys() {
        let targetObject = CLIRequestObject([
            (.label, .object([
                FenceParameterKey.mode.rawValue: .string("exact"),
                FenceParameterKey.value.rawValue: .string("Save"),
            ])),
        ])
        var parameters = CLIRequestParameters()

        parameters.set(.target, targetObject)

        XCTAssertEqual(parameters[.target], targetObject.heistValue)
        XCTAssertEqual(parameters.rawValues, [
            FenceParameterKey.target.rawValue: targetObject.heistValue,
        ])
    }

    func testCommandArgumentWriterBuildsTypedParametersAndSkipsNilFields() {
        let parameters = CommandArgumentWriter.parameters(
            CommandArgumentWriter.value(.text, "hello"),
            CommandArgumentWriter.value(.timeout, 2.5),
            CommandArgumentWriter.optional(.rotor, Optional<String>.none)
        )

        XCTAssertEqual(parameters[.text], .string("hello"))
        XCTAssertEqual(parameters[.timeout], .double(2.5))
        XCTAssertNil(parameters[.rotor])
    }

    func testOrdinalOnlyIsRejectedAtTypedTargetBoundary() throws {
        let command = try TapSubcommand.parse(["--ordinal", "0"])

        XCTAssertThrowsError(try command.element.parsedTarget()) { error in
            XCTAssertTrue(
                String(describing: error).contains("ElementTarget requires a predicate"),
                "Unexpected error: \(error)"
            )
        }
    }

    func testTapWithoutTargetOrCoordinatesStillFailsValidation() async throws {
        var command = try TapSubcommand.parse([])

        XCTAssertFalse(try command.element.hasTarget)

        do {
            try await command.run()
            XCTFail("Expected missing target validation to fail before connecting")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("Must specify --identifier, -l, or --x/--y coordinates"),
                "Unexpected error: \(error)"
            )
        }
    }
}

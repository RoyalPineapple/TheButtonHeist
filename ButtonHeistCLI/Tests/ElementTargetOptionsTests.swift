import XCTest
import ButtonHeist
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
                    label: "Save",
                    identifier: "saveButton",
                    traits: [.button],
                    excludeTraits: [.notEnabled]
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

        XCTAssertEqual(
            Dictionary(object.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { _, newest in newest }),
            semanticObject
        )
        XCTAssertEqual(object[.label], .object([
            "mode": .string("exact"),
            "value": .string("Save"),
        ]))
        XCTAssertEqual(object[.identifier], .object([
            "mode": .string("exact"),
            "value": .string("saveButton"),
        ]))
        XCTAssertEqual(object[.value], .object([
            "mode": .string("exact"),
            "value": .string("1"),
        ]))
        XCTAssertEqual(object[.traits], .array([.string("button")]))
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

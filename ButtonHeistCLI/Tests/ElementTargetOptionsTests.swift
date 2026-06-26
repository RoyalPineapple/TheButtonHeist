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

    func testGestureElementObjectEncodesPredicateChecks() {
        let object = TapSubcommand.elementObject(.predicate(
            ElementPredicate(label: "Save", identifier: "saveButton", value: "1", traits: [.button])
        ))

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

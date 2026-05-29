import XCTest
import ButtonHeist
@testable import ButtonHeistCLIExe

final class ElementTargetOptionsTests: XCTestCase {

    func testPositionalTargetParsesToTypedHeistIdTarget() throws {
        let command = try TapSubcommand.parse(["button_save"])

        XCTAssertEqual(try command.element.parsedTarget(), .heistId("button_save"))
    }

    func testMatcherOptionsParseToTypedMatcherTarget() throws {
        let command = try TapSubcommand.parse([
            "--identifier", "saveButton",
            "--label", "Save",
            "--traits", "button",
            "--exclude-traits", "notEnabled",
            "--ordinal", "1",
        ])

        XCTAssertEqual(
            try command.element.parsedTarget(),
            .matcher(
                ElementMatcher(
                    label: "Save",
                    identifier: "saveButton",
                    traits: [.button],
                    excludeTraits: [.notEnabled]
                ),
                ordinal: 1
            )
        )
    }

    func testOrdinalOnlyIsRejectedAtTypedTargetBoundary() throws {
        let command = try TapSubcommand.parse(["--ordinal", "0"])

        XCTAssertThrowsError(try command.element.parsedTarget()) { error in
            XCTAssertTrue(
                String(describing: error).contains("ElementTarget requires heistId or matcher"),
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
                String(describing: error).contains("Must specify a heistId, --identifier, or --x/--y coordinates"),
                "Unexpected error: \(error)"
            )
        }
    }
}

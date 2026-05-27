import XCTest
import ButtonHeist
@testable import ButtonHeistCLIExe

final class ElementTargetOptionsTests: XCTestCase {

    func testOrdinalOnlyDoesNotCountAsTapTarget() throws {
        let command = try TapSubcommand.parse(["--ordinal", "0"])

        XCTAssertFalse(try command.element.hasTarget)
        XCTAssertNil(try command.element.parsedTarget())
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

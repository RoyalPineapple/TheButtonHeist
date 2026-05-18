import XCTest
import ButtonHeist
@testable import ButtonHeistCLIExe

final class ElementTargetOptionsTests: XCTestCase {

    func testOrdinalOnlyCountsAsTapTarget() throws {
        let command = try TapSubcommand.parse(["--ordinal", "0"])

        XCTAssertTrue(try command.element.hasTarget)

        let target = try XCTUnwrap(command.element.parsedTarget())
        guard case .matcher(let matcher, let ordinal) = target else {
            return XCTFail("Expected ordinal-only target to build a matcher target")
        }
        XCTAssertFalse(matcher.hasPredicates)
        XCTAssertEqual(ordinal, 0)
    }

    func testTapWithoutTargetOrCoordinatesStillFailsValidation() async throws {
        var command = try TapSubcommand.parse([])

        XCTAssertFalse(try command.element.hasTarget)

        do {
            try await command.run()
            XCTFail("Expected missing target validation to fail before connecting")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("Must specify a heistId, -id, or --x/--y coordinates"),
                "Unexpected error: \(error)"
            )
        }
    }
}

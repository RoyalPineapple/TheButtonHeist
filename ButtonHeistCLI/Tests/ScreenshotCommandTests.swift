import XCTest
@testable import ButtonHeistCLIExe

final class ScreenshotCommandTests: XCTestCase {

    func testIncludeInterfaceFlagParses() throws {
        let command = try ScreenshotCommand.parse(["--include-interface"])

        XCTAssertTrue(command.includeInterface)
    }

    func testIncludeInterfaceRejectsRawInlinePngOutput() throws {
        XCTAssertThrowsError(try ScreenshotCommand.parse(["--inline", "--include-interface"]))
    }
}

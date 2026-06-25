import XCTest
@testable import ButtonHeistCLIExe

final class ScreenshotCommandTests: XCTestCase {

    func testIncludeInterfaceFlagIsNotACommandSurface() {
        XCTAssertThrowsError(try ScreenshotCommand.parse(["--include-interface"]))
    }

    func testInlineRejectsOutputPath() {
        XCTAssertThrowsError(try ScreenshotCommand.parse(["--inline", "--output", "/tmp/screen.png"]))
    }
}

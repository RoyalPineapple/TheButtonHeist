import Foundation
import XCTest

import ButtonHeist
import TheScore

@testable import ButtonHeistCLIExe

final class ScreenshotCommandTests: XCTestCase {

    func testIncludeInterfaceFlagIsNotACommandSurface() {
        XCTAssertThrowsError(try ScreenshotCommand.parse(["--include-interface"]))
    }

    func testInlineRejectsOutputPath() {
        XCTAssertThrowsError(try ScreenshotCommand.parse(["--inline", "--output", "/tmp/screen.png"]))
    }

    func testInlineCommandResultWritesScreenshotDataAsBinary() throws {
        let expectedData = Data([0x89, 0x50, 0x4E, 0x47])
        let response = FenceResponse.screenshotData(
            payload: ScreenPayload(
                pngData: expectedData.base64EncodedString(),
                width: 2,
                height: 1
            )
        )

        let result = try ScreenshotCommand.inlineCommandResult(for: response)

        guard case .binary(let data) = result else {
            return XCTFail("expected inline screenshot to produce binary output")
        }
        XCTAssertEqual(data, expectedData)
        XCTAssertFalse(result.isFailure)
    }

    func testInlineCommandResultPreservesStructuredFailureResponse() throws {
        let result = try ScreenshotCommand.inlineCommandResult(for: .error("screenshot failed"))

        guard case .response(let response, let format) = result else {
            return XCTFail("expected failure to stay on formatted response path")
        }
        XCTAssertEqual(format, .human)
        XCTAssertEqual(response.humanFormatted(), "Error: screenshot failed")
        XCTAssertTrue(result.isFailure)
    }

    func testInlineCommandResultRejectsMalformedScreenshotData() {
        let response = FenceResponse.screenshotData(
            payload: ScreenPayload(pngData: "not-base64", width: 1, height: 1)
        )

        XCTAssertThrowsError(try ScreenshotCommand.inlineCommandResult(for: response)) { error in
            XCTAssertTrue(String(describing: error).contains("Failed to decode screenshot data"))
        }
    }
}

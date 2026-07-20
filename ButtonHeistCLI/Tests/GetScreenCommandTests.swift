import Foundation
import XCTest

@_spi(ButtonHeistTooling) import ButtonHeist
import TheScore

@testable import ButtonHeistCLIExe

final class GetScreenCommandTests: XCTestCase {

    func testIncludeInterfaceFlagIsNotACommandSurface() {
        XCTAssertThrowsError(try GetScreenCommand.parse(["--include-interface"]))
    }

    func testInlineRejectsOutputPath() {
        XCTAssertThrowsError(try GetScreenCommand.parse(["--inline", "--output", "/tmp/screen.png"]))
    }

    func testAccessibilityFlagSetsScreenMode() throws {
        let command = try GetScreenCommand.parse(["--accessibility"])

        let arguments = try command.requestArguments()

        XCTAssertEqual(arguments.value(for: .mode), .string("accessibility"))
    }

    func testInlineCommandResultWritesScreenshotDataAsBinary() throws {
        let expectedData = Data([0x89, 0x50, 0x4E, 0x47])
        let response = FenceResponse.screenshotData(
            payload: try XCTUnwrap(ScreenPayload.admit(
                pngData: expectedData.base64EncodedString(),
                width: 2,
                height: 1
            ))
        )

        let result = try GetScreenCommand.inlineCommandResult(for: response)

        guard case .binary(let data) = result else {
            return XCTFail("expected inline screenshot to produce binary output")
        }
        XCTAssertEqual(data, expectedData)
        XCTAssertFalse(result.isFailure)
    }

    func testInlineCommandResultPreservesStructuredFailureResponse() throws {
        let failure = DiagnosticFailure(
            message: "screenshot failed",
            details: FailureDetails(code: .requestActionFailed)
        )
        let result = try GetScreenCommand.inlineCommandResult(for: .error(failure))

        guard case .response(let formatted) = result else {
            return XCTFail("expected failure to stay on formatted response path")
        }
        XCTAssertEqual(formatted.format, .human)
        XCTAssertEqual(formatted.envelope.response.diagnosticFailure, failure)
        XCTAssertEqual(CLIRunner.renderedOutput(for: result), .text("Error: screenshot failed"))
        XCTAssertTrue(result.isFailure)
    }

    func testInlineCommandResultRejectsMalformedScreenshotData() throws {
        let response = FenceResponse.screenshotData(
            payload: try XCTUnwrap(ScreenPayload.admit(pngData: "not-base64", width: 1, height: 1))
        )

        XCTAssertThrowsError(try GetScreenCommand.inlineCommandResult(for: response)) { error in
            XCTAssertTrue(String(describing: error).contains("Failed to decode screenshot data"))
        }
    }
}

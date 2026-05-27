import XCTest
import ButtonHeist
import TheScore

final class PublicJSONGoldenTests: XCTestCase {

    func testActionSuccessPublicJSONGolden() throws {
        let result = ActionResult(
            success: true,
            method: .activate,
            payload: .value("Pressed Buy")
        )

        try XCTAssertGoldenJSON(
            FenceResponse.action(result: result),
            equals: #"{"method":"activate","status":"ok","value":"Pressed Buy"}"#
        )
    }

    func testActionFailurePublicJSONGolden() throws {
        let result = ActionResult(
            success: false,
            method: .activate,
            message: "No element matching label \"Buy\"",
            errorKind: .elementNotFound
        )

        try XCTAssertGoldenJSON(
            FenceResponse.action(result: result),
            equals: #"{"errorClass":"elementNotFound","message":"No element matching label \"Buy\"","method":"activate","status":"error"}"#
        )
    }

    func testScreenshotArtifactDefaultPolicyPublicJSONGolden() throws {
        let payload = ScreenPayload(
            pngData: "cG5n",
            width: 393,
            height: 852,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )

        try XCTAssertGoldenJSON(
            FenceResponse.screenshot(path: "/tmp/buttonheist-screen.png", payload: payload),
            equals: #"{"height":852,"path":"\/tmp\/buttonheist-screen.png","status":"ok","width":393}"#
        )
    }

    func testRecordingArtifactDefaultPolicyPublicJSONGolden() throws {
        let payload = RecordingPayload(
            videoData: "dmlkZW8=",
            width: 390,
            height: 844,
            duration: 5.0,
            frameCount: 40,
            fps: 8,
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 5),
            stopReason: .maxDuration
        )
        let expected = #"{"duration":5,"fps":8,"frameCount":40,"height":844,"interactionCount":0,"# +
            #""path":"\/tmp\/buttonheist-recording.mp4","status":"ok","stopReason":"maxDuration","width":390}"#

        try XCTAssertGoldenJSON(
            FenceResponse.recording(path: "/tmp/buttonheist-recording.mp4", payload: payload),
            equals: expected
        )
    }

    private func XCTAssertGoldenJSON(
        _ response: FenceResponse,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try response.jsonData()
        let actual = try XCTUnwrap(String(data: data, encoding: .utf8), file: file, line: line)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

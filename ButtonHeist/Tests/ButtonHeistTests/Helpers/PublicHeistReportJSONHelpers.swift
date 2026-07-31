import ButtonHeistTestSupport
import XCTest
import TheScore
@_spi(ButtonHeistTooling) @testable import ButtonHeist

func publicHeistReportJSON(_ response: FenceResponse) throws -> JSONProbe {
    try publicJSONProbe(response).object("report")
}

func assertPublicHeistSummary(
    _ summary: JSONProbe,
    executedTopLevelStepCount: Int,
    executedNodeCount: Int,
    outputNodeCount: Int,
    durationMs: Int,
    abortedAtPath: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try summary.int("executedTopLevelStepCount"), executedTopLevelStepCount, file: file, line: line)
    XCTAssertEqual(try summary.int("executedNodeCount"), executedNodeCount, file: file, line: line)
    XCTAssertEqual(try summary.int("outputNodeCount"), outputNodeCount, file: file, line: line)
    XCTAssertEqual(try summary.int("durationMs"), durationMs, file: file, line: line)
    if let abortedAtPath {
        XCTAssertEqual(try summary.string("abortedAtPath"), abortedAtPath, file: file, line: line)
    } else {
        try summary.assertMissing("abortedAtPath")
    }
}

func assertPublicElement(
    _ element: JSONProbe,
    traits: [String],
    label: String?,
    value: String? = nil,
    identifier: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try element.strings("traits"), traits, file: file, line: line)
    if let label {
        XCTAssertEqual(try element.string("label"), label, file: file, line: line)
    } else {
        try element.assertMissing("label")
    }
    if let value {
        XCTAssertEqual(try element.string("value"), value, file: file, line: line)
    } else {
        try element.assertMissing("value")
    }
    if let identifier {
        XCTAssertEqual(try element.string("identifier"), identifier, file: file, line: line)
    } else {
        try element.assertMissing("identifier")
    }
}

func assertPublicProjectionOmission(
    _ omission: JSONProbe,
    reason: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try omission.string("reason"), reason, file: file, line: line)
}

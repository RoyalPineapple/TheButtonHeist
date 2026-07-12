import ButtonHeistTestSupport
import XCTest
@_spi(ButtonHeistTooling) @testable import ButtonHeist

func publicHeistReportJSON(_ response: FenceResponse) throws -> JSONProbe {
    try publicJSONProbe(response).object("report")
}

func assertPublicHeistSummary(
    _ summary: JSONProbe,
    executedTopLevelStepCount: Int,
    executedNodeCount: Int,
    outputReceiptNodeCount: Int,
    durationMs: Int,
    abortedAtPath: String?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try summary.int("executedTopLevelStepCount"), executedTopLevelStepCount, file: file, line: line)
    XCTAssertEqual(try summary.int("executedNodeCount"), executedNodeCount, file: file, line: line)
    XCTAssertEqual(try summary.int("outputReceiptNodeCount"), outputReceiptNodeCount, file: file, line: line)
    XCTAssertEqual(try summary.int("durationMs"), durationMs, file: file, line: line)
    if let abortedAtPath {
        XCTAssertEqual(try summary.string("abortedAtPath"), abortedAtPath, file: file, line: line)
    } else {
        try summary.assertMissing("abortedAtPath")
    }
}

func assertPublicInteractionDigest(
    _ digest: JSONProbe,
    expected: AccessibilityTrace.InteractionDigest,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try digest.int("nodeCountBefore"), expected.nodeCountBefore, file: file, line: line)
    XCTAssertEqual(try digest.int("nodeCountAfter"), expected.nodeCountAfter, file: file, line: line)
    XCTAssertEqual(try digest.bool("nodeCountChanged"), expected.nodeCountChanged, file: file, line: line)
    XCTAssertEqual(try digest.bool("elementSetChanged"), expected.elementSetChanged, file: file, line: line)
    if let screenIdBefore = expected.screenIdBefore {
        XCTAssertEqual(try digest.string("screenIdBefore"), screenIdBefore, file: file, line: line)
    } else {
        try digest.assertMissing("screenIdBefore")
    }
    if let screenIdAfter = expected.screenIdAfter {
        XCTAssertEqual(try digest.string("screenIdAfter"), screenIdAfter, file: file, line: line)
    } else {
        try digest.assertMissing("screenIdAfter")
    }
    XCTAssertEqual(try digest.bool("screenIdChanged"), expected.screenIdChanged, file: file, line: line)
    XCTAssertEqual(try digest.bool("firstResponderChanged"), expected.firstResponderChanged, file: file, line: line)
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
    projectedAs: String?,
    omittedCount: Int?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    XCTAssertEqual(try omission.string("reason"), reason, file: file, line: line)
    if let projectedAs {
        XCTAssertEqual(try omission.string("projectedAs"), projectedAs, file: file, line: line)
    } else {
        try omission.assertMissing("projectedAs")
    }
    if let omittedCount {
        XCTAssertEqual(try omission.int("omittedCount"), omittedCount, file: file, line: line)
    } else {
        try omission.assertMissing("omittedCount")
    }
}

func assertAccessibilityTraceProjectedAsDelta(
    _ actionResult: JSONProbe,
    omittedCount: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try assertPublicProjectionOmission(
        actionResult.object("omitted").object("accessibilityTrace"),
        reason: ProjectionOmissionReason.rawAccessibilityTrace.rawValue,
        projectedAs: "delta",
        omittedCount: omittedCount,
        file: file,
        line: line
    )
}

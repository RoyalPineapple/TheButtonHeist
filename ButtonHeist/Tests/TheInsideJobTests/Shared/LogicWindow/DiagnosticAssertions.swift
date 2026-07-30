#if canImport(UIKit)
import XCTest

func XCTAssertDiagnostic(
    _ message: String?,
    contains fragments: [String] = [],
    doesNotContain excludedFragments: [String] = [],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let message else {
        return XCTFail("Expected diagnostic message", file: file, line: line)
    }
    for fragment in fragments {
        XCTAssertTrue(
            message.contains(fragment),
            "Expected diagnostic to contain '\(fragment)'. Message: \(message)",
            file: file,
            line: line
        )
    }
    for fragment in excludedFragments {
        XCTAssertFalse(
            message.contains(fragment),
            "Expected diagnostic to omit '\(fragment)'. Message: \(message)",
            file: file,
            line: line
        )
    }
}
#endif

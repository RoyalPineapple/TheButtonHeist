import XCTest

// Exit codes matching the CLI implementation
enum ExitCode: Int32 {
    case success = 0
    case connectionFailed = 1
    case noDeviceFound = 2
    case timeout = 3
    case unknown = 99
}

final class ExitCodeTests: XCTestCase {

    func testExitCodeValues() {
        XCTAssertEqual(ExitCode.success.rawValue, 0)
        XCTAssertEqual(ExitCode.connectionFailed.rawValue, 1)
        XCTAssertEqual(ExitCode.noDeviceFound.rawValue, 2)
        XCTAssertEqual(ExitCode.timeout.rawValue, 3)
        XCTAssertEqual(ExitCode.unknown.rawValue, 99)
    }

    func testSuccessIsZero() {
        // Unix convention: 0 means success
        XCTAssertEqual(ExitCode.success.rawValue, 0)
    }

    func testErrorCodesAreNonZero() {
        XCTAssertNotEqual(ExitCode.connectionFailed.rawValue, 0)
        XCTAssertNotEqual(ExitCode.noDeviceFound.rawValue, 0)
        XCTAssertNotEqual(ExitCode.timeout.rawValue, 0)
        XCTAssertNotEqual(ExitCode.unknown.rawValue, 0)
    }

    func testAllCodesUnique() {
        let codes: [ExitCode] = [.success, .connectionFailed, .noDeviceFound, .timeout, .unknown]
        let values = codes.map { $0.rawValue }
        let uniqueValues = Set(values)

        XCTAssertEqual(values.count, uniqueValues.count, "All exit codes should be unique")
    }
}
